import SwiftUI

/// 主布局:侧栏 + 仓库内容 + 克隆/设置/更新面板。
struct MainView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var updater = UpdateChecker.shared
    @SGState private var showUpdateSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // 隐藏系统标题栏后,窗口顶部仍保留约 28pt 的交通灯区域,
            // 负上边距让自绘标题栏与之重叠,项目名与交通灯对齐。
            TitleBarView(appState: appState)
                .padding(.top, -40)
            NavigationSplitView(columnVisibility: $appState.columnVisibility) {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 210, ideal: 270, max: 420)
                    .frame(maxHeight: .infinity)
            } detail: {
                if let model = appState.activeRepo {
                    // .id:切换仓库时视图身份随之改变,onAppear/onDisappear 才能成对触发
                    //(否则新仓库不刷新、旧仓库轮询泄漏)
                    RepoContentView(model: model)
                        .id(model.repo.path)
                } else {
                    WelcomeView()
                }
            }
            .frame(minWidth: 1080, minHeight: 680)
        }
        .frame(minWidth: 1080, minHeight: 680)
        .toolbar(removing: .sidebarToggle)
        .sheet(isPresented: $appState.showCloneSheet) {
            CloneSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showSettings) {
            SettingsSheet()
        }
        .sheet(isPresented: $showUpdateSheet) {
            if case .available(let release) = updater.state {
                UpdateAvailableSheet(release: release)
            }
        }
        .onChange(of: updater.state) { _, newState in
            if case .available = newState {
                showUpdateSheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sgShowUpdateSheet)) { _ in
            showUpdateSheet = true
        }
        .onAppear {
            // 启动后延迟自动检查更新(不阻塞首屏)
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await UpdateChecker.shared.maybeAutoCheck()
            }
        }
        .alert(
            appState.lastError?.title ?? "错误",
            isPresented: Binding(
                get: { appState.lastError != nil },
                set: { if !$0 { appState.lastError = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(appState.lastError?.message ?? "")
        }
    }
}

// MARK: - 欢迎页

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .padding(.bottom, 8)
            Text("SourceGit")
                .font(.title.bold())
            Text("原生、轻量的 macOS Git 客户端")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    appState.openRepoFromPanel()
                } label: {
                    Label("打开仓库", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    appState.showCloneSheet = true
                } label: {
                    Label("克隆仓库", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
            Text("⌘O 打开 · ⇧⌘N 克隆")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 仓库主内容
//
// 注意:body 被拆分为多个计算属性——超大表达式会让旧版 Swift 编译器
// 类型检查超时(CI 曾因此失败),请保持每个属性的表达式规模适中。

struct RepoContentView: View {
    @ObservedObject var model: RepoModel

    var body: some View {
        withAlerts
    }

    /// 上下分栏主内容。
    private var paneContent: some View {
        VStack(spacing: 0) {
            if model.mergeInProgress {
                MergeBannerView(model: model)
            }
            VSplitView {
                Group {
                    switch model.section {
                    case .status:
                        WorkcopyView(model: model)
                    default:
                        HistoryView(model: model)
                    }
                }
                .frame(minHeight: 260)
                .layoutPriority(1)

                BottomPane(model: model)
                    .frame(minHeight: 200)
            }
            BottomBar(model: model)
        }
    }

    private var withToolbar: some View {
        paneContent
            .navigationTitle(model.name)
    }

    private var withLifecycle: some View {
        withToolbar
            .onAppear {
                model.startPolling()
                Task { await model.refreshAll() }
            }
            .onDisappear {
                model.stopPolling()
            }
            .onChange(of: model.selectedFile?.id) {
                Task { await model.loadFileDiff() }
            }
            .onChange(of: model.section, initial: true) { _, newSection in
                // 范围变化必须重新加载:否则标题显示新分支、内容仍是全仓库历史
                if newSection.isHistoryScope {
                    Task { await model.loadHistory(reset: true) }
                }
                model.searchText = ""      // 过滤词不应跨视图泄漏
            }
            .onChange(of: model.selectedCommitID) {
                Task { await model.loadCommitDetail() }
            }
            .onChange(of: model.selectedCommitPath) {
                Task { await model.loadSelectedCommitFileDiff() }
            }
    }

    private var withSheetsAndOverlay: some View {
        withLifecycle
            .sheet(item: $model.activeSheet) { sheet in
                sheetView(sheet)
            }
            .overlay {
                if model.busyOverlayVisible {
                    ZStack {
                        Color.primary.opacity(0.04)
                        ProgressView("正在执行 git 操作…")
                            .padding(16)
                            .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
    }

    private var withAlerts: some View {
        withSheetsAndOverlay
            .alert(
                model.lastError?.title ?? "错误",
                isPresented: Binding(
                    get: { model.lastError != nil },
                    set: { if !$0 { model.lastError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(model.lastError?.message ?? "")
            }
            .alert(
                model.confirmation?.title ?? "",
                isPresented: Binding(
                    get: { model.confirmation != nil },
                    set: { if !$0 { model.confirmation = nil } }
                )
            ) {
            Button(model.confirmation?.confirmLabel ?? "确定", role: .destructive) {
                model.confirmation?.action()
                model.confirmation = nil
            }
            Button("取消", role: .cancel) {
                model.confirmation = nil
            }
        } message: {
            Text(model.confirmation?.message ?? "")
        }
    }

    @ViewBuilder
    private func sheetView(_ sheet: RepoSheet) -> some View {
        switch sheet {
        case .newBranch(let prefill):
            NewBranchSheet(model: model, prefillStart: prefill)
        case .checkout:
            CheckoutSheet(model: model)
        case .merge(let prefill):
            MergeSheet(model: model, prefill: prefill)
        case .pull:
            PullSheet(model: model)
        case .push:
            PushSheet(model: model)
        case .stashSave:
            StashSaveSheet(model: model)
        case .renameBranch(let branch):
            RenameBranchSheet(model: model, branch: branch)
        }
    }
}

// MARK: - 底部面板(工作副本 diff / 提交详情)

struct BottomPane: View {
    @ObservedObject var model: RepoModel

    var body: some View {
        if model.section.isHistoryScope {
            CommitDetailView(model: model)
        } else {
            DiffPane(model: model)
        }
    }
}

// MARK: - 合并进行中横幅

struct MergeBannerView: View {
    @ObservedObject var model: RepoModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("合并进行中 —— 请在工作副本中解决冲突并提交,或终止合并")
                .lineLimit(1)
            Spacer()
            Button("终止合并") {
                model.perform("终止合并") { try $0.abortMerge() }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.15))
    }
}

// MARK: - 底部状态栏

struct BottomBar: View {
    @ObservedObject var model: RepoModel
    @FocusState private var searchFocused: Bool

    private var branchName: String {
        if model.status.isDetached {
            return "分离头指针 \(model.status.headHash.prefix(7))"
        }
        return model.status.branch ?? "—"
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                Text(branchName).fontWeight(.medium)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
            .help(model.status.isDetached ? model.status.headHash : (model.status.upstream ?? "无上游"))

            if model.status.ahead > 0 || model.status.behind > 0 {
                Text("\(model.status.ahead > 0 ? "↑\(model.status.ahead)" : "")\(model.status.behind > 0 ? " ↓\(model.status.behind)" : "")")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text(model.status.entries.isEmpty ? "工作区干净" : "\(model.status.entries.count) 个未提交更改")
                .foregroundStyle(model.status.entries.isEmpty ? .secondary : .primary)
                .monospacedDigit()

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(model.section.isHistoryScope ? "过滤提交…" : "过滤文件…", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 180)
                    .focused($searchFocused)
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onChange(of: model.focusSearchToken) {
            searchFocused = true
        }
    }
}

// MARK: - 自绘标题栏
//
// 隐藏系统标题栏后由我们绘制:左侧为项目名(与按钮同一行),右侧为操作栏。
// 背景区域可拖动窗口。

struct TitleBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            // 侧栏开关用系统的那个(隐藏标题栏后它仍显示在标题栏左侧),
            // 这里只放右侧的操作按钮。
            Spacer(minLength: 0)

            if let model = appState.activeRepo {
                RepoActionBar(model: model)
            }
        }
        .padding(.leading, 76)      // 让开交通灯按钮
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .frame(height: 40)
        .background(
            WindowDragArea()
                .background(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
        }
    }
}

/// 让标题栏空白区域可拖动窗口。
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

// MARK: - 操作栏(自绘,放在标题栏右侧)

/// 仓库操作栏:提交 / 分支 / 切换 / 合并 / 拉取 / 推送 / 更多。
///
/// 为什么不用系统窗口工具栏:macOS 统一工具栏会把同组工具栏项包进一个圆角容器,
/// 且条目超过 7 个时 macOS 27 会把溢出组再完整渲染一份(条目重复)。
/// 自绘操作栏没有这些问题,外观也更接近常见 Git 客户端。
struct RepoActionBar: View {
    @ObservedObject var model: RepoModel

    var body: some View {
        HStack(spacing: 2) {
            actionButton("提交", "checkmark.circle") {
                model.section = .status
                model.focusCommitEditorToken += 1
            }
            actionButton("分支", "arrow.triangle.branch") {
                model.activeSheet = .newBranch(prefill: nil)
            }
            actionButton("切换", "arrow.left.arrow.right.circle") {
                model.activeSheet = .checkout
            }
            actionButton("合并", "arrow.triangle.merge") {
                model.activeSheet = .merge(prefill: nil)
            }
            actionButton("拉取", "arrow.down.circle") {
                model.activeSheet = .pull
            }
            actionButton("推送", "arrow.up.circle") {
                model.activeSheet = .push
            }
            Menu {
                Button("获取全部远端") { model.fetchAll() }
                Button("贮藏当前改动…") { model.activeSheet = .stashSave }
                Divider()
                Button("刷新") { Task { await model.refreshAll() } }
                Button("在终端中打开") { model.openInTerminal() }
                Button("在 Finder 中显示") { model.revealInFinder() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "ellipsis.circle").font(.system(size: 13))
                    Text("更多").font(.system(size: 12))
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .fixedSize()
    }

    private func actionButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 13))
                Text(title).font(.system(size: 12))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

// MARK: - 工具栏按钮

/// 工具栏按钮(图标 + 文字)。
/// 必须是普通函数(返回 some View):自定义 ToolbarContent 结构体在 SwiftUI 中
/// 重建时会导致工具栏条目重复渲染。
/// 工具栏「更多」菜单。
private func repoToolbarMenu(@ViewBuilder content: () -> some View) -> some View {
    Menu {
        content()
    } label: {
        VStack(spacing: 2) {
            Image(systemName: "ellipsis.circle").font(.system(size: 15))
            Text("更多").font(.system(size: 10))
        }
        .frame(minWidth: 34)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("更多操作")
}

private func repoToolbarButton(
    _ title: String,
    _ icon: String,
    enabled: Bool = true,
    action: @escaping () -> Void
) -> some View {
    // 用标准 Label(图标+文字并排):自定义 VStack 视图会被 macOS 统一工具栏
    // 聚成带圆角背景的一组,看起来像多了一层包裹。
    Label {
        Text(title)
    } icon: {
        Image(systemName: icon)
    }
    .onTapGesture(perform: action)
    .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.5))
    .disabled(!enabled)
    .help(enabled ? title : "\(title)(将在后续里程碑提供)")
}
