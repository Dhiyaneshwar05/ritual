#!/bin/zsh
# Builds Ritual and wraps it in a drag-to-Applications disk image: build/Ritual-<version>.dmg
set -euo pipefail
cd "${0:A:h}/.."
./build.sh --package
APP=build/Ritual.app
VERSION=$(plutil -extract CFBundleShortVersionString raw $APP/Contents/Info.plist)
STAGE=$(mktemp -d -t ritual-dmg)
DMG=build/Ritual-$VERSION.dmg
cp -R $APP $STAGE/
ln -s /Applications $STAGE/Applications
rm -f $DMG
hdiutil create -volname "Ritual $VERSION" -srcfolder $STAGE -fs HFS+ -format UDZO -ov $DMG >/dev/null
rm -rf $STAGE
echo "✓ $DMG ($(du -h $DMG | cut -f1))"
