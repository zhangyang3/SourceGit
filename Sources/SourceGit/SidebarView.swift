import SwiftUI

/// 侧栏:仓库列表 + WORKSPACE(文件状态/历史/搜索)+ 分支/标签/远端/已贮藏 + 底部过滤器。
/// 布局参考常见 Git 客户端:分组小标题 + 树形项,选中项为蓝色圆角高亮。
struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    // 仓库列表
                    sectionHeader("仓库")
                    ForEach(appState.bookmarks) { bookmark in
                        BookmarkRow(bookmark: bookmark)
                    }
                    if appState.bookmarks.isEmpty {
                        emptyHint("使用 ⌘O 添加仓库")
                    }
                    Divider().padding(.vertical, 6)

                    // 主工作区与仓库相关分组
                    if let model = appState.activeRepo {
                        WorkspaceSections(model: model, header: sectionHeader)
                    } else {
                        sectionHeader("WORKSPACE")
                        SidebarItemRow(icon: "doc.text.magnifyingglass", title: "文件状态", disabled: true) {}
                        SidebarItemRow(icon: "clock.arrow.circlepath", title: "历史", disabled: true) {}
                        SidebarItemRow(icon: "magnifyingglass", title: "搜索", disabled: true) {}
                        SidebarItemRow(icon: "square.stack.3d.up", title: "子模块", disabled: true) {}
                        SidebarItemRow(icon: "arrow.triangle.branch", title: "子树", disabled: true) {}
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }

            Divider()

            // 底部过滤器
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("过滤器", text: Binding(
                    get: { appState.activeRepo?.searchText ?? "" },
                    set: { appState.activeRepo?.searchText = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    fileprivate func sectionHeader(_ title: String) -> AnyView {
        AnyView(
            HStack(spacing: 5) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.top, 10)
            .padding(.bottom, 2)
        )
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
    }
}

// MARK: - 工作区分组(观察 RepoModel,模型变化即时刷新)

/// WORKSPACE / 分支 / 标签 / 远端 / 已贮藏 分组。
/// 单独抽出是因为这些数据来自 RepoModel:侧栏只观察 AppState 时,
/// 模型内部变化(如分支列表刷新)不会触发侧栏重绘。
struct WorkspaceSections: View {
    @ObservedObject var model: RepoModel
    let header: (String) -> AnyView

    var body: some View {
        Group {
            header("WORKSPACE")
            SidebarItemRow(
                icon: "doc.text.magnifyingglass",
                title: "文件状态",
                badge: "\(model.status.entries.count)",
                selected: !model.section.isHistoryScope
            ) {
                model.section = .status
            }
            SidebarItemRow(
                icon: "clock.arrow.circlepath",
                title: "历史",
                selected: model.section.isHistoryScope
            ) {
                model.section = .history
            }
            SidebarItemRow(icon: "magnifyingglass", title: "搜索", disabled: true) {}

            header("分支")
            ForEach(model.branches) { branch in
                BranchRow(model: model, branch: branch)
            }
            if model.branches.isEmpty {
                Text("暂无本地分支")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, 10).padding(.vertical, 2)
            }

            header("标签")
            ForEach(model.tags) { tag in
                SidebarItemRow(icon: "tag", title: tag.name, selected: model.section == .tag(tag)) {
                    model.section = .tag(tag)
                }
            }
            if model.tags.isEmpty {
                Text("暂无标签")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, 10).padding(.vertical, 2)
            }

            header("远端")
            ForEach(model.remotes) { remote in
                RemoteRow(model: model, remote: remote)
            }
            if model.remotes.isEmpty {
                Text("暂无远端")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, 10).padding(.vertical, 2)
            }

            header("已贮藏")
            ForEach(model.stashes) { stash in
                StashRow(model: model, stash: stash)
            }
            if model.stashes.isEmpty {
                Text("暂无贮藏")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, 10).padding(.vertical, 2)
            }

            SidebarItemRow(icon: "square.stack.3d.up", title: "子模块", disabled: true) {}
            SidebarItemRow(icon: "arrow.triangle.branch", title: "子树", disabled: true) {}
        }
    }
}

// MARK: - 通用侧栏行

struct SidebarItemRow: View {
    let icon: String
    let title: String
    var badge: String?
    var selected: Bool = false
    var disabled: Bool = false
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 16)
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 0)
            if let badge {
                Text(badge)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(selected ? Color.white.opacity(0.9) : Color.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(selected ? Color.accentColor : Color.clear)
        )
        .foregroundStyle(selected ? Color.white : (disabled ? Color.secondary.opacity(0.45) : Color.primary))
        .contentShape(Rectangle())
        .onTapGesture { if !disabled { action() } }
    }
}

