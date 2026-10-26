import SwiftUI

/// 克隆仓库面板。
struct CloneSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @SGState private var url = "https://github.com/"
    @SGState private var directory = NSHomeDirectory()
    @SGState private var name = ""
    @SGState private var cloning = false
    @SGState private var errorText: String?

    private var suggestedName: String {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
            .droppingSuffix("/")
            .droppingSuffix(".git")
        return (trimmed as NSString).lastPathComponent
    }

    private var destPath: String {
        (directory as NSString).appendingPathComponent(name.isEmpty ? suggestedName : name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("克隆仓库")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("源 URL").font(.caption).foregroundStyle(.secondary)
                TextField("https://github.com/user/repo.git", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .disabled(cloning)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("目标位置").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text((destPath as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("选择…") {
                        if let picked = openDirectoryPanel(title: "选择克隆目标目录") {
                            directory = picked
                        }
                    }
                    .disabled(cloning)
                }
                HStack {
                    Text("目录名").font(.caption).foregroundStyle(.secondary)
                    TextField(suggestedName, text: $name)
                        .textFieldStyle(.roundedBorder)
                        .disabled(cloning)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(4)
            }

            HStack {
                if cloning {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在克隆…")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .disabled(cloning)
                Button("克隆") { clone() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(cloning || url.trimmingCharacters(in: .whitespaces).isEmpty || suggestedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func clone() {
        let sourceURL = url.trimmingCharacters(in: .whitespaces)
        let finalName = name.isEmpty ? suggestedName : name
        cloning = true
        errorText = nil
        Task {
            do {
                try await appState.cloneRepo(url: sourceURL, directory: directory, name: finalName)
                appState.showCloneSheet = false
            } catch {
                errorText = (error as? GitError)?.description ?? error.localizedDescription
            }
            cloning = false
        }
    }
}

extension String {
    func droppingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropFirst(suffix.count)) : self
    }
}

// MARK: - M4 面板通用样式

private struct SheetCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3.bold())
            content
        }
        .padding(20)
        .frame(width: 520)
    }
}

private struct SheetFooter: View {
    let busy: Bool
    let busyText: String
    let confirmTitle: String
    let confirmDisabled: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    init(
        busyText: String = "执行中…",
        busy: Bool = false,
        confirmTitle: String,
        confirmDisabled: Bool = false,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.busy = busy
        self.busyText = busyText
        self.confirmTitle = confirmTitle
        self.confirmDisabled = confirmDisabled
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        HStack {
            if busy {
                ProgressView().controlSize(.small)
                Text(busyText).foregroundStyle(.secondary)
            }
            Spacer()
            Button("取消", action: onCancel).disabled(busy)
            Button(confirmTitle, action: onConfirm)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(confirmDisabled || busy)
        }
    }
}

// MARK: - 新建分支

struct NewBranchSheet: View {
    @ObservedObject var model: RepoModel
    @Environment(\.dismiss) private var dismiss
    let prefillStart: GitBranch?

    @SGState private var name = ""
    @SGState private var startID: String = "HEAD"
    @SGState private var checkoutAfter = true
    @SGState private var submitting = false

    init(model: RepoModel, prefillStart: GitBranch? = nil) {
        self.model = model
        self.prefillStart = prefillStart
        _name = SGState(wrappedValue: "")
        _startID = SGState(wrappedValue: prefillStart?.fullName ?? "HEAD")
        _checkoutAfter = SGState(wrappedValue: true)
    }

    private struct StartOption: Identifiable {
        let id: String
        let label: String
    }

    private var options: [StartOption] {
        var list = [StartOption(id: "HEAD", label: "当前 HEAD")]
        list += model.branches.map { StartOption(id: $0.fullName, label: "本地 · \($0.name)") }
        list += model.remoteBranches.map { StartOption(id: $0.fullName, label: "远程 · \($0.name)") }
        list += model.tags.map { StartOption(id: $0.fullName, label: "标签 · \($0.name)") }
        return list
    }

    var body: some View {
        SheetCard(title: "新建分支") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("分支名").font(.caption).foregroundStyle(.secondary)
                    TextField("feature/xxx", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("起点").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $startID) {
                        ForEach(options) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)
                }
                Toggle("创建后切换到此分支", isOn: $checkoutAfter)
                Text(prefillNote)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                SheetFooter(
                    busy: submitting,
                    confirmTitle: "创建分支",
                    confirmDisabled: name.sg_trimmed().isEmpty
                ) {
                    submit()
                } onCancel: {
                    dismiss()
                }
            }
        }
    }

    private var prefillNote: String {
        if let prefillStart {
            return "基于「\(prefillStart.name)」创建"
        }
        return "基于当前 HEAD(\(model.status.headHash.prefix(7)))创建"
    }

    private func submit() {
        submitting = true
        let from = startID == "HEAD" ? nil : startID
        model.createBranch(name: name, fromStart: from, checkoutAfterCreate: checkoutAfter) { [weak model] ok in
            model?.activeSheet = nil
            if ok { dismiss() }
            submitting = false
        }
    }
}

