#!/bin/bash
# 打包 SourceGit.app
# 用法:
#   bash make-app.sh            # release 构建(默认)
#   bash make-app.sh debug      # debug 构建
#   UNIVERSAL=1 bash make-app.sh release   # 通用二进制(发布用)
#
# 说明:
#   - 构建走 scripts/dev.sh(swiftc 直编,见该文件头注释)
#   - 产物输出到 build/SourceGit.app
#   - APP_VERSION 是产品版本唯一来源(写入 Info.plist;发布 tag 需与之同步,见 PLAN.md §7.3)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="SourceGit"
BUNDLE_ID="com.zhangyang3.SourceGit"
CONFIG="${1:-release}"

# 版本号单一来源:Sources/GitCore/AppVersion.swift
APP_VERSION="$(sed -n 's/^.*static let current = "\([^"]*\)".*/\1/p' Sources/GitCore/AppVersion.swift)"
if [ -z "${APP_VERSION}" ]; then
    echo "错误:无法从 Sources/GitCore/AppVersion.swift 提取版本号" >&2
    exit 1
fi

export CONFIG
export UNIVERSAL="${UNIVERSAL:-0}"

echo "==> 构建 (${CONFIG}, UNIVERSAL=${UNIVERSAL})"
bash scripts/dev.sh build

BIN="build/${APP_NAME}"
if [ ! -f "${BIN}" ]; then
    echo "错误:找不到构建产物二进制 ${BIN}" >&2
    exit 1
fi

APP="build/${APP_NAME}.app"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/${APP_NAME}"

# 应用图标:由 scripts/make-icon.swift 生成(不提交二进制,构建时产出)
ICON_SRC="scripts/make-icon.swift"
ICON_ICNS="build/AppIcon.icns"
if [ ! -f "${ICON_ICNS}" ] || [ "${ICON_SRC}" -nt "${ICON_ICNS}" ]; then
    echo "==> 生成应用图标"
    rm -rf build/AppIcon.iconset build/IconGen
    /usr/bin/swiftc "${ICON_SRC}" -o build/IconGen
    ./build/IconGen
    iconutil -c icns build/AppIcon.iconset -o "${ICON_ICNS}"
    rm -rf build/AppIcon.iconset build/IconGen
fi
cp "${ICON_ICNS}" "${APP}/Contents/Resources/AppIcon.icns"

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-CN</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "${APP}/Contents/PkgInfo"

echo "==> 完成: ${APP} (v${APP_VERSION}, $(lipo -archs "${APP}/Contents/MacOS/${APP_NAME}" | tr '\n' ' '))"
