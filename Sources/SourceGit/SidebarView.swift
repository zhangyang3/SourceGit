import SwiftUI

/// 侧栏:仓库列表 + 当前仓库分组。
struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                sidebarHeader("仓库")
                ForEach(appState.bookmarks) { bookmark in
                    BookmarkRow(bookmark: bookmark)
                }
                if appState.bookmarks.isEmpty {
                    Text("尚未添加仓库\n使用 ⌘O 打开")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }

                if let model = appState.activeRepo {
                    Divider().padding(.vertical, 6)
                    RepoGroupsView(model: model)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func sidebarHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }
}

// MARK: - 仓库书签行

struct BookmarkRow: View {
    @EnvironmentObject var appState: AppState
    let bookmark: RepoBookmark
    @SGState private var confirmRemove = false

    private var isSelected: Bool { appState.selectedBookmarkID == bookmark.id }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(.tint)
            Text(bookmark.name)
                .lineLimit(1)
                .fontWeight(isSelected ? .semibold : .regular)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .rowBackground(selected: isSelected)
        .onTapGesture { appState.selectedBookmarkID = bookmark.id }
        .contextMenu {
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: bookmark.path)])
            }
            Button("打开终端") {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = ["-a", "Terminal", bookmark.path]
                try? p.run()
            }
            Divider()
            Button("从列表移除…", role: .destructive) {
                confirmRemove = true
            }
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
            Text("仅从 SourceGit 侧栏移除,仓库本身不受影响。")
        }
    }
}

// MARK: - 当前仓库分组

struct RepoGroupsView: View {
    @ObservedObject var model: RepoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            sidebarSectionRow(.status, icon: "pencil.and.list.clipboard", title: "工作副本",
                              badge: model.status.entries.isEmpty ? nil : "\(model.status.entries.count)")
            sidebarSectionRow(.history, icon: "clock.arrow.circlepath", title: "历史")

            DisclosureSection(icon: "arrow.triangle.branch", title: "分支", count: model.branches.count + model.remoteBranches.count) {
                if !model.branches.isEmpty {
                    groupCaption("本地")
                    ForEach(model.branches) { branch in
                        BranchRow(model: model, branch: branch)
                    }
                }
                if !model.remoteBranches.isEmpty {
                    groupCaption("远程")
                    ForEach(model.remoteBranches) { branch in
                        BranchRow(model: model, branch: branch)
                    }
                }
            }

            DisclosureSection(icon: "tag", title: "标签", count: model.tags.count) {
                ForEach(model.tags) { tag in
                    sidebarSectionRow(.tag(tag), icon: "tag", title: tag.name)
                }
            }

            DisclosureSection(icon: "antenna.radiowaves.left.and.right", title: "远端", count: model.remotes.count) {
                ForEach(model.remotes) { remote in
                    RemoteRow(model: model, remote: remote)
                }
            }

            DisclosureSection(icon: "archivebox", title: "贮藏", count: model.stashes.count) {
                if model.stashes.isEmpty {
                    Text("暂无贮藏")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                }
                ForEach(model.stashes) { stash in
                    StashRow(model: model, stash: stash)
                }
            }
        }
    }

    private func groupCaption(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 24)
            .padding(.top, 2)
    }

    @ViewBuilder
    private func sidebarSectionRow(
        _ section: SidebarSection,
        icon: String,
        title: String,
        badge: String? = nil,
        subtitle: String? = nil
    ) -> some View {
        let selected = model.section == section
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .lineLimit(1)
            if let badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .rowBackground(selected: selected)
        .onTapGesture { model.section = section }
        .help(subtitle ?? title)
    }
}

// MARK: - 分支行

struct BranchRow: View {
    @ObservedObject var model: RepoModel
    let branch: GitBranch

    private var isCurrent: Bool {
        !branch.isRemote && branch.hash == model.status.headHash
            && model.status.branch == branch.name
    }

    private var subtitle: String? {
        var parts: [String] = []
        if !branch.isRemote, let upstream = branch.upstream {
            parts.append(upstream)
        }
        if let track = trackDisplay(branch.upstreamTrack) {
            parts.append(track)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(SGPalette.laneColor(branch.isRemote ? 2 : 0))
                .frame(width: 6, height: 6)
            Text(branch.name)
                .lineLimit(1)
                .fontWeight(isCurrent ? .semibold : .regular)
            if isCurrent {
                Text("✓")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
            }
            if let track = trackDisplay(branch.upstreamTrack) {
                Text(track)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .padding(.leading, 16)
        .contentShape(Rectangle())
        .rowBackground(selected: model.section == .branch(branch))
        .onTapGesture { model.section = .branch(branch) }
        .onTapGesture(count: 2) {
            if !isCurrent { model.checkout(branch) }
        }
        .help(subtitle ?? branch.fullName)
        .contextMenu {
            if !isCurrent {
                Button("切换到此分支") { model.checkout(branch) }
            }
            Button("基于此分支新建…") { model.activeSheet = .newBranch(prefill: branch) }
            Divider()
            Button("合并到当前分支…") { model.activeSheet = .merge(prefill: branch) }
            if !branch.isRemote && !isCurrent {
                Divider()
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

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "network")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(remote.name)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .padding(.leading, 16)
        .contentShape(Rectangle())
        .rowBackground(selected: model.section == .remote(remote))
        .onTapGesture { model.section = .remote(remote) }
        .help(remote.fetchURL)
        .contextMenu {
            Button("获取此远端") { model.fetch(remote) }
            Button("拉取此远端…") { model.activeSheet = .pull }
            Button("推送…") { model.activeSheet = .push }
            Divider()
            Button("复制 URL") { copyToPasteboard(remote.fetchURL) }
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
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(stash.subject)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .padding(.leading, 16)
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

// MARK: - 可折叠分组

struct DisclosureSection<Content: View>: View {
    let icon: String
    let title: String
    let count: Int
    @ViewBuilder let content: Content
    @SGState private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }

            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    content
                }
                .transition(.opacity)
            }
        }
    }
}