// MARK: - 切换分支

struct CheckoutSheet: View {
    @ObservedObject var model: RepoModel
    @Environment(\.dismiss) private var dismiss
    @SGState private var filter = ""
    @SGState private var selected: GitBranch?

    private var filteredLocal: [GitBranch] {
        model.branches.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
    }

    private var filteredRemote: [GitBranch] {
        model.remoteBranches.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        SheetCard(title: "切换分支") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("过滤分支…", text: $filter)
                    .textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if !filteredLocal.isEmpty {
                            Text("本地").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 4)
                            ForEach(filteredLocal) { branch in
                                row(branch)
                            }
                        }
                        if !filteredRemote.isEmpty {
                            Text("远程").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 6)
                            ForEach(filteredRemote) { branch in
                                row(branch)
                            }
                        }
                    }
                }
                .frame(height: 260)
                .overlay(
                    RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12))
                )
                .background(Color(nsColor: .controlBackgroundColor))

                SheetFooter(
                    confirmTitle: "切换",
                    confirmDisabled: selected == nil || isCurrentSelected
                ) {
                    if let selected { submit(selected) }
                } onCancel: {
                    dismiss()
                }
            }
        }
    }

    private var isCurrentSelected: Bool {
        guard let selected else { return false }
        return !selected.isRemote && selected.name == model.status.branch
    }

    private func row(_ branch: GitBranch) -> some View {
        let isSel = selected == branch
        let isCurrent = !branch.isRemote && branch.name == model.status.branch
        return HStack(spacing: 6) {
            Circle()
                .fill(SGPalette.laneColor(branch.isRemote ? 2 : 0))
                .frame(width: 6, height: 6)
            Text(branch.name)
                .fontWeight(isCurrent ? .semibold : .regular)
            if isCurrent {
                Text("✓ 当前").font(.caption2).foregroundStyle(.tint)
            }
            if let track = trackDisplay(branch.upstreamTrack) {
                Text(track).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .rowBackground(selected: isSel)
        .contentShape(Rectangle())
        .onTapGesture { selected = branch }
        .onTapGesture(count: 2) { submit(branch) }
    }

    private func submit(_ branch: GitBranch) {
        model.checkout(branch) { [weak model] ok in
            if ok { model?.activeSheet = nil }
        }
    }
}

// MARK: - 合并

struct MergeSheet: View {
    @ObservedObject var model: RepoModel
    @Environment(\.dismiss) private var dismiss
    let prefill: GitBranch?

    @SGState private var selected: GitBranch?
    @SGState private var noFF = false
    @SGState private var submitting = false

    init(model: RepoModel, prefill: GitBranch? = nil) {
        self.model = model
        self.prefill = prefill
        _selected = SGState(wrappedValue: prefill ?? model.branches.first { $0.name != model.status.branch })
    }

    private var candidates: [GitBranch] {
        (model.branches.filter { $0.name != model.status.branch } + model.remoteBranches)
            .filter { $0.hash != model.status.headHash }
    }

    var body: some View {
        SheetCard(title: "合并到「\(model.status.branch ?? "当前分支")」") {
            VStack(alignment: .leading, spacing: 10) {
                if candidates.isEmpty {
                    Text("没有可合并的分支。")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                } else {
                    Picker("", selection: $selected) {
                        ForEach(candidates) { branch in
                            Text((branch.isRemote ? "远程 · " : "本地 · ") + branch.name).tag(branch as GitBranch?)
                        }
                    }
                    .labelsHidden()
                    Toggle("保留合并提交(--no-ff)", isOn: $noFF)
                    Text("如产生冲突,顶部会出现横幅,在工作副本中解决后提交。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                SheetFooter(
                    busy: submitting,
                    confirmTitle: "合并",
                    confirmDisabled: selected == nil
                ) {
                    submit()
                } onCancel: {
                    dismiss()
                }
            }
        }
    }

    private func submit() {
        guard let selected else { return }
        submitting = true
        model.mergeBranch(selected, noFF: noFF) { [weak model] ok in
            if ok { model?.activeSheet = nil }
            submitting = false
        }
    }
}

// MARK: - 拉取

struct PullSheet: View {
    @ObservedObject var model: RepoModel
    @Environment(\.dismiss) private var dismiss

    enum Strategy: String, CaseIterable, Identifiable {
        case merge = "合并(默认)"
        case rebase = "变基(rebase)"
        case ffOnly = "仅快进"
        var id: String { rawValue }
    }

    @SGState private var remote: GitRemote?
    @SGState private var branch: GitBranch?
    @SGState private var strategy: Strategy = .merge
    @SGState private var submitting = false

    init(model: RepoModel) {
        self.model = model
        // 默认:当前分支上游 → 第一个远端的第一个分支
        var defaultRemote: GitRemote?
        var defaultBranch: GitBranch?
        if let upstream = model.status.upstream {
            let parts = upstream.split(separator: "/").map(String.init)
            if parts.count >= 2 {
                defaultRemote = model.remotes.first { $0.name == parts[0] }
                defaultBranch = model.remoteBranches.first { $0.name == upstream }
            }
        }
        if defaultRemote == nil {
            defaultRemote = model.remotes.first
        }
        if defaultBranch == nil, let r = defaultRemote {
            defaultBranch = model.remoteBranches.first { $0.remoteName == r.name }
        }
        _remote = SGState(wrappedValue: defaultRemote)
        _branch = SGState(wrappedValue: defaultBranch)
    }

    private var branchOptions: [GitBranch] {
        guard let remote else { return [] }
        return model.remoteBranches.filter { $0.remoteName == remote.name }
    }

    var body: some View {
        SheetCard(title: "拉取") {
            VStack(alignment: .leading, spacing: 12) {
                if model.remotes.isEmpty {
                    Text("此仓库没有配置远端。")
                        .foregroundStyle(.secondary).padding(.vertical, 16)
                } else {
                    HStack {
                        Picker("远端", selection: $remote) {
                            ForEach(model.remotes) { r in
                                Text(r.name).tag(r as GitRemote?)
                            }
                        }
                        Picker("远程分支", selection: $branch) {
                            ForEach(branchOptions) { b in
                                Text(b.shortName).tag(b as GitBranch?)
                            }
                        }
                    }
                    .labelsHidden()
                    Picker("策略", selection: $strategy) {
                        ForEach(Strategy.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 340)
                    Text("当前分支:\(model.status.branch ?? "—")\((model.status.behind > 0) ? " · 落后远端 \(model.status.behind) 个提交" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                SheetFooter(
                    busy: submitting,
                    confirmTitle: "拉取",
                    confirmDisabled: remote == nil || branch == nil
                ) {
                    submit()
                } onCancel: {
                    dismiss()
                }
            }
        }
    }

    private func submit() {
        guard let remote, let branch else { return }
        submitting = true
        model.pull(remote: remote, branch: branch,
                   rebase: strategy == .rebase, ffOnly: strategy == .ffOnly) { [weak model] ok in
            if ok { model?.activeSheet = nil }
            submitting = false
        }
    }
}

// MARK: - 推送

struct PushSheet: View {
    @ObservedObject var model: RepoModel
    @Environment(\.dismiss) private var dismiss

    @SGState private var remote: GitRemote?
    @SGState private var branch: GitBranch?
    @SGState private var setUpstream: Bool
    @SGState private var force = false
    @SGState private var submitting = false

    init(model: RepoModel) {
        self.model = model
        let current = model.branches.first { $0.name == model.status.branch }
        let upstreamRemote = current?.upstream?.split(separator: "/").first.map(String.init)
        let r = model.remotes.first { $0.name == upstreamRemote } ?? model.remotes.first
        _remote = SGState(wrappedValue: r)
        _branch = SGState(wrappedValue: current ?? model.branches.first)
        _setUpstream = SGState(wrappedValue: current?.upstream == nil)
    }

    var body: some View {
        SheetCard(title: "推送") {
            VStack(alignment: .leading, spacing: 12) {
                if model.remotes.isEmpty {
                    Text("此仓库没有配置远端。")
                        .foregroundStyle(.secondary).padding(.vertical, 16)
                } else {
                    HStack {
                        Picker("远端", selection: $remote) {
                            ForEach(model.remotes) { r in
                                Text(r.name).tag(r as GitRemote?)
                            }
                        }
                        Picker("分支", selection: $branch) {
                            ForEach(model.branches) { b in
                                Text(b.name).tag(b as GitBranch?)
                            }
                        }
                    }
                    .labelsHidden()
                    Toggle("设置上游(首次推送该分支)", isOn: $setUpstream)
                    Toggle("强制推送(--force-with-lease)", isOn: $force)
                    Text(force
                         ? "⚠ 强制推送会用本地覆盖远端,请确认没有他人的工作。"
                         : "当前分支:\(model.status.branch ?? "—")\((model.status.ahead > 0) ? " · 领先 \(model.status.ahead) 个提交" : "")")
                        .font(.caption)
                        .foregroundStyle(force ? Color.orange : Color.secondary)
                }
                SheetFooter(
                    busy: submitting,
                    confirmTitle: force ? "强制推送" : "推送",
                    confirmDisabled: remote == nil || branch == nil || (force && !confirmForceHint)
                ) {
                    submit()
                } onCancel: {
                    dismiss()
                }
            }
        }
    }

    private var confirmForceHint: Bool { true }

    private func submit() {
        guard let remote, let branch else { return }
        submitting = true
        model.push(remote: remote, branch: branch,
                   setUpstream: setUpstream, forceWithLease: force) { [weak model] ok in
            if ok { model?.activeSheet = nil }
            submitting = false
        }
    }
}

// MARK: - 贮藏

struct StashSaveSheet: View {
    @ObservedObject var model: RepoModel
    @Environment(\.dismiss) private var dismiss

    @SGState private var message = ""
    @SGState private var includeUntracked = true
    @SGState private var keepIndex = false
    @SGState private var submitting = false

    var body: some View {
        SheetCard(title: "贮藏当前改动") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("说明(可选)").font(.caption).foregroundStyle(.secondary)
                    TextField("例如:WIP 功能开发中", text: $message)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("包含未跟踪文件", isOn: $includeUntracked)
                Toggle("保留已暂存的改动(不贮藏暂存区)", isOn: $keepIndex)
                Text("共 \(model.status.entries.count) 个未提交文件将被贮藏。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                SheetFooter(
                    busy: submitting,
                    confirmTitle: "贮藏",
                    confirmDisabled: model.status.entries.isEmpty
                ) {
                    submit()
                } onCancel: {
                    dismiss()
                }
            }
        }
    }

    private func submit() {
        submitting = true
        model.stashSave(message: message, includeUntracked: includeUntracked, keepIndex: keepIndex) { [weak model] ok in
            if ok { model?.activeSheet = nil }
            submitting = false
        }
    }
}

// MARK: - 设置(更新配置)

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = UpdateSettings.shared
    @ObservedObject private var checker = UpdateChecker.shared

    var body: some View {
        SheetCard(title: "设置") {
            VStack(alignment: .leading, spacing: 14) {
                // 关于
                HStack(spacing: 10) {
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                        .font(.system(size: 22))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SourceGit \(AppVersion.effective)")
                            .font(.callout.weight(.semibold))
                        Text("仓库:\(AppVersion.repository)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Divider()

                Text("更新").font(.headline)
                Toggle("自动检查更新", isOn: $settings.autoCheck)
                HStack {
                    Text("检查频率").foregroundStyle(.secondary)
                    Picker("", selection: $settings.frequency) {
                        ForEach(UpdateFrequency.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    .disabled(!settings.autoCheck)
                    Spacer()
                }
                HStack {
                    Text("上次检查")
                        .foregroundStyle(.secondary)
                    Text(settings.lastCheckDate.map { Fmt.short($0) } ?? "从未")
                        .monospacedDigit()
                    Spacer()
                    if settings.skippedVersion != nil {
                        Text("已跳过 \(settings.skippedVersion ?? "")")
                            .foregroundStyle(.secondary)
                        Button("清除") { settings.clearSkipped() }
                            .controlSize(.small)
                    }
                }
                .font(.callout)

                HStack {
                    Button {
                        Task { await checker.check(manual: true) }
                    } label: {
                        Label("立即检查", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(checker.state == .checking)

                    stateView

                    Spacer()
                }

                Text("说明:更新包托管在 GitHub Releases(未签名公证,首次打开需右键 → 打开)。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                HStack {
                    Spacer()
                    Button("完成") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch checker.state {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
        case .upToDate:
            Label("已是最新版本", systemImage: "checkmark.circle")
                .foregroundStyle(.green).font(.callout)
        case .noRelease(let message):
            Text(message).foregroundStyle(.secondary).font(.callout)
        case .available(let release):
            Button("查看新版本 \(release.displayVersion)…") {
                // 状态驱动的更新弹窗由 MainView 展示;这里触发再次弹出
                NotificationCenter.default.post(name: .sgShowUpdateSheet, object: nil)
            }
            .font(.callout)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange).font(.callout)
        }
    }
}

extension Notification.Name {
    static let sgShowUpdateSheet = Notification.Name("sgShowUpdateSheet")
}

// MARK: - 发现新版本

struct UpdateAvailableSheet: View {
    let release: AppRelease
    @ObservedObject private var checker = UpdateChecker.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetCard(title: "发现新版本 \(release.displayVersion)") {
            VStack(alignment: .leading, spacing: 12) {
                Text("当前版本 \(AppVersion.effective) → 新版本 \(release.displayVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("更新说明").font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        Text(release.body ?? "(无说明)")
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 220)
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12))
                    )
                }

                HStack {
                    ProgressView().controlSize(.small)
                    Text("下载方式:前往 GitHub Releases 页面(未签名包,首次打开需右键 → 打开)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("跳过此版本") {
                        checker.skip(release)
                        dismiss()
                    }
                    Button("稍后提醒") { dismiss() }
                    Button("前往下载") {
                        checker.openDownload(release)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

// MARK: - 重命名分支

struct RenameBranchSheet: View {
    @ObservedObject var model: RepoModel
    @Environment(\.dismiss) private var dismiss
    let branch: GitBranch
    @SGState private var newName: String

    init(model: RepoModel, branch: GitBranch) {
        self.model = model
        self.branch = branch
        _newName = SGState(wrappedValue: branch.name)
    }

    var body: some View {
        SheetCard(title: "重命名分支") {
            VStack(alignment: .leading, spacing: 12) {
                Text("将「\(branch.name)」重命名为:").font(.callout)
                TextField("新分支名", text: $newName)
                    .textFieldStyle(.roundedBorder)
                SheetFooter(
                    confirmTitle: "重命名",
                    confirmDisabled: newName.sg_trimmed().isEmpty || newName == branch.name
                ) {
                    submit()
                } onCancel: {
                    dismiss()
                }
            }
        }
    }

    private func submit() {
        model.renameBranch(branch, to: newName) { [weak model] ok in
            if ok { model?.activeSheet = nil }
        }
    }
}
