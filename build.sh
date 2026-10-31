#!/bin/zsh
# Builds Ritual.app without Xcode, using swiftc from the Command Line Tools.
#   ./build.sh            build + install to ~/Applications + launch
#   ./build.sh --demo     same, but launch with sample history (stored in demo.json)
#   ./build.sh --no-run   build + install only
#   ./build.sh --package  build only, leave build/Ritual.app for tools/make-dmg.sh
set -euo pipefail
cd "${0:A:h}"

VERSION=0.4.0

# The newest SDK can be ahead of the installed Swift compiler, so use the first one that type-checks
# a SwiftUI import: RITUAL_SDK if set, then the default, then each installed SDK from newest down.
pick_sdk() {
  local probe=$(mktemp -t ritual).swift
  echo 'import SwiftUI' > $probe
  for sdk in ${RITUAL_SDK:-} $(xcrun --show-sdk-path 2>/dev/null) $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX[0-9]*.*.sdk 2>/dev/null | sort -rV); do
    [[ -d $sdk ]] || continue
    if swiftc -sdk $sdk -target arm64-apple-macos15.0 -typecheck $probe >/dev/null 2>&1; then rm -f $probe; echo $sdk; return; fi
  done
  rm -f $probe
  echo "No macOS SDK works with this Swift compiler. Install or update the Command Line Tools: xcode-select --install" >&2
  exit 1
}
SDK=$(pick_sdk)
echo "→ using $(basename $SDK)"
TARGET=arm64-apple-macos15.0
BUILD=build
APP=$BUILD/Ritual.app
DEST=~/Applications/Ritual.app

rm -rf $APP
mkdir -p $APP/Contents/{MacOS,Resources}

echo "→ compiling app"
swiftc -sdk $SDK -target $TARGET -O -parse-as-library -swift-version 5 \
  -module-name Ritual \
  Shared/*.swift App/*.swift \
  -o $APP/Contents/MacOS/Ritual

cat > $APP/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.local.ritual</string>
  <key>CFBundleName</key><string>Ritual</string>
  <key>CFBundleDisplayName</key><string>Ritual</string>
  <key>CFBundleExecutable</key><string>Ritual</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.healthcare-fitness</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>dev.local.ritual</string>
    <key>CFBundleURLSchemes</key><array><string>ritual</string></array>
  </dict></array>
</dict></plist>
PLIST

echo "→ compiling widgets"
WX=$APP/Contents/PlugIns/RitualWidgets.appex
mkdir -p $WX/Contents/MacOS
swiftc -sdk $SDK -target $TARGET -O -parse-as-library -swift-version 5 -application-extension \
  -module-name RitualWidgets \
  Shared/*.swift Widgets/*.swift \
  -o $WX/Contents/MacOS/RitualWidgets

# Widget habit picker needs App Intents metadata. Only Xcode ships the processor; skip quietly without it.
XTC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain
XSDK=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
if [[ -x $XTC/usr/bin/appintentsmetadataprocessor ]]; then
  echo "→ widget intents metadata"
  AIM=$BUILD/intents; rm -rf $AIM; mkdir -p $AIM
  ls $PWD/Shared/*.swift $PWD/Widgets/*.swift > $AIM/sources.txt
  echo '["AppIntent","EntityQuery","AppEntity","AppEnum","WidgetConfigurationIntent","DynamicOptionsProvider","AppShortcutsProvider"]' > $AIM/protocols.json
  $XTC/usr/bin/swiftc -sdk $XSDK -target $TARGET -swift-version 5 -parse-as-library -application-extension -module-name RitualWidgets -wmo \
    -emit-const-values -Xfrontend -const-gather-protocols-file -Xfrontend $AIM/protocols.json \
    -c $(cat $AIM/sources.txt) -o $AIM/w.o -emit-const-values-path $AIM/RitualWidgets.swiftconstvalues >/dev/null 2>&1 \
  && echo $AIM/RitualWidgets.swiftconstvalues > $AIM/cv.txt \
  && $XTC/usr/bin/appintentsmetadataprocessor --output $AIM/out --toolchain-dir $XTC --module-name RitualWidgets \
       --sdk-root $XSDK --xcode-version 16F6 --platform-family macOS --deployment-target 15.0 --target-triple $TARGET \
       --source-file-list $AIM/sources.txt --swift-const-vals-list $AIM/cv.txt --force >/dev/null 2>&1 \
  && mkdir -p $WX/Contents/Resources && cp -R $AIM/out/Metadata.appintents $WX/Contents/Resources/ \
  || echo "  (skipped: intents metadata failed; widgets still work, habit picker may not)"
fi

cat > $WX/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.local.ritual.widgets</string>
  <key>CFBundleName</key><string>RitualWidgets</string>
  <key>CFBundleDisplayName</key><string>Ritual</string>
  <key>CFBundleExecutable</key><string>RitualWidgets</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSExtension</key><dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
  </dict>
</dict></plist>
PLIST

if [[ ! -f $BUILD/AppIcon.icns ]]; then
  echo "→ drawing icon"
  swiftc -sdk $SDK -target $TARGET -O tools/MakeIcon.swift -o $BUILD/makeicon
  $BUILD/makeicon $BUILD/AppIcon.iconset
  iconutil -c icns $BUILD/AppIcon.iconset -o $BUILD/AppIcon.icns
fi
cp $BUILD/AppIcon.icns $APP/Contents/Resources/
mkdir -p $WX/Contents/Resources
cp Resources/Fonts/*.ttf Resources/Fonts/OFL-*.txt $APP/Contents/Resources/
cp Resources/Fonts/*.ttf $WX/Contents/Resources/

# Real widgets need a real certificate: macOS drops widgets from ad-hoc signed apps.
# Pick up a free "Apple Development" identity if one is in the keychain; override with RITUAL_SIGN_ID.
SIGN_ID=${RITUAL_SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')}
SIGN_ID=${SIGN_ID:--}
if [[ $SIGN_ID == "-" ]]; then
  echo "→ signing (ad-hoc: widgets won't appear in the gallery until an Apple Development certificate is installed)"
else
  echo "→ signing with $(security find-identity -v -p codesigning | awk -v id=$SIGN_ID -F'"' '$0 ~ id {print $2; exit}')"
fi
# Widgets must be sandboxed; they get read-only access to the app's data folder.
cat > $BUILD/widgets.entitlements <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.temporary-exception.files.home-relative-path.read-only</key>
  <array><string>/Library/Application Support/Ritual/</string></array>
</dict></plist>
PLIST
plutil -replace CFBundleShortVersionString -string $VERSION $APP/Contents/Info.plist
plutil -replace CFBundleShortVersionString -string $VERSION $WX/Contents/Info.plist
codesign --force --sign $SIGN_ID --timestamp=none --options runtime --entitlements $BUILD/widgets.entitlements $WX
codesign --force --sign $SIGN_ID --timestamp=none --options runtime $APP

if [[ "${1:-}" == "--package" ]]; then echo "✓ Ritual $VERSION built at $APP"; exit 0; fi

echo "→ installing to $DEST"
pkill -x Ritual 2>/dev/null && sleep 0.5 || true
rm -rf $DEST
mkdir -p ~/Applications
cp -R $APP $DEST

# register the bundle so the widget gallery and ritual:// links find it
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f $DEST >/dev/null 2>&1 || true
pluginkit -a $DEST/Contents/PlugIns/RitualWidgets.appex 2>/dev/null || true

if [[ "${1:-}" != "--no-run" ]]; then
  if [[ "${1:-}" == "--demo" ]]; then open $DEST --args --demo; else open $DEST; fi
fi
echo "✓ Ritual built"
