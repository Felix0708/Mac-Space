#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$project/.build/module-cache" "$project/dist"
stage="$(mktemp -d "$project/.build/app.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/여백.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$project/resources/Info.plist" "$app/Contents/Info.plist"
cp "$project/resources/Yeobaek.icns" "$app/Contents/Resources/Yeobaek.icns"
xcrun swiftc -parse-as-library -O -target arm64-apple-macos27.0 \
  -module-cache-path "$project/.build/module-cache" \
  "$project/src/SpaceModel.swift" "$project/src/YeobaekApp.swift" \
  -o "$app/Contents/MacOS/Space" -framework SwiftUI -framework AppKit
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
ditto "$app" "$project/dist/여백.app"
codesign --verify --deep --strict "$project/dist/여백.app"
echo "$project/dist/여백.app"
