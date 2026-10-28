# SourceGit for macOS — 工作计划

> 原生 Swift 编写的 macOS Git 图形客户端,目标:**功能完整的前提下把内存占用压到最低**。
>
> - 远程仓库:https://github.com/zhangyang3/SourceGit.git
> - 文档版本:v1(2026-10-26)

---

## 1. 目标与非目标

### 1.1 目标

| 维度 | 指标 |
|---|---|
| 平台 | 仅 macOS,最低 macOS 14 |
| 交互 | 侧栏仓库 + 工作副本 + 历史图形 + 分支 + 远端 + 贮藏 |
| **内存(硬指标)** | 空闲 < 60MB;中型仓库(≤5 万提交)日常操作峰值 < 150MB;大仓库峰值 < 300MB |
| 启动 | 冷启动 < 1.5s |
| 构建 | 脚本构建(`scripts/dev.sh`,swiftc 直编),本地与 CI 同路径;不依赖 Xcode/SPM | 本机 CLT(macOS 27.0)SwiftPM 存在 PackageDescription 模块与 dylib 符号不匹配的缺陷,任何 manifest 均无法链接,故弃用 SPM;日后修复 CLT 或安装 Xcode 后可回归 SPM |
| CI/CD | GitHub Actions:push/PR 自动构建+测试;打 `v*` tag 自动打包 `.dmg` 并发布 Release(见 §7) |

### 1.2 非目标(MVP 明确不做)

- 交互式 rebase 编辑器、submodule 深度管理、blame 视图、Git LFS 专属界面、SSH 密钥管理 GUI、shelve
- 多窗口/标签页(先单窗口多仓库切换)
- iOS/catalyst 适配

---

## 2. 为什么原生方案内存低 — 设计期就锁定的原则

内存性能**从架构层面约束,不做"事后优化"**:

1. **无嵌入式运行时**:不内嵌 WebView/Node/Chromium,纯 SwiftUI + 少量 AppKit,无 HTML 渲染管线。
2. **数据按需加载**:
   - 提交历史分页加载(默认 800 条,底部"加载更多"),绝不一次性拉全量;
   - Diff 只在**选中某文件时**才调用 git 计算,不预计算整个提交的所有文件 diff。
3. **渲染虚拟化**:
   - 提交列表/文件列表用 `LazyVStack`(行视图懒构建);
   - 单个超大 diff 文件默认只渲染前 3000 行,超出显示"加载更多行",避免一次构建上万 SwiftUI 视图;
   - 若实测仍不达标,关键长列表降级为 `NSTableView` 包装(风险预案,见 §8)。
4. **解析不留双份**:git 输出用块读取 + 循环内 `autoreleasepool`,解析产物为轻量值类型(struct,单条提交 ~200B),解析完立即释放原始字符串。
5. **单一数据源**:`RepoModel` 是唯一状态持有者,视图全部引用,不复制快照。
6. **轮询节流**:后台每 5s 仅执行一次 `git status --no-optional-locks`(成本低),不做常驻文件监听队列;窗口失焦自动暂停轮询。
7. **缓存有上限**:diff 结果做 LRU 缓存(上限 32 个文件),超限淘汰;提交图泳道数据随分页重建,不无限累积。
8. **轻量高亮**:diff 着色用自绘前景/背景色,不引入语法高亮三方库。

**度量手段**(无 Instruments GUI 的替代):`footprint <pid>`、`leaks <pid>`、活动监视器;每次性能里程碑把数据记入 `docs/PERF.md`。

---

## 3. 技术选型

| 项 | 选择 | 理由 |
|---|---|---|
| UI 框架 | SwiftUI(macOS 14+),文件选择等用 AppKit | 开发效率高;内存友好 |
| Git 后端 | 调用系统 `/usr/bin/git` 子进程 | 与 sourcegit-scm/sourcegit 同思路;功能全覆盖、零链接库开销;libgit2 在无 Xcode 环境构建维护成本高 |
| 输出协议 | `--porcelain -z`、`--pretty=format`(自定义分隔符) | 机器可读、稳定、支持中文/空格路径 |
| 语言模式 | Swift 5(`dev.sh` 中 `-swift-version 5`) | 规避 Swift 6 严格并发的初期摩擦,稳定后再评估迁移 |
| 打包 | `make-app.sh` 生成 `.app`(Info.plist/PkgInfo),后续 ad-hoc 签名 | 无 Xcode 也可产出可双击运行的应用 |

---

## 4. 架构与模块

