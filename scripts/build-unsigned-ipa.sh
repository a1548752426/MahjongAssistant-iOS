#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate --spec project.yml

rm -rf build/DerivedData build/Payload build/MahjongAssistant-unsigned.ipa

xcodebuild \
  -project MahjongAssistant.xcodeproj \
  -scheme MahjongAssistant \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  clean build

APP_PATH="$(find build/DerivedData/Build/Products/Release-iphoneos -maxdepth 1 -name '*.app' -type d | head -n 1)"
if [[ -z "$APP_PATH" ]]; then
  echo "Release .app was not produced." >&2
  exit 1
fi

mkdir -p build/Payload
cp -R "$APP_PATH" build/Payload/
(
  cd build
  /usr/bin/zip -qry MahjongAssistant-unsigned.ipa Payload
)

echo "Created: $ROOT_DIR/build/MahjongAssistant-unsigned.ipa"

