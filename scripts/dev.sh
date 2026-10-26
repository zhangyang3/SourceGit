#!/bin/bash
# SourceGit 本地开发构建脚本(swiftc 直编,不依赖 SPM)
#
# 背景:本机 CLT(macOS 27.0)的 SwiftPM 存在 PackageDescription 模块与
# dylib 符号不匹配的缺陷,任何 manifest 都无法链接,故改用 swiftc 直接编译。
# CI 与本地共用本脚本,保证构建路径完全一致。
#
# 用法:
#   bash scripts/dev.sh build    # 编译应用 → build/SourceGit
#   bash scripts/dev.sh test     # 编译并运行测试 → build/SourceGitTests
#   bash scripts/dev.sh run      # 编译并启动应用
#
# 环境变量:
#   CONFIG=debug|release   默认 debug
#   UNIVERSAL=1            产出 arm64 + x86_64 通用二进制(发布用)
set -euo pipefail
cd "$(dirname "$0")/.."

CMD="${1:-build}"
CONFIG="${CONFIG:-debug}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p build

# 仅支持 Apple Silicon;固定部署目标为 macOS 14(与 Info.plist 的 LSMinimumSystemVersion 一致,
# 否则会用 SDK 默认 target,产物将无法在 macOS 14 运行)
FLAGS=(-sdk "$SDK" -swift-version 5 -target arm64-apple-macosx14.0)
case "$CONFIG" in
    release) FLAGS+=(-O) ;;
    debug)   FLAGS+=(-Onone -g) ;;
    *) echo "错误:CONFIG 只能是 debug 或 release(当前:$CONFIG)" >&2; exit 1 ;;
esac

case "$CMD" in
    build)
        find Sources/GitCore Sources/SourceGit -name '*.swift' | sort > build/app-sources.txt
        # CLT 缺 SwiftUIMacros 插件,@State 不可用;UI 状态一律用 @SGState(见 SwiftUICompat.swift)
        if grep -nE '@State[[:space:]]' $(cat build/app-sources.txt) 2>/dev/null; then
            echo "错误:检测到 @State(CLT 无 SwiftUIMacros 插件),请改用 @SGState" >&2
            exit 1
        fi
        if [ "${UNIVERSAL:-0}" = "1" ]; then
            echo "提示:本项目仅发布 Apple Silicon(arm64),已忽略 UNIVERSAL=1" >&2
        fi
        /usr/bin/swiftc "${FLAGS[@]}" -parse-as-library -o build/SourceGit @build/app-sources.txt
        echo "==> 应用已生成 build/SourceGit ($(lipo -archs build/SourceGit | tr '\n' ' '))"
        ;;
    test)
        # 测试与应用同语言模式。
        # 编译 GitCore + 界面层(排除带 @main 的 App.swift),以便对 UI 状态机做集成测试。
        find Tests Sources/GitCore -name '*.swift' | sort > build/test-sources.txt
        find Sources/SourceGit -name '*.swift' ! -name 'App.swift' | sort >> build/test-sources.txt
        /usr/bin/swiftc "${FLAGS[@]}" -o build/SourceGitTests @build/test-sources.txt
        ./build/SourceGitTests
        ;;
    run)
        # 用 bash 显式调用:脚本可能没有可执行权限(直接从 git 拉取时)
        bash "$0" build
        exec ./build/SourceGit
        ;;
    *)
        echo "用法: bash scripts/dev.sh [build|test|run]" >&2
        exit 1
        ;;
esac
