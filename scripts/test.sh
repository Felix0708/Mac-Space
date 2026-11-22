#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$project/.build/module-cache"
xcrun swiftc -parse-as-library -target arm64-apple-macos27.0 \
  -module-cache-path "$project/.build/module-cache" \
  "$project/src/SpaceModel.swift" "$project/tests/SpaceModelTests.swift" \
  -o "$project/.build/SpaceModelTests" -framework SwiftUI -framework AppKit
"$project/.build/SpaceModelTests"
