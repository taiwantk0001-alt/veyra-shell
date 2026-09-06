#!/usr/bin/env bash
# 在 Mac / Codemagic 上执行，生成 ios-shell/base.ipa（未签名壳）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$ROOT/ios-shell/ShellApp.xcodeproj"
OUT_IPA="$ROOT/ios-shell/base.ipa"
DERIVED="$ROOT/ios-shell/.derived"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "错误：需要在安装了 Xcode 的 Mac 上运行本脚本。"
  exit 1
fi

rm -rf "$DERIVED" "$OUT_IPA"
mkdir -p "$DERIVED"

echo "==> xcodebuild -version"
xcodebuild -version

echo "==> 列出 schemes"
xcodebuild -project "$PROJ" -list

echo "==> 编译未签名 ShellApp（generic iOS）…"
xcodebuild \
  -project "$PROJ" \
  -scheme ShellApp \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  build

APP="$(find "$DERIVED/Build/Products" -name 'ShellApp.app' -type d | head -n 1)"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "错误：未找到 ShellApp.app"
  find "$DERIVED/Build/Products" -maxdepth 4 -print || true
  exit 1
fi

STAGE="$DERIVED/ipa-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"

echo "==> 打包 base.ipa…"
(
  cd "$STAGE"
  /usr/bin/zip -qr "$OUT_IPA" Payload
)

echo ""
echo "完成：$OUT_IPA"
ls -lh "$OUT_IPA"
