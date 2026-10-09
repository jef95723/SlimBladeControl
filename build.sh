#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Build requires macOS and Xcode Command Line Tools.' >&2
  exit 1
fi
source scripts/toolchain.sh
xcrun --find clang >/dev/null
bash tests/run.sh
app='build/SlimBlade Control.app'
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/AppIcon.iconset
xcrun clang -fobjc-arc -Wall -Wextra -Werror scripts/make_icon.m -framework Cocoa -o build/make_icon
build/make_icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O2 -mmacosx-version-min=12.0 \
  src/main.m src/actions.m src/interface.m src/shortcuts.m rust/target/release/libslimblade_core.a -liconv -lresolv -framework Cocoa -framework IOKit -framework ApplicationServices -framework Carbon -framework UniformTypeIdentifiers \
  -o "$app/Contents/MacOS/SlimBladeControl"
cp Info.plist "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Resources/Buttons"
cp assets/buttons/*.png "$app/Contents/Resources/Buttons/"
codesign --force --sign - --identifier org.local.SlimBladeControl "$app"
echo "Built $app. Move it to /Applications before granting permissions."
