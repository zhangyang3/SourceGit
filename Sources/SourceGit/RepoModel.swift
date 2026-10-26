import AppKit
import Foundation
import SwiftUI

// MARK: - 支撑类型

/// 侧栏可选区域。
enum SidebarSection: Hashable {
    case status
    case history
    case branch(GitBranch)
    case tag(GitTag)
    case remote(GitRemote)

    var isHistoryScope: Bool {
        switch self {
        case .history, .branch, .tag, .remote: return true
        case .status: return false
        }
    }
}

/// 工作副本里选中的文件(同一文件可能同时出现在两个分组)。
struct SelectedFile: Identifiable, Hashable {
    let file: WorktreeFile
    let staged: Bool
    var id: String { (staged ? "S|" : "W|") + file.path }
}

/// 展示用错误盒子。
struct ErrorBox: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    init(title: String, error: Error) {
        self.title = title
        if let gitError = error as? GitError {
            self.message = gitError.description
        } else {
            self.message = error.localizedDescription
        }
    }
}

/// 二次确认盒子(危险操作)。
struct ConfirmationBox: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmLabel: String
    let action: @MainActor () -> Void
}

/// diff 展示模式。
enum DiffDisplayMode: String, CaseIterable, Identifiable {
    case unified = "统一"
    case sideBySide = "并排"
    var id: String { rawValue }
}

/// 仓库级弹窗。
enum RepoSheet: Identifiable {
    case newBranch(prefill: GitBranch?)
    case checkout
    case merge(prefill: GitBranch?)
    case pull
    case push
    case stashSave
    case renameBranch(GitBranch)

    var id: String {
        switch self {
        case .newBranch: return "newBranch"
        case .checkout: return "checkout"
        case .merge: return "merge"
        case .pull: return "pull"
        case .push: return "push"
        case .stashSave: return "stashSave"
        case .renameBranch: return "renameBranch"
        }
    }
}

// MARK: - diff 结果 LRU 缓存(提交内容不可变,缓存恒有效;上限 32 个文件)

final class DiffLRUCache {
    private var store: [String: [DiffFile]] = [:]
    private var order: [String] = []
    private let capacity: Int

    init(capacity: Int = 32) {
        self.capacity = max(1, capacity)
    }

    func get(_ key: String) -> [DiffFile]? {
        guard let value = store[key] else { return nil }
        touch(key)
        return value
    }

    func set(_ key: String, value: [DiffFile]) {
        if store[key] == nil, order.count >= capacity, let oldest = order.first {
            order.removeFirst()
            store[oldest] = nil
        }
        store[key] = value
        touch(key)
    }

    var count: Int { store.count }

    private func touch(_ key: String) {
        if let idx = order.firstIndex(of: key) {
            order.remove(at: idx)
        }
        order.append(key)
    }
}

// MARK: - 仓库状态机

/// 单个打开仓库的 UI 状态与动作(唯一数据源)。
@MainActor
final class RepoModel: ObservableObject {
    let repo: GitRepository
    let name: String

    // 数据
    @Published var status = RepoStatus()
    @Published var branches: [GitBranch] = []
    @Published var remoteBranches: [GitBranch] = []
    @Published var tags: [GitTag] = []
    @Published var remotes: [GitRemote] = []
    @Published var stashes: [GitStash] = []

    // UI 状态
    @Published var section: SidebarSection = .status
    @Published var selectedFile: SelectedFile?
    @Published var fileDiff: [DiffFile] = []
    @Published var diffMode: DiffDisplayMode = .unified
    @Published var commitMessage = ""
    @Published var amendMode = false
    @Published var searchText = ""
    @Published var busyCount = 0
    /// 全屏遮罩计数:只统计用户主动发起的操作(提交/推送/获取…);
    /// 后台轮询与差异加载不计入,避免每次点击都闪一下。
    @Published private(set) var overlayCount = 0
    /// 是否应显示全屏"正在执行"遮罩
    var busyOverlayVisible: Bool { overlayCount > 0 }
    /// 是否处于合并进行中(由刷新流程写入,避免在 body 中反复执行 git 子进程)
    @Published private(set) var mergeInProgress = false
    /// 连续刷新失败次数(用于停止轮询,避免每 5 秒弹一次错误)
    private var consecutiveRefreshFailures = 0
    @Published var lastError: ErrorBox?
    @Published var confirmation: ConfirmationBox?
    @Published var focusCommitEditorToken = 0
    @Published var focusSearchToken = 0
    @Published var activeSheet: RepoSheet?

