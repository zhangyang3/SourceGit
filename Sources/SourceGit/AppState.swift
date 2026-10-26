import Foundation
import SwiftUI

/// 仓库书签(持久化到 Application Support)。
struct RepoBookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var path: String
}

/// 应用级状态:仓库书签管理与持久化、当前打开的仓库。
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var bookmarks: [RepoBookmark]
    @Published var selectedBookmarkID: UUID? {
        didSet {
            // 重复选中同一仓库不应重建状态机(会丢失提交信息草稿/选中项)
            guard selectedBookmarkID != oldValue else { return }
            persist()
            reopenSelected()
        }
    }
    @Published private(set) var activeRepo: RepoModel?
    @Published var showCloneSheet = false
    @Published var showSettings = false
    /// 侧栏显示状态(自绘标题栏里的切换按钮用)
    @Published var columnVisibility: NavigationSplitViewVisibility = .all
    @Published var lastError: ErrorBox?

    private static var storageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SourceGit", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("bookmarks.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.storageURL),
           let saved = try? JSONDecoder().decode(SavedState.self, from: data) {
            bookmarks = saved.bookmarks
            selectedBookmarkID = saved.selectedID
        } else {
            bookmarks = []
            selectedBookmarkID = nil
        }
        // init 中的赋值不触发 didSet,这里显式恢复上次打开的仓库
        reopenSelected()
    }

    private struct SavedState: Codable {
        var bookmarks: [RepoBookmark]
        var selectedID: UUID?
    }

    private func persist() {
        let state = SavedState(bookmarks: bookmarks, selectedID: selectedBookmarkID)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: Self.storageURL, options: .atomic)
        }
    }

    // MARK: - 书签管理

    /// 校验路径并添加书签(重复路径只选中),失败抛错给调用方展示。
    func addBookmark(path: String) throws {
        let repo = try GitRepository.open(path)
        let abs = repo.path
        if let existing = bookmarks.first(where: { $0.path == abs }) {
            selectedBookmarkID = existing.id
            return
        }
        let bookmark = RepoBookmark(name: repo.name, path: abs)
        bookmarks.append(bookmark)
        selectedBookmarkID = bookmark.id
    }

    func removeBookmark(_ id: UUID) {
        bookmarks.removeAll { $0.id == id }
        if selectedBookmarkID == id {
            selectedBookmarkID = bookmarks.first?.id
        }
    }

    func removeCurrent() {
        if let id = selectedBookmarkID {
            removeBookmark(id)
        }
    }

    private func reopenSelected() {
        guard let id = selectedBookmarkID,
              let bookmark = bookmarks.first(where: { $0.id == id }) else {
            activeRepo = nil
            return
        }
        do {
            activeRepo = try RepoModel(path: bookmark.path, name: bookmark.name)
        } catch {
            lastError = ErrorBox(
                title: "无法打开仓库",
                message: "「\(bookmark.name)」无法作为 git 仓库打开:\n\(ErrorBox(title: "", error: error).message)"
            )
            activeRepo = nil
        }
    }

    // MARK: - 打开

    /// 弹出目录选择面板并尝试添加为书签。
    func openRepoFromPanel() {
        guard let path = openDirectoryPanel(title: "选择 git 仓库目录") else { return }
        do {
            try addBookmark(path: path)
        } catch {
            lastError = ErrorBox(title: "无法打开仓库", error: error)
        }
    }

    // MARK: - 克隆

    /// 克隆远端仓库到 directory/name,成功后加入书签并打开。
    func cloneRepo(url: String, directory: String, name: String) async throws {
        let dest = (directory as NSString).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest) {
            throw GitError(command: "clone", exitCode: -1, stderrText: "目标路径已存在:\n\(dest)", stdoutText: "")
        }
        _ = try await Task.detached(priority: .userInitiated) {
            try GitRepository.clone(url, to: dest)
        }.value
        try addBookmark(path: dest)
    }
}
