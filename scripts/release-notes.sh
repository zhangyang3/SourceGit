#!/bin/bash
# 生成 Release 发布说明(平铺版式:下载表格 + 安装说明 + 本次变更)
#
# 用法: bash scripts/release-notes.sh v0.1.0
# 输出: build/release-notes.md
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:-dev}"
REPO="${GITHUB_REPOSITORY:-zhangyang3/SourceGit}"
OUT="build/release-notes.md"
mkdir -p build

DMG="SourceGit-${TAG}-arm64.dmg"
ZIP="SourceGit-${TAG}-arm64-macos.zip"
BASE="https://github.com/${REPO}/releases/download/${TAG}"

cat > "$OUT" <<EOF
## 下载

| 系统要求 | 架构 | 安装包 | 备用格式 |
| --- | --- | --- | --- |
| macOS 14.0 或更高 | Apple Silicon (arm64) | [${DMG}](${BASE}/${DMG}) | [${ZIP}](${BASE}/${ZIP}) |

## 安装

1. 下载上面的 DMG 并打开,把 **SourceGit.app** 拖入「应用程序」;
2. 首次打开若被 Gatekeeper 拦截:右键 → 打开,或执行
   \`xattr -d com.apple.quarantine /Applications/SourceGit.app\`;
3. 之后可在 **设置(⌘,)→ 更新** 中开启自动检查更新,或用菜单「检查更新…」手动检查。

## 本次变更

EOF

# 变更列表:优先取该版本提交信息中的条目
if git rev-parse -q --verify "$TAG" >/dev/null 2>&1; then
    git log -1 --format=%B "$TAG" | grep -E '^- ' >> "$OUT" || true
fi
if [ ! -s "$OUT" ] || ! grep -qE '^- ' "$OUT"; then
    git log --oneline -10 --pretty='- %s' >> "$OUT"
fi

echo "==> 发布说明已生成: $OUT"
