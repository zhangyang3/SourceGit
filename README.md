# SourceGit

原生 Swift 编写的 macOS Git 图形客户端。功能完整,同时把内存占用压到最低:
空闲约 **38MB**,5 万提交仓库全量历史约 **57MB**。

[![CI](https://github.com/zhangyang3/SourceGit/actions/workflows/ci.yml/badge.svg)](https://github.com/zhangyang3/SourceGit/actions/workflows/ci.yml)
[![Release](https://github.com/zhangyang3/SourceGit/actions/workflows/release.yml/badge.svg)](https://github.com/zhangyang3/SourceGit/releases)

## 特性

### 仓库管理
- 打开本地仓库 / 从 URL 克隆 / 侧栏多仓库书签(移除书签不删除磁盘文件)
- 仓库列表持久化,重启自动恢复上次打开的仓库

### 工作副本
- 未暂存 / 已暂存分组,复选框或双击一键切换暂存
- 提交信息编辑器、修订上次提交(amend,自动预填原信息)、⌘⏎ 提交
- 放弃修改(二次确认,覆盖未跟踪文件与新增文件)
- 合并冲突标记 + 顶部横幅,支持一键终止合并
- 右键菜单:在 Finder 显示、用默认应用打开、复制路径

### 差异视图
- 统一 / 并排两种模式,行号槽、增删着色、二进制文件提示
- 大文件渲染上限(单文件 3000 行),超出提示截断,避免拖垮界面

### 历史
- 提交图形泳道:合并曲线、HEAD 强调、泳道循环配色
- 引用徽章:`HEAD → main`、本地分支、远程分支、标签
- 按分支 / 标签 / 远端过滤,按主题 / 作者 / 哈希前缀搜索
- 分页加载(默认 800 条,按需追加),1 万 / 5 万提交仓库滚动流畅
- 提交详情:作者头像、完整提交信息、变更文件列表,选中文件按需加载差异(带 LRU 缓存)

### 分支与远端
- 分支:创建(起点可选 HEAD / 本地 / 远程 / 标签)、切换(远程分支自动建跟踪分支)、删除、重命名
- 合并(--no-ff),冲突路径可恢复
- fetch(全部或单个远端)、pull(合并 / 变基 / 仅快进)、push(首次推送设置上游、force-with-lease)

### 贮藏
- 保存(可含未跟踪文件、可保留暂存区)、应用、弹出、删除

### 应用更新
- 检查 GitHub Releases 新版本,展示更新说明并跳转下载
- 更新配置:自动检查开关、频率(每次启动 / 每天 / 每周)、跳过指定版本、上次检查时间

### 体验细节
- 工具栏:提交 / 分支 / 切换 / 合并 / 获取 / 拉取 / 推送 / 贮藏 / 刷新 / 终端 / Finder
- 底部状态栏:当前分支、领先落后、未提交数量、过滤框
- 快捷键:⌘O 打开、⇧⌘N 克隆、⌘R 刷新、⌘1 工作副本、⌘2 历史、⌘F 过滤、⌘, 设置、⌘⏎ 提交
- 深浅色自适应

## 系统要求

- macOS 14.0 或更高
- Apple Silicon(arm64)

## 下载

从 [Releases](https://github.com/zhangyang3/SourceGit/releases) 下载对应架构的 DMG,把应用拖入「应用程序」即可。

> 产物为 ad-hoc 签名(未公证)。若被 Gatekeeper 拦截:右键 → 打开,或执行
> `xattr -d com.apple.quarantine /Applications/SourceGit.app`。

## 开发

### 构建与测试

```bash
bash scripts/dev.sh build        # 编译应用 → build/SourceGit
bash scripts/dev.sh run          # 编译并启动
bash scripts/dev.sh test         # 编译并运行测试(38 个用例)
bash make-app.sh                 # 打包 build/SourceGit.app
open build/SourceGit.app
```

### 目录结构

```
Sources/GitCore/     纯逻辑层:git 子进程封装、状态/历史/引用/diff/stash 解析、泳道算法、更新核心
Sources/SourceGit/   界面层:侧栏、工作副本、历史、差异视图、操作面板、设置
scripts/dev.sh       构建/测试/运行
scripts/perf.sh      性能基准:生成大仓库并采样内存
make-app.sh          打包 .app(版本号自 AppVersion.swift 提取)
```

### 构建方式说明

构建不依赖 Xcode 与 SwiftPM,采用 `swiftc` 直编脚本,本地与 CI 共用同一路径:

- 部分 Command Line Tools 的 SwiftPM 存在 `PackageDescription` 符号缺失缺陷,manifest 无法链接,故不采用 SPM;
- 界面层统一使用 `@SGState`(`Sources/SourceGit/SwiftUICompat.swift`)替代 `@State`——部分 SDK 中 `@State` 为宏实现,需要额外插件;`dev.sh` 会做静态检查,误用 `@State` 直接构建失败。

### 架构

- **GitCore**:只做 git 能力(封装 `git` 子进程,输出按机器可读格式解析),不依赖界面层,可独立测试
- **SourceGit**:`@MainActor` 状态机持有单一数据源,所有 git 调用在后台线程执行,结果回主线程刷新
- 内存策略:历史分页加载、diff 按需计算并缓存(LRU 32 项)、长列表懒渲染、解析即释放原始输出

## 发布

推送 `v*` 标签即自动构建 arm64 安装包、生成 `.dmg` 并发布 Release:

```bash
# 版本号单一来源:Sources/GitCore/AppVersion.swift,需与标签一致
git tag v0.1.0 && git push origin v0.1.0
```

CI 会对 `macos-14` 与 `macos-15` 两个环境做构建校验;标签与源码版本号不一致时发布流程会直接失败。
