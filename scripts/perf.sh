#!/bin/bash
# 性能基准:生成指定规模的临时仓库,启动应用并采样内存(phys_footprint)。
#
# 用法:
#   bash scripts/perf.sh                    # 默认 50000 提交,历史页(分页 800)
#   bash scripts/perf.sh 50000 all          # 全量加载 5 万条历史(SG_HISTORY_LIMIT)
#   bash scripts/perf.sh 10000 history
#   bash scripts/perf.sh 0 idle             # 不开仓库,仅测空闲
#
# 结果写入 docs/PERF.md 需手动更新(本脚本只打印)。
set -euo pipefail
cd "$(dirname "$0")/.."

COMMITS="${1:-50000}"
MODE="${2:-history}"
PERF_REPO=".perf-repo"
APP="build/SourceGit"

echo "==> 构建 (release)"
CONFIG=release bash scripts/dev.sh build >/dev/null

if [ "$COMMITS" = "0" ]; then
    echo '{"bookmarks":[],"selectedID":null}' > ~/Library/"Application Support"/SourceGit/bookmarks.json
    LAUNCH_ENV=()
else
    echo "==> 生成 ${COMMITS} 提交测试仓库 (fast-import)"
    rm -rf "$PERF_REPO"
    git init -q -b main "$PERF_REPO"
    python3 - "$COMMITS" > "$PERF_REPO/stream.fi" <<'PYEOF'
import sys
n = int(sys.argv[1])
print("blob\nmark :1\ndata 8\ncontent ")
for i in range(1, n + 1):
    msg = f"提交 #{i:06d}:例行变更".encode()
    body = f"content {i:06d}\n".encode()
    print("commit refs/heads/main")
    print(f"mark :{i + 1}")
    print(f"committer 性能测试 <perf@sourcegit.local> {1700000000 + i * 60} +0800")
    print(f"data {len(msg)}")
    print(msg.decode())
    if i > 1:
        print(f"from :{i}")
    print("M 100644 inline a.txt")
    print(f"data {len(body)}")
    print(body.decode(), end="")
print("done")
PYEOF
    git -C "$PERF_REPO" fast-import --quiet < "$PERF_REPO/stream.fi"
    rm "$PERF_REPO/stream.fi"
    cat > ~/Library/"Application Support"/SourceGit/bookmarks.json <<EOF
{"bookmarks":[{"name":"perf","path":"$PWD/$PERF_REPO","id":"33333333-3333-3333-3333-333333333333"}],"selectedID":"33333333-3333-3333-3333-333333333333"}
EOF
    if [ "$MODE" = "all" ]; then
        LAUNCH_ENV=(env SG_INITIAL_SECTION=history SG_HISTORY_LIMIT="$COMMITS")
    else
        LAUNCH_ENV=(env SG_INITIAL_SECTION=history)
    fi
fi

echo "==> 启动应用 (${MODE}, ${COMMITS} 提交)"
if [ "$COMMITS" = "0" ]; then
    "$APP" >/dev/null 2>&1 &
elif [ "$MODE" = "all" ]; then
    SG_INITIAL_SECTION=history SG_HISTORY_LIMIT="$COMMITS" "$APP" >/dev/null 2>&1 &
else
    SG_INITIAL_SECTION=history "$APP" >/dev/null 2>&1 &
fi
APP_PID=$!
sleep 6
# footprint 的 phys_footprint 行形如 "phys_footprint: 61.0M"(单位 MB)
sample() {
    footprint "$1" 2>/dev/null | grep -m1 "phys_footprint" | awk '{printf "%.0f", $2}'
}
echo "结果(phys_footprint, MB):"
echo "  启动 6s 后: $(sample $APP_PID) MB"
sleep 6
echo "  启动 12s 后(轮询稳态): $(sample $APP_PID) MB"

echo "==> 清理"
kill $APP_PID 2>/dev/null || true
sleep 1
rm -rf "$PERF_REPO"
echo '{"bookmarks":[],"selectedID":null}' > ~/Library/"Application Support"/SourceGit/bookmarks.json
