import AppKit
import SwiftUI
import SceneKit

/// Development aid: `RITUAL_SNAPSHOT=<dir> Ritual` writes PNGs of the main window for each tab and skin,
/// then quits. SceneKit views are composited in from their own snapshot() since cacheDisplay skips Metal layers.
@MainActor
enum DebugSnapshot {
    private static var fallback: NSWindow?
    static var directory: URL? {
        // An env var, not an argument: AppKit treats trailing path arguments as files to open.
        guard let path = ProcessInfo.processInfo.environment["RITUAL_SNAPSHOT"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func run(store: Store, skins: [String], tabs: [Tab]) {
        guard let dir = directory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            // A closed main window isn't reopened at launch; host one ourselves so there's something to capture.
            if !NSApp.windows.contains(where: { $0.isVisible && $0.frame.width > 400 }) {
                let w = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1320, height: 820), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                w.titlebarAppearsTransparent = true
                w.contentView = NSHostingView(rootView: MainWindow().environment(store))
                w.orderFrontRegardless()
                fallback = w
                try? await Task.sleep(for: .seconds(1.5))
            }
            for skin in skins where !skins.isEmpty {
                var s = store.settings; s.skin = skin; store.setSettings(s)
                for tab in tabs {
                    NotificationCenter.default.post(name: .ritualShowTab, object: tab)
                    try? await Task.sleep(for: .seconds(1.6))
                    capture(to: dir.appendingPathComponent("\(skin)-\(tab.rawValue.lowercased()).png"))
                }
                // done state of the orb, then put the data back
                NotificationCenter.default.post(name: .ritualShowTab, object: Tab.today)
                if let id = store.selected?.id, store.check(id) {
                    try? await Task.sleep(for: .seconds(1.8))
                    capture(to: dir.appendingPathComponent("\(skin)-today-done.png"))
                    store.uncheck(id)
                }
            }
            // sheets and the settings window
            let sheets: [(Notification.Name, String)] = [(.ritualEdit, "sheet-editor"), (.ritualShelf, "sheet-shelf"), (.ritualGuide, "sheet-guide")]
            NotificationCenter.default.post(name: .ritualShowTab, object: Tab.today)
            for (name, file) in sheets {
                NotificationCenter.default.post(name: name, object: nil)
                try? await Task.sleep(for: .seconds(1.6))
                captureSheet(to: dir.appendingPathComponent("\(file).png"))
                NotificationCenter.default.post(name: .ritualDismissSheets, object: nil)
                try? await Task.sleep(for: .seconds(0.9))
            }
            NotificationCenter.default.post(name: .ritualShowTab, object: Tab.tasks)
            try? await Task.sleep(for: .seconds(0.8))
            NotificationCenter.default.post(name: .ritualEditTask, object: nil)
            try? await Task.sleep(for: .seconds(1.6))
            captureSheet(to: dir.appendingPathComponent("sheet-task-editor.png"))
            NotificationCenter.default.post(name: .ritualDismissSheets, object: nil)
            try? await Task.sleep(for: .seconds(0.9))
            // settings pages rendered offscreen (window capture can't see ScrollView layers)
            for page in SettingsView.Page.allCases {
                let r = ImageRenderer(content: SettingsContent(page: page).padding(24).frame(width: 620, alignment: .topLeading).background(SkinBackground()).environment(store).environment(\.skin, store.skin))
                r.scale = 1
                if let img = r.nsImage, let t = img.tiffRepresentation, let b = NSBitmapImageRep(data: t) {
                    try? b.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("settings-\(page.id.replacingOccurrences(of: " ", with: "")).png"))
                }
            }
            UserDefaults.standard.set("Groups & habits", forKey: "ritual.debug.settingsPage")
            NotificationCenter.default.post(name: .ritualSettings, object: nil)
            try? await Task.sleep(for: .seconds(2.5))
            if let w = NSApp.windows.first(where: { $0.title == "Ritual Settings" && $0.isVisible }) {
                w.makeKeyAndOrderFront(nil)
                w.displayIfNeeded()
                try? await Task.sleep(for: .seconds(0.8))
                if let v = w.contentView, let layer = v.layer {
                    let size = v.bounds.size, scale: CGFloat = 2
                    if let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                        ctx.scaleBy(x: scale, y: scale)
                        if !v.isFlipped { } else { ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1) }
                        layer.render(in: ctx)
                        if let img = ctx.makeImage() {
                            try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("window-settings.png"))
                        }
                    }
                }
            }
            NSApp.terminate(nil)
        }
    }

    private static func capture(to url: URL) {
        let candidates = NSApp.windows.filter { $0.isVisible && $0.frame.width > 400 }
        guard let window = candidates.first, let view = window.contentView else { NSLog("Ritual snapshot: no window"); return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds),
              let ui = view.bitmapImageRepForCachingDisplay(in: bounds) else { NSLog("Ritual snapshot: no rep"); return }
        view.cacheDisplay(in: bounds, to: ui)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        ui.draw(in: bounds)
        for scn in allSCNViews(in: view) {
            let img = scn.snapshot()
            // window coordinates are bottom-left based, matching the bitmap context
            var frame = scn.convert(scn.bounds, to: nil)
            frame.origin.x -= view.convert(view.bounds, to: nil).minX
            frame.origin.y -= view.convert(view.bounds, to: nil).minY
            img.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
        }
        // labels and controls sit above the 3D view in the real window; paint the UI again with the
        // SceneKit areas masked out so text over the orb shows
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.saveGState()
        if let img = ui.cgImage {
            ctx.setBlendMode(.normal)
            let opaque = NSImage(cgImage: img, size: bounds.size)
            opaque.draw(in: bounds, from: .zero, operation: .sourceAtop, fraction: 0)
        }
        ctx.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        do { try rep.representation(using: .png, properties: [:])?.write(to: url) } catch { NSLog("Ritual snapshot: \(error)") }
    }

    private static func captureSheet(to url: URL) {
        guard let sheet = NSApp.windows.compactMap(\.attachedSheet).first ?? NSApp.windows.first(where: { $0.isSheet }),
              let view = sheet.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func allSCNViews(in v: NSView) -> [SCNView] {
        (v as? SCNView).map { [$0] } ?? v.subviews.flatMap(allSCNViews)
    }
}
