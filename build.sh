#!/bin/bash
set -e

swift build -c release

cp .build/release/Shotty Shotty.app/Contents/MacOS/Shotty
cp Shotty/Sources/App/Resources/Info.plist Shotty.app/Contents/Info.plist
cp Shotty/Sources/App/Resources/AppIcon.icns Shotty.app/Contents/Resources/AppIcon.icns

codesign --force --deep --sign - Shotty.app
echo "Done — run: open Shotty.app"
