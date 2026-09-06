#!/usr/bin/env bash
# 在 Mac + Xcode 上执行一次，生成 ios-shell/base.ipa（未签名壳，供服务器注入网页 + 轻松签签名）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$ROOT/ios-shell/ShellApp.xcodeproj"
OUT_IPA="$ROOT/ios-shell/base.ipa"
DERIVED="$ROOT/ios-shell/.derived"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "错误：需要在安装了 Xcode 的 Mac 上运行本脚本。"
  echo "Windows / Linux 服务器无法编译 iOS 壳。"
  exit 1
fi

rm -rf "$DERIVED"
mkdir -p "$DERIVED"

echo "==> 编译未签名 ShellApp（iphoneos）…"
xcodebuild \
  -project "$PROJ" \
  -scheme ShellApp \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  DEVELOPMENT_TEAM="" \
  build

APP="$(find "$DERIVED/Build/Products" -name 'ShellApp.app' -type d | head -n 1)"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "错误：未找到 ShellApp.app"
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
echo "把该文件放到服务器项目的 ios-shell/base.ipa，即可后台生成业务 IPA，再用轻松签签名。"