    // 历史(M3)
    @Published var history = HistoryData(commits: [], rows: [], laneCount: 1)
    @Published var historyLoading = false
    @Published var selectedCommitID: String?
    /// 选中提交的文件摘要列表(不含 hunk)
    @Published var commitChanges: [CommitFileChange] = []
    /// 选中提交中当前选中的文件路径
    @Published var selectedCommitPath: String?
    /// 选中文件的 diff(经 LRU 缓存)
    @Published var selectedCommitDiff: [DiffFile] = []
    /// 当前历史分页上限(每次增加 800);可用环境变量 SG_HISTORY_LIMIT 覆盖(性能测试钩子)
    var historyLimit = RepoModel.defaultHistoryLimit

    /// 历史视图选项
    @Published var showRemoteBranches = true      // 显示远程分支
    @Published var dateOrder = false             // 按时间排序(否则按拓扑)
    @Published var compactRows = false           // 紧凑视图

    /// 提交 diff 缓存(key = "commit|path")
    private let commitDiffCache = DiffLRUCache(capacity: 32)

    static let defaultHistoryLimit: Int =
        ProcessInfo.processInfo.environment["SG_HISTORY_LIMIT"].flatMap { Int($0) } ?? 800

    private var pollTask: Task<Void, Never>?

    init(path: String, name: String) throws {
        repo = try GitRepository.open(path)
        self.name = name
        // 性能测试钩子(见 scripts/perf.sh):指定初始视图
        if ProcessInfo.processInfo.environment["SG_INITIAL_SECTION"] == "history" {
            section = .history
        }
    }

    var isBusy: Bool { busyCount > 0 }

    // MARK: - 过滤

    var filteredUnstaged: [WorktreeFile] { filterFiles(status.unstaged) }
    var filteredStaged: [WorktreeFile] { filterFiles(status.staged) }

