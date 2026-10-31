import AppKit
import AVFoundation

/// Synthesized sounds (no audio files to license) plus trackpad haptics.
@MainActor
final class Feedback {
    static let shared = Feedback()
    var soundOn = true
    var hapticsOn = true
    var volume = 0.6 { didSet { engine.mainMixerNode.outputVolume = Float(volume) * 0.9 } }

    private let engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var started = false

    enum Sound: CaseIterable { case tick, done, levelUp, undo }

    private init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.55
        for s in Sound.allCases { buffers[s] = Self.render(s, format: format) }
    }

    func play(_ s: Sound) {
        guard soundOn, let buf = buffers[s] else { return }
        if !started {
            do { try engine.start(); started = true } catch { NSLog("Ritual: audio unavailable: \(error)"); return }
        }
        player.scheduleBuffer(buf, at: nil, options: [])
        if !player.isPlaying { player.play() }
    }

    func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .levelChange) {
        guard hapticsOn else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    // MARK: Synthesis

    private struct Note { let f: Double; let at: Double; let len: Double; let gain: Double; let shape: Shape }
    private enum Shape { case sine, tri, bell }

    private static func notes(_ s: Sound) -> [Note] {
        switch s {
        case .tick:
            return [Note(f: 1760, at: 0, len: 0.035, gain: 0.25, shape: .tri)]
        case .undo:
            return [Note(f: 392, at: 0, len: 0.12, gain: 0.35, shape: .sine), Note(f: 294, at: 0.07, len: 0.16, gain: 0.3, shape: .sine)]
        case .done:
            let chord = [523.25, 659.25, 783.99, 1046.5]
            return [Note(f: 130.8, at: 0, len: 0.4, gain: 0.6, shape: .sine)]
                + chord.enumerated().map { Note(f: $1, at: Double($0) * 0.05, len: 0.6, gain: 0.28, shape: .bell) }
        case .levelUp:
            let run = [523.25, 659.25, 783.99, 1046.5, 1318.5, 1568]
            return [Note(f: 98, at: 0, len: 0.8, gain: 0.55, shape: .sine)]
                + run.enumerated().map { Note(f: $1, at: Double($0) * 0.075, len: 0.9, gain: 0.22, shape: .bell) }
        }
    }

    private static func render(_ s: Sound, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let ns = notes(s)
        let sr = format.sampleRate
        let total = (ns.map { $0.at + $0.len }.max() ?? 0.1) + 0.05
        let frames = AVAudioFrameCount(total * sr)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let out = buf.floatChannelData![0]
        for i in 0..<Int(frames) { out[i] = 0 }
        for n in ns {
            let start = Int(n.at * sr), count = Int(n.len * sr)
            for j in 0..<count where start + j < Int(frames) {
                let t = Double(j) / sr
                let attack = min(1, t / 0.004)
                let env = attack * exp(-t * (n.shape == .bell ? 5.5 : 9) / max(n.len, 0.05) * 0.5)
                let ph = 2 * Double.pi * n.f * t
                let v: Double
                switch n.shape {
                case .sine: v = sin(ph)
                case .tri: v = asin(sin(ph)) * 2 / .pi
                case .bell: v = sin(ph) * 0.7 + sin(ph * 2.01) * 0.2 + sin(ph * 3.98) * 0.1
                }
                out[start + j] += Float(v * env * n.gain)
            }
        }
        var peak: Float = 0
        for i in 0..<Int(frames) { peak = max(peak, abs(out[i])) }
        if peak > 0.95 { for i in 0..<Int(frames) { out[i] *= 0.95 / peak } }
        return buf
    }
}