```
Sources/
  GitCore/                 # 纯逻辑层,不依赖 UI,可独立验证
    Git.swift              # Process 封装:参数、环境、退出码、stdout/stderr 收集
    Models.swift           # WorktreeFile / RepoStatus / GitCommit / GitBranch /
                           # GitTag / GitRemote / GitStash / CommitRef
    GitRepository.swift    # 高层 API:status/log/diff/stage/commit/branch/
                           # fetch/pull/push/merge/stash/clone…
    DiffParser.swift       # unified diff → DiffFile / DiffHunk / DiffLine
    GraphBuilder.swift     # 提交图泳道(lane)算法:行数据 + 连线曲线
  SourceGit/               # UI 层
    App.swift              # @main、菜单、快捷键
    AppState.swift         # 仓库书签管理 + 持久化(JSON,Application Support)
    RepoModel.swift        # @MainActor 单仓库状态机:刷新、轮询、动作、错误
    MainView.swift         # 布局骨架:侧栏 + 上下分栏 + 工具栏 + 底部状态栏
    SidebarView.swift      # 侧栏(仓库组/状态/历史/分支/标签/远端/贮藏)
    WorkcopyView.swift     # 未暂存/已暂存分组、复选框暂存、提交编辑器
    HistoryView.swift      # 提交列表(图形列+ref 标签)、搜索、加载更多
    CommitDetailView.swift # 选中提交:元信息 + 变更文件列表 + diff
    DiffView.swift         # 统一 / 并排两种视图,行号槽,增删着色
    CommitGraphView.swift  # Canvas 自绘泳道图
    Sheets.swift           # 克隆/建分支/切换/合并/拉取/推送/贮藏/确认框
  tests 冒烟:GitCoreSmoke(可选 executable target,跑解析用例)
scripts/dev.sh / make-app.sh / README.md / docs/PERF.md
```

**数据流**:`View → RepoModel(@MainActor) → Task.detached → GitCore → git 子进程 → 解析 → @Published → View`。
所有 git 调用都带 `-z`/自定义分隔符、`core.quotepath=false`、`GIT_OPTIONAL_LOCKS=0`。

---

## 5. UI 规格(侧栏 + 上下分栏布局)

- **左侧栏**
  - 顶部:仓库列表(右键移除、在 Finder 显示);
  - 当前仓库分组:工作副本(带未提交计数)/ 历史;
  - 可折叠:分支(本地 + 远程,当前分支加粗 ✓,上游显示 ↑n ↓n)/ 标签 / 远端(可展开其分支)/ 贮藏。
- **主区**上下分栏(可拖动):
  - 工作副本页:上=左文件分组列表 + 右提交信息编辑器与提交按钮;下=选中文件 diff;
  - 历史页:上=提交列表(泳道图形列 + 主题 + 作者 + 相对时间 + ref 徽章 `HEAD -> main`、`origin/main`、`tag: v1`);下=提交详情(元信息 + 文件列表 + diff);
  - 点击侧栏具体分支/标签/远端 → 历史页按该 ref 过滤。
- **工具栏**:提交 / 分支 / 切换 / 合并 / 获取 / 拉取 / 推送 / 贮藏 / 终端 / 刷新(图标+文字)。
- **底部状态栏**:当前分支徽章 + ahead/behind + 未提交数 + 过滤搜索框。
- **合并冲突**:顶部横幅提示"合并进行中",冲突文件在列表中特殊标记,提供"终止合并"。

---

## 6. 里程碑与排期(总计约 8 人日)

| 里程碑 | 内容 | 交付物 | 验收标准 | 工期 |
|---|---|---|---|---|
| **M0 骨架** | scripts/dev.sh(swiftc 直编 + 测试工具)、make-app.sh、README、目录结构、GitHub Actions(CI + Release) | 可构建的空窗口 `.app`;CI 绿灯 | `bash make-app.sh && open build/SourceGit.app` 出空窗口;push 后 CI 通过 | 1d |
| **M1 GitCore** | 进程封装、status/log/refs/diff/stash 解析、泳道算法 | GitCore + 冒烟验证 | 对真实仓库解析无错;中文路径、空仓库、detached HEAD 不崩 | 1.5d |
| **M2 仓库+工作副本** | 打开/克隆仓库、侧栏、暂存/取消暂存/放弃/提交、diff 视图(统一+并排) | 可日常提交的客户端 | 暂存→提交→状态刷新闭环;差分渲染正确 | 1.5d |
| **M3 历史** | 泳道图形、提交详情、按分支/标签/远端过滤、搜索、分页 | 历史页完整 | 1 万提交仓库滚动流畅,内存不随滚动上涨 | 1d |
| **M4 分支与远端** | 建分支/切换/删除/合并、fetch/pull/push(上游设置、force-with-lease)、stash 增删应用 | 远端操作闭环 | 与 GitHub 远程仓库完成 push/pull;冲突路径可恢复 | 1d |
| **M5 性能治理** | 大仓库基准、footprint 记录、diff 行数上限、LRU 缓存、轮询暂停 | docs/PERF.md + 优化 | 达成 §1.1 内存预算;5 万提交仓库达标 | 1d |
| **M6 打磨发布** | 快捷键、空态/错误态统一、README 截图、ad-hoc 签名、**应用更新机制(GitHub Releases 检查更新 + 更新配置;签名自动安装进 backlog)** | v0.1.0 发布包(由 Release workflow 自动产出) | 干净机器可运行;打 `v0.1.0` tag 后 Release 页出现 `.dmg`;检查更新可用 | 1d |