    private func filterFiles(_ files: [WorktreeFile]) -> [WorktreeFile] {
        guard !searchText.isEmpty else { return files }
        return files.filter { $0.path.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - 刷新

    func refreshAll() async {
        busyCount += 1
        defer { busyCount -= 1 }
        let repo = self.repo
        do {
            // 并行执行,总耗时取决于最慢的一条
            async let newStatus = Task.detached { try repo.status() }.value
            async let branchData = Task.detached { try repo.branches() }.value
            async let newTags = Task.detached { try repo.tags() }.value
            async let newRemotes = Task.detached { try repo.remotes() }.value
            async let newStashes = Task.detached { try repo.stashes() }.value
            async let merging = Task.detached { repo.mergeInProgress }.value
            let (st, br, tg, rm, sh, mg) = try await (newStatus, branchData, newTags, newRemotes, newStashes, merging)

            // 判等后再赋值:避免无变化时触发整棵视图树重建
            if st != status { status = st }
            if br.local != branches { branches = br.local }
            if br.remote != remoteBranches { remoteBranches = br.remote }
            if tg != tags { tags = tg }
            if rm != remotes { remotes = rm }
            if sh != stashes { stashes = sh }
            if mg != mergeInProgress { mergeInProgress = mg }
            revalidateSelection()
        } catch {
            lastError = ErrorBox(title: "刷新失败", error: error)
        }
    }

    /// 轻量刷新(轮询用):仅 status + 选中文件 diff。
    /// allowWhileBusy=false 时若已有操作在执行则跳过(轮询不与用户操作抢锁)。
    func refreshStatus(allowWhileBusy: Bool = true) async {
        if !allowWhileBusy, busyCount > 0 { return }
        busyCount += 1
        defer { busyCount -= 1 }
        let repo = self.repo
        do {
            async let st = Task.detached { try repo.status() }.value
            async let merging = Task.detached { repo.mergeInProgress }.value
            let (newStatus, mg) = try await (st, merging)
            if newStatus != status { status = newStatus }
            if mg != mergeInProgress { mergeInProgress = mg }
            consecutiveRefreshFailures = 0
            revalidateSelection()
            if selectedFile != nil {
                await loadFileDiff()
            }
        } catch {
            consecutiveRefreshFailures += 1
            // 连续失败:只提示一次;达到 3 次后停止轮询,避免错误弹窗反复出现
            if consecutiveRefreshFailures == 1 {
                lastError = ErrorBox(title: "刷新失败", error: error)
            }
            if consecutiveRefreshFailures >= 3 {
                stopPolling()
            }
        }
    }

    private func revalidateSelection() {
        guard let sel = selectedFile else { return }
        let pool = sel.staged ? status.staged : status.unstaged
        if let updated = pool.first(where: { $0 == sel.file }) {
            selectedFile = SelectedFile(file: updated, staged: sel.staged)
        } else {
            selectedFile = nil
            fileDiff = []
        }
    }

    func loadFileDiff() async {
        guard let sel = selectedFile else {
            fileDiff = []
            return
        }
        busyCount += 1
        defer { busyCount -= 1 }
        let repo = self.repo
        let path = sel.file.path
        let staged = sel.staged
        let untracked = sel.file.isUntracked
        do {
            let result = try await Task.detached { () -> [DiffFile] in
                if untracked { return try repo.diffUntracked(path) }
                return staged ? try repo.diffStaged(path) : try repo.diffWorktree(path)
            }.value
            // 期间用户可能已切换选择:丢弃过期结果
            guard selectedFile == sel else { return }
            fileDiff = result
        } catch {
            fileDiff = []
            lastError = ErrorBox(title: "读取差异失败", error: error)
        }
    }

    // MARK: - 轮询(窗口激活时每 5s 刷新 status)

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, NSApplication.shared.isActive else { continue }
                await self.refreshStatus(allowWhileBusy: false)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - 选择

    func select(_ file: WorktreeFile, staged: Bool) {
        selectedFile = SelectedFile(file: file, staged: staged)
        fileDiff = []      // 先清空,避免短暂显示上一个文件的差异
    }

    // MARK: - 工作副本动作

    func toggleStage(_ sel: SelectedFile) {
        if sel.staged {
            unstage([sel.file.path])
        } else {
            stage([sel.file.path])
        }
    }

    func stage(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        perform("暂存文件") { try $0.stage(paths) }
    }

    func unstage(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        perform("取消暂存") { try $0.unstage(paths) }
    }

    func stageAllUnstaged() {
        stage(status.unstaged.map(\.path))
    }

    func unstageAllStaged() {
        unstage(status.staged.map(\.path))
    }

    func requestDiscard(_ files: [WorktreeFile], staged: Bool) {
        guard !files.isEmpty else { return }
        let preview = files.prefix(3).map { "· " + ($0.oldPath ?? $0.path) }.joined(separator: "\n")
            + (files.count > 3 ? "\n… 共 \(files.count) 个文件" : "")
        confirmation = ConfirmationBox(
            title: "放弃修改",
            message: "以下改动将被不可恢复地丢弃:\n\n\(preview)",
            confirmLabel: "放弃修改"
        ) { [weak self] in
            Task { await self?.discard(files, staged: staged) }
        }
    }

    /// 放弃改动:staged=true 恢复到 HEAD;staged=false 仅把工作区还原到暂存区版本。
    func discard(_ files: [WorktreeFile], staged: Bool) async {
        let repo = self.repo
        busyCount += 1
        defer { busyCount -= 1 }
        do {
            // 放到后台线程:每个文件会触发 1~3 次 git 子进程,主线程执行会卡住界面
            try await Task.detached { () -> Void in
                for file in files {
                    if file.isUntracked || !repo.fileExistsInHEAD(file.path) {
                        // 未跟踪 / 新增文件:取消暂存后删除
                        try? repo.unstage([file.path])
                        try repo.removeUntracked([file.path])
                    } else if staged {
                        // 已暂存分组:放弃即恢复为 HEAD(暂存内容一并丢弃)
                        try repo.unstage([file.path])
                        try repo.discardWorktreeChanges([file.path])
                    } else {
                        // 未暂存分组:只还原工作区到暂存区版本,保留已暂存内容
                        try repo.discardWorktreeChanges([file.path])
                    }
                }
            }.value
        } catch {
            lastError = ErrorBox(title: "放弃修改失败", error: error)
        }
        await refreshAll()
    }

    func commit() async {
        let message = commitMessage.sg_trimmed()
        guard !message.isEmpty else {
            lastError = ErrorBox(title: "无法提交", message: "提交信息不能为空。")
            return
        }
        guard amendMode || !status.staged.isEmpty else {
            lastError = ErrorBox(title: "无法提交", message: "没有已暂存的变更。\n请先勾选需要提交的文件。")
            return
        }
        let amend = amendMode
        let ok = await performAsync("提交", quiet: true) { try $0.commit(message: message, amend: amend) }
        if ok {
            commitMessage = ""
            amendMode = false
        }
    }

    func toggleAmend(_ on: Bool) async {
        amendMode = on
        if on, commitMessage.isEmpty {
            let repo = self.repo
            let task = Task.detached(priority: .userInitiated) { try repo.headMessage() }
            if let msg = try? await task.value {
                // 期间用户可能已取消 amend,不再覆盖已输入的内容
                guard amendMode else { return }
                if commitMessage.isEmpty {
                    commitMessage = msg.sg_trimmed()
                }
            }
        }
    }

    // MARK: - 贮藏动作(M4 完整化)

    func stashApply(_ stash: GitStash, pop: Bool) {
        perform("应用贮藏") { try $0.stashApply(stash, pop: pop) }
    }

    func requestStashDrop(_ stash: GitStash) {
        confirmation = ConfirmationBox(
            title: "删除贮藏",
            message: "确定删除 \(stash.ref) 吗?\n\(stash.subject)",
            confirmLabel: "删除"
        ) { [weak self] in
            self?.perform("删除贮藏") { try $0.stashDrop(stash) }
        }
    }

    // MARK: - 历史(M3)

    var historyScopeLabel: String {
        switch section {
        case .history, .status: return "所有分支"
        case .branch(let b): return b.name
        case .tag(let t): return t.name
        case .remote(let r): return r.name
        }
    }

    private func historyScopeArgs() -> [String] {
        switch section {
        case .history, .status: return showRemoteBranches ? ["--all"] : ["--branches"]
        case .branch(let b): return [b.fullName]
        case .tag(let t): return [t.fullName]
        case .remote(let r): return ["--glob=refs/remotes/\(r.name)/*", "HEAD"]
        }
    }

    /// 是否还有更多历史可加载(以实际加载条数与上限比较)
    var hasMoreHistory: Bool { history.commits.count >= historyLimit && history.commits.count > lastLoadedCount }

    /// 上一次实际加载到的条数(用于判断继续加载是否有新内容)
    private var lastLoadedCount = 0

    var selectedCommit: GitCommit? {
        history.commits.first { $0.id == selectedCommitID }
    }

    var selectedCommitIsMerge: Bool {
        selectedCommit.map { $0.parents.count > 1 } ?? false
    }

    var selectedCommitFile: [DiffFile] {
        selectedCommitDiff
    }

    var filteredHistoryRows: [CommitGraphRow] {
        guard !searchText.isEmpty else { return history.rows }
        let q = searchText
        return history.rows.filter { row in
            let c = row.commit
            return c.subject.localizedCaseInsensitiveContains(q)
                || c.authorName.localizedCaseInsensitiveContains(q)
                || c.shortHash.hasPrefix(q)
                || c.hash.hasPrefix(q)
        }
    }

    /// 重置(reset=true 清空选择与分页)并加载当前范围的历史。
    func loadHistory(reset: Bool = true) async {
        if reset {
            historyLimit = Self.defaultHistoryLimit
            lastLoadedCount = 0
            selectedCommitID = nil
            commitChanges = []
            selectedCommitPath = nil
            selectedCommitDiff = []
        }
        historyLoading = true
        defer { historyLoading = false }
        let repo = self.repo
        let scope = historyScopeArgs()
        let limit = historyLimit
        do {
            let useDateOrder = dateOrder
            let result = try await Task.detached {
                try repo.history(scope: scope, limit: limit, dateOrder: useDateOrder)
            }.value
            // 期间范围可能已变化:丢弃过期结果
            guard historyScopeArgs() == scope else { return }
            history = result
            lastLoadedCount = result.commits.count
        } catch {
            lastError = ErrorBox(title: "加载历史失败", error: error)
        }
    }

    /// 增加分页并重新加载(保留当前选择)。
    func loadMoreHistory() async {
        historyLimit += 800
        await loadHistory(reset: false)
    }

    /// 加载选中提交的变更文件摘要(仅名称/类型/行数,不含 hunk —— 大提交内存策略)。
    func loadCommitDetail() async {
        guard let hash = selectedCommitID else {
            commitChanges = []
            selectedCommitPath = nil
            selectedCommitDiff = []
            return
        }
        let repo = self.repo
        busyCount += 1
        defer { busyCount -= 1 }
        do {
            let changes = try await Task.detached { try repo.diffCommitChanges(hash) }.value
            guard selectedCommitID == hash else { return }   // 过期结果丢弃
            commitChanges = changes
            selectedCommitPath = changes.first?.path
            selectedCommitDiff = []
        } catch {
            commitChanges = []
            selectedCommitPath = nil
            selectedCommitDiff = []
            lastError = ErrorBox(title: "读取提交详情失败", error: error)
        }
    }

    /// 加载选中提交中指定文件的 diff(带 LRU 缓存,提交内容不可变故缓存恒有效)。
    func loadSelectedCommitFileDiff() async {
        guard let hash = selectedCommitID, let path = selectedCommitPath else {
            selectedCommitDiff = []
            return
        }
        let key = "\(hash)|\(path)"
        if let cached = commitDiffCache.get(key) {
            selectedCommitDiff = cached
            return
        }
        let repo = self.repo
        busyCount += 1
        defer { busyCount -= 1 }
        do {
            let files = try await Task.detached { try repo.diffCommit(hash, path: path) }.value
            commitDiffCache.set(key, value: files)
            guard selectedCommitID == hash, selectedCommitPath == path else { return }
            selectedCommitDiff = files
        } catch {
            selectedCommitDiff = []
            lastError = ErrorBox(title: "读取文件差异失败", error: error)
        }
    }

    // MARK: - 分支与远端动作(M4)

    func createBranch(
        name: String,
        fromStart: String?,
        checkoutAfterCreate: Bool,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        let trimmed = name.sg_trimmed()
        guard !trimmed.isEmpty else {
            lastError = ErrorBox(title: "无法创建分支", message: "分支名不能为空。")
            completion?(false)
            return
        }
        perform("创建分支", completion: completion) {
            try $0.createBranch(trimmed, from: fromStart, checkout: checkoutAfterCreate)
        }
    }

    func checkout(_ branch: GitBranch, completion: (@MainActor (Bool) -> Void)? = nil) {
        perform("切换分支", completion: completion) {
            if branch.isRemote {
                try $0.checkoutRemote(branch.name)
            } else {
                try $0.checkout(branch.name)
            }
        }
    }

    func renameBranch(_ branch: GitBranch, to newName: String, completion: (@MainActor (Bool) -> Void)? = nil) {
        let trimmed = newName.sg_trimmed()
        guard !trimmed.isEmpty else {
            lastError = ErrorBox(title: "无法重命名", message: "新分支名不能为空。")
            completion?(false)
            return
        }
        perform("重命名分支", completion: completion) {
            try $0.renameBranch(branch.name, to: trimmed)
        }
    }

    func requestDeleteBranch(_ branch: GitBranch) {
        confirmation = ConfirmationBox(
            title: "删除分支",
            message: branch.isRemote
                ? "将删除远端「\(branch.remoteName ?? "")」上的分支「\(branch.shortName)」。\n此操作会影响远端仓库!"
                : "确定删除分支「\(branch.name)」吗?",
            confirmLabel: "删除"
        ) { [weak self] in
            self?.deleteBranch(branch, force: false)
        }
    }

    private func deleteBranch(_ branch: GitBranch, force: Bool) {
        perform("删除分支", completion: { [weak self] ok in
            // 未合并分支删除失败 → 提示强制删除
            if !ok, !force, !branch.isRemote,
               let self,
               let message = self.lastError?.message,
               message.contains("not fully merged") || message.contains("fully merged") || message.contains("-D") {
                self.confirmation = ConfirmationBox(
                    title: "强制删除分支",
                    message: "分支「\(branch.name)」包含未合并到上游的提交,\n强制删除后将无法通过分支名找回。",
                    confirmLabel: "强制删除"
                ) { [weak self] in
                    self?.deleteBranch(branch, force: true)
                }
            }
        }) {
            try $0.deleteBranch(branch, force: force)
        }
    }

    func mergeBranch(
        _ branch: GitBranch,
        noFF: Bool,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        perform("合并", completion: completion) {
            try $0.merge(branch.name, noFF: noFF)
        }
    }

    func fetchAll() {
        perform("获取全部远端") { try $0.fetch(nil) }
    }

    func fetch(_ remote: GitRemote) {
        perform("获取 \(remote.name)") { try $0.fetch(remote.name) }
    }

    func pull(
        remote: GitRemote,
        branch: GitBranch,
        rebase: Bool,
        ffOnly: Bool,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        perform("拉取", completion: completion) {
            try $0.pull(remote: remote.name, branch: branch.shortName, rebase: rebase, ffOnly: ffOnly)
        }
    }

    func push(
        remote: GitRemote,
        branch: GitBranch,
        setUpstream: Bool,
        forceWithLease: Bool,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        perform("推送", completion: completion) {
            try $0.push(remote: remote.name, branch: branch.name,
                        setUpstream: setUpstream, forceWithLease: forceWithLease)
        }
    }

    func stashSave(
        message: String,
        includeUntracked: Bool,
        keepIndex: Bool,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        perform("贮藏", completion: completion) {
            try $0.stashSave(message: message.isEmpty ? nil : message,
                             includeUntracked: includeUntracked, keepIndex: keepIndex)
        }
    }

    // MARK: - 系统集成

    func revealInFinder(relativePath: String? = nil) {
        let url = URL(fileURLWithPath: repo.path)
        if let relativePath {
            NSWorkspace.shared.activateFileViewerSelecting([url.appendingPathComponent(relativePath)])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func openInTerminal() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", repo.path]
        try? process.run()
    }

    /// 通用后台执行 + 刷新 + 错误展示(可等待版本,返回是否成功)。
    /// 供需要"等结果"的调用方使用(如提交后清空提交信息)。
    @discardableResult
    func performAsync(
        _ title: String,
        quiet: Bool = false,
        _ op: @escaping @Sendable (GitRepository) throws -> Void
    ) async -> Bool {
        busyCount += 1
        if !quiet { overlayCount += 1 }
        defer {
            busyCount -= 1
            if !quiet { overlayCount -= 1 }
        }
        return await performWork(title, op)
    }

    /// 实际执行(不负责忙状态计数),供 perform / performAsync 共用。
    private func performWork(
        _ title: String,
        _ op: @escaping @Sendable (GitRepository) throws -> Void
    ) async -> Bool {
        let repo = self.repo
        do {
            try await Task.detached { try op(repo) }.value
            await refreshAll()
            // 历史视图下同步刷新提交列表
            if section.isHistoryScope {
                await loadHistory(reset: false)
            }
            return true
        } catch {
            lastError = ErrorBox(title: "\(title)失败", error: error)
            await refreshStatus()
            return false
        }
    }

    /// 通用后台执行 + 刷新 + 错误展示;completion 在成功/失败后回调(主线程)。
    /// 忙状态在调用时**同步**占用,确保调用方返回后立刻能观察到"正在执行"。
    func perform(
        _ title: String,
        quiet: Bool = false,
        completion: (@MainActor (Bool) -> Void)? = nil,
        _ op: @escaping @Sendable (GitRepository) throws -> Void
    ) {
        busyCount += 1
        if !quiet { overlayCount += 1 }
        Task { [weak self] in
            guard let self else { return }
            let ok = await self.performWork(title, op)
            self.busyCount -= 1
            if !quiet { self.overlayCount -= 1 }
            completion?(ok)
        }
    }
}
