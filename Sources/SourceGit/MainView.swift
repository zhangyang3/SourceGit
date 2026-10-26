import SwiftUI

/// 主布局:侧栏 + 仓库内容 + 克隆/设置/更新面板。
struct MainView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var updater = UpdateChecker.shared
    @SGState private var showUpdateSheet = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 270, max: 420)
                .frame(maxHeight: .infinity)
        } detail: {
            if let model = appState.activeRepo {
                RepoContentView(model: model)
            } else {
                WelcomeView()
            }
        }
        .frame(minWidth: 1080, minHeight: 680)
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
            if model.repo.mergeInProgress {
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
            .toolbar { RepoToolbar(model: model) }
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
            .onChange(of: model.section) { _, newSection in
                if newSection.isHistoryScope && model.history.commits.isEmpty {
                    Task { await model.loadHistory() }
                }
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

// MARK: - 工具栏

struct RepoToolbar: ToolbarContent {
    @ObservedObject var model: RepoModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            toolbarButton("提交", "checkmark.circle") {
                model.section = .status
                model.focusCommitEditorToken += 1
            }

            toolbarButton("分支", "arrow.triangle.branch") {
                model.activeSheet = .newBranch(prefill: nil)
            }
            toolbarButton("切换", "arrow.left.arrow.right.circle") {
                model.activeSheet = .checkout
            }
            toolbarButton("合并", "arrow.triangle.merge") {
                model.activeSheet = .merge(prefill: nil)
            }
            toolbarButton("获取", "arrow.triangle.2.circlepath") {
                model.fetchAll()
            }
            toolbarButton("拉取", "arrow.down.circle") {
                model.activeSheet = .pull
            }
            toolbarButton("推送", "arrow.up.circle") {
                model.activeSheet = .push
            }
            toolbarButton("贮藏", "archivebox") {
                model.activeSheet = .stashSave
            }

            Divider()

            toolbarButton("刷新", "arrow.clockwise") {
                Task { await model.refreshAll() }
            }
            toolbarButton("终端", "terminal") {
                model.openInTerminal()
            }
            toolbarButton("Finder", "folder") {
                model.revealInFinder()
            }
        }
    }

    private func toolbarButton(
        _ title: String,
        _ icon: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 15))
                Text(title).font(.system(size: 10))
            }
            .frame(minWidth: 34)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.5))
        .disabled(!enabled)
        .help(enabled ? title : "\(title)(将在后续里程碑提供)")
    }
}