每个里程碑完成即 git commit,按 `M0-骨架` 格式写提交信息。

---

## 7. CI/CD 与发布(GitHub Actions)

仓库:`https://github.com/zhangyang3/SourceGit.git`,workflow 位于 `.github/workflows/`。

### 7.1 持续集成(`ci.yml`)

- **触发**:push 到 `master`/`main`、所有 PR、支持手动触发(workflow_dispatch);并发去重(同分支新提交自动取消旧任务)。
- **矩阵**:`macos-14` + `macos-15` 双 runner,同时验证最低支持系统与最新系统。
- **步骤**:环境信息 → `bash scripts/dev.sh build`(Debug)→ `bash scripts/dev.sh test`(M1 起逐步补齐解析/泳道算法用例)→ `bash make-app.sh release` 打包冒烟(校验 `.app` 结构)。

### 7.2 自动打包发布(`release.yml`)

- **触发**:推送 `v*` tag(如 `git tag v0.1.0 && git push --tags`),或手动指定版本号触发。
- **产物**:通用二进制(`--arch arm64 --arch x86_64`,失败则回退当前架构)→ `make-app.sh` 生成 `.app` → ad-hoc 签名(`codesign --force --deep -s -`)→ `ditto` 压缩 zip + `hdiutil` 生成 `.dmg`。
- **发布**:`gh release create <tag> --generate-notes` 附上 `.dmg` 与 `.zip`;tag 已存在时改为 `gh release upload --clobber`(支持重跑覆盖产物)。
- **说明**:无 Apple 开发者账号,不做公证(notarize);用户首次打开需右键→打开,或 `xattr -d com.apple.quarantine` 去隔离。后续有证书再在 workflow 中追加 notarytool 步骤。

### 7.3 版本规范

- 版本号写于 `make-app.sh`/Info.plist(单一来源,变量 `APP_VERSION`),发布前手动改版本 → 打 tag → CI 自动出包,tag 与版本号必须一致。
- Release Notes 由 `--generate-notes` 按 PR/commit 自动生成。

---

## 8. 测试与验收清单

- **功能冒烟**:新建/打开/克隆仓库 → 修改+暂存+提交 → 建分支/切换/合并(含冲突)→ fetch/pull/push → stash 保存/应用/删除 → 放弃修改 → 中文与空格路径 → 空仓库首提交 → detached HEAD 浏览。
- **性能场景**:
  - 5 万提交仓库(可用 `git fast-import` 生成)打开历史页;
  - 单文件 1 万行 diff 打开;
  - 1000 个变更文件的工作副本状态页;
  - 记录空闲/打开/滚动/大 diff 四个时点的 `footprint`。
- **回归**:每次里程碑跑一遍冒烟清单。

---

## 9. 风险与预案

| 风险 | 影响 | 预案 |
|---|---|---|
| 无 Xcode,无 Instruments GUI | 性能分析受限 | 用 `footprint`/`leaks`/`sample` 命令行;必要时安装 Xcode 仅用于分析 |
| SwiftUI 长列表性能不达标 | 滚动卡顿、内存上涨 | 关键列表换 `NSTableView`/`NSOutlineView` 包装(M5 决策点) |
| git 输出超大(diff 全量文本) | 内存尖峰 | 按文件粒度请求 diff;`-U` 上下文行数固定;行数上限 + 按需加载 |
| 泳道图算法边角情况(graft/浅克隆) | 图形错乱 | topo-order 输入保证主流程正确;异常输入降级为"单泳道" |
| 交互细节庞大 | 范围蔓延 | 严格按 §1.2 裁剪,细节问题记入 backlog 迭代 |
| GitHub Actions macOS runner 队列紧张 | CI 慢 | 仅 release 必须跑 macos;CI 矩阵可临时减配为 macos-15 单 runner |

---

## 10. 应用更新机制(M6)

- **检查层(自研,零依赖)**:启动后台请求 GitHub Releases API(`repos/zhangyang3/SourceGit/releases/latest`),比对 `tag_name` 与本地版本;版本号单一来源为 `Sources/SourceGit/AppVersion.swift`(make-app.sh 校验一致)。
- **更新配置(设置项)**:自动检查开关(默认开)、检查频率(每次启动/每天/每周)、跳过指定版本、上次检查时间;持久化 UserDefaults,设置入口在应用菜单。
- **UI**:菜单「检查更新…」手动触发;发现新版本弹窗(版本、Release Notes、前往下载 = 打开 Release 页);已是最新则轻提示。
- **backlog(不做)**:Sparkle/Ed25519 签名自动安装(需 vendored 框架与发布签名密钥体系,待有 Developer ID 后评估)、DMG 后台下载与 SHA256 校验。

## 11. 后续迭代方向(backlog,不在本期)

blame 视图、交互式 rebase、submodule 管理、文件历史、二进制 diff 预览(图片)、暗色主题微调、多标签窗口、菜单栏轻量模式。
