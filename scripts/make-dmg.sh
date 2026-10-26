#!/bin/bash
# 生成 SourceGit 安装 DMG(含「拖入 Applications」入口)
#
# 用法:
#   bash scripts/make-dmg.sh v0.1.0
#
# 说明:
#   - 需要先执行 make-app.sh 生成 build/SourceGit.app
#   - DMG 内含:SourceGit.app + 指向 /Applications 的符号链接(拖拽安装)
#   - 产物:build/SourceGit-<tag>-arm64.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:-dev}"
APP="build/SourceGit.app"
if [ ! -d "${APP}" ]; then
    echo "错误:未找到 ${APP},请先执行 bash make-app.sh" >&2
    exit 1
fi

STAGE="build/dmg-stage"
DMG="build/SourceGit-${TAG}-arm64.dmg"

rm -rf "${STAGE}"
mkdir -p "${STAGE}"
cp -R "${APP}" "${STAGE}/SourceGit.app"
# 拖拽安装入口
ln -s /Applications "${STAGE}/Applications"

rm -f "${DMG}"
hdiutil create -volname "SourceGit" -srcfolder "${STAGE}" -ov -format UDZO "${DMG}" >/dev/null
rm -rf "${STAGE}"

echo "==> 已生成 ${DMG} ($(du -h "${DMG}" | cut -f1))"