// MARK: - 仓库行

struct BookmarkRow: View {
    @EnvironmentObject var appState: AppState
    let bookmark: RepoBookmark
    @SGState private var confirmRemove = false

    private var isSelected: Bool { appState.selectedBookmarkID == bookmark.id }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .frame(width: 16)
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
            Text(bookmark.name)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .contentShape(Rectangle())
        .onTapGesture { appState.selectedBookmarkID = bookmark.id }
        .contextMenu {
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: bookmark.path)])
            }
            Button("在终端中打开") {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = ["-a", "Terminal", bookmark.path]
                try? p.run()
            }
            Divider()
            Button("从列表移除…", role: .destructive) { confirmRemove = true }
        }
        .confirmationDialog(
            "移除「\(bookmark.name)」?",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("移除(不删除磁盘文件)", role: .destructive) {
                appState.removeBookmark(bookmark.id)
            }
        } message: {
            Text("仅从侧栏移除,仓库本身不受影响。")
        }
    }
}

// MARK: - 分支行

struct BranchRow: View {
    @ObservedObject var model: RepoModel
    let branch: GitBranch

    private var isCurrent: Bool {
        !branch.isRemote && branch.hash == model.status.headHash && model.status.branch == branch.name
    }

    private var isSelected: Bool { model.section == .branch(branch) }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isCurrent ? Color.accentColor : Color.secondary.opacity(0.55))
                .frame(width: 7, height: 7)
            Text(branch.name)
                .font(.system(size: 13))
                .lineLimit(1)
            if isCurrent {
                Text("✓")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
            }
            Spacer(minLength: 0)
            if let track = trackDisplay(branch.upstreamTrack) {
                Text(track)
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .padding(.leading, 14)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .contentShape(Rectangle())
        .onTapGesture { model.section = .branch(branch) }
        .onTapGesture(count: 2) {
            if !isCurrent { model.checkout(branch) }
        }
        .contextMenu {
            if !isCurrent {
                Button("切换到此分支") { model.checkout(branch) }
            }
            Button("基于此分支新建…") { model.activeSheet = .newBranch(prefill: branch) }
            Divider()
            Button("合并到当前分支…") { model.activeSheet = .merge(prefill: branch) }
            if !branch.isRemote && !isCurrent {
                Button("重命名…") { model.activeSheet = .renameBranch(branch) }
            }
            Divider()
            Button("删除…", role: .destructive) { model.requestDeleteBranch(branch) }
            Divider()
            Button("复制名称") { copyToPasteboard(branch.name) }
        }
    }
}

// MARK: - 远端行

struct RemoteRow: View {
    @ObservedObject var model: RepoModel
    let remote: GitRemote
    @SGState private var expanded = false

    private var isSelected: Bool { model.section == .remote(remote) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }
                Image(systemName: "network")
                    .font(.system(size: 12))
                Text(remote.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .contentShape(Rectangle())
            .onTapGesture { model.section = .remote(remote) }
            .contextMenu {
                Button("获取此远端") { model.fetch(remote) }
                Button("拉取…") { model.activeSheet = .pull }
                Button("推送…") { model.activeSheet = .push }
                Divider()
                Button("复制 URL") { copyToPasteboard(remote.fetchURL) }
            }

            if expanded {
                ForEach(model.remoteBranches.filter { $0.remoteName == remote.name }) { branch in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.secondary.opacity(0.55))
                            .frame(width: 7, height: 7)
                        Text(branch.shortName)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.leading, 22)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture { model.section = .branch(branch) }
                }
            }
        }
    }
}

// MARK: - 贮藏行

struct StashRow: View {
    @ObservedObject var model: RepoModel
    let stash: GitStash

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "archivebox")
                .font(.system(size: 12))
                .frame(width: 16)
            Text(stash.subject)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .padding(.leading, 14)
        .contentShape(Rectangle())
        .help("\(stash.ref) · \(stash.subject)")
        .contextMenu {
            Button("应用(保留贮藏)") { model.stashApply(stash, pop: false) }
            Button("弹出(应用并删除)") { model.stashApply(stash, pop: true) }
            Divider()
            Button("删除…", role: .destructive) { model.requestStashDrop(stash) }
        }
    }
}
