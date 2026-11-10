#!/usr/bin/env bash
# Run on a Mac with Xcode + cmake. Builds libmgba.a for iOS (device).
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d third_party/mgba ] || git clone --depth 1 https://github.com/mgba-emu/mgba.git third_party/mgba
cmake -S third_party/mgba -B build/mgba-ios -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DBUILD_STATIC=ON -DBUILD_SHARED=OFF -DBUILD_QT=OFF -DBUILD_SDL=OFF -DBUILD_GL=OFF -DBUILD_GLES2=OFF \
  -DBUILD_LIBRETRO=OFF -DBUILD_TEST=OFF -DBUILD_EXAMPLE=OFF -DBUILD_PYTHON=OFF -DBUILD_HEADLESS=OFF \
  -DDISABLE_DEPS=ON -DM_CORE_GB=OFF -DM_CORE_GBA=ON -DUSE_ZLIB=ON -DUSE_PNG=OFF -DUSE_LIBZIP=OFF \
  -DUSE_SQLITE3=OFF -DUSE_ELF=OFF -DUSE_LZMA=OFF -DUSE_DISCORD_RPC=OFF -DUSE_EDITLINE=OFF -DENABLE_SCRIPTING=OFF
cmake --build build/mgba-ios --config Release --target mgba
cp -f build/mgba-ios/Release-iphoneos/libmgba.a build/mgba-ios/ 2>/dev/null || true
echo "Done. Now: xcodegen && open PhoenixGBA.xcodeproj"
