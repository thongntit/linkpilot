#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
bin_path="$(swift build -c release --show-bin-path)"
app_path="${1:-$PWD/dist/LinkPilot.app}"
mkdir -p "$app_path/Contents/MacOS"
install -m 755 "$bin_path/LinkPilot" "$app_path/Contents/MacOS/LinkPilot"
install -m 644 Info.plist "$app_path/Contents/Info.plist"
codesign --force --sign - "$app_path"
codesign --verify --strict "$app_path"
printf '%s\n' "$app_path"
