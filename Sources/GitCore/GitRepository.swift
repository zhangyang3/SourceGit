import Foundation

/// 仓库句柄:所有高层 git 操作的入口。
///
/// 值类型(仅持有路径),可跨线程安全传递;所有方法为同步调用,
/// UI 层应将其放入后台任务执行。
public struct GitRepository: Sendable {
    /// 空树哈希(sha1 仓库;根提交 diff 的基准)。
    public static let emptyTreeHash = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

    /// 仓库工作区绝对路径
    public let path: String
    /// 展示名(目录名)
    public let name: String

    public init(path: String, name: String? = nil) {
        self.path = path
        self.name = name ?? URL(fileURLWithPath: path).lastPathComponent
    }

    /// 打开并校验一个本地仓库路径。
    public static func open(_ path: String) throws -> GitRepository {
        let abs = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .resolvingSymlinksInPath().path
        _ = try Git.run(["rev-parse", "--git-dir"], cwd: abs)
        return GitRepository(path: abs)
    }

    /// 从 URL 克隆仓库到本地路径。
    public static func clone(_ url: String, to path: String) throws -> GitRepository {
        _ = try Git.run(["clone", url, path])
        return try open(path)
    }

    @discardableResult
    func git(_ args: [String], allowed: Set<Int32> = [0]) throws -> String {
        try Git.run(args, cwd: path, allowedExitCodes: allowed)
    }

    // MARK: - 只读查询

    /// 工作副本状态。
    public func status() throws -> RepoStatus {
        let raw = try git(["status", "--porcelain=v1", "-z", "--branch"])
        var result = RepoStatus()
        let tokens = raw.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var index = 0

        if index < tokens.count, tokens[index].hasPrefix("## ") {
            parseBranchHeader(String(tokens[index].dropFirst(3)), into: &result)
            index += 1
        }
        while index < tokens.count {
            let token = tokens[index]
            index += 1
            let chars = Array(token.prefix(3))
            guard chars.count == 3, chars[2] == " " else { continue }
            let x = chars[0], y = chars[1]
            let entryPath = String(token.dropFirst(3))
            guard !entryPath.isEmpty else { continue }
            var oldPath: String?
            if x == "R" || x == "C" {
                if index < tokens.count {
                    oldPath = tokens[index]
                    index += 1
                }
            }
            result.entries.append(
                WorktreeFile(path: entryPath, oldPath: oldPath, indexStatus: x, worktreeStatus: y)
            )
        }

        if let head = try? git(["rev-parse", "HEAD"]).sg_trimmed(), !head.isEmpty {
            result.headHash = head
        }
        return result
    }

    private func parseBranchHeader(_ header: String, into result: inout RepoStatus) {
        if header.hasPrefix("No commits yet on ") {
            result.branch = String(header.dropFirst("No commits yet on ".count))
            result.isEmptyRepo = true
            return
        }
        if header.hasPrefix("HEAD (no branch)") {
            result.isDetached = true
            return
        }
        var rest = header
        // 去掉尾部 [ahead 1, behind 2]
        if let bracket = rest.range(of: " [") {
            let track = String(rest[bracket.upperBound...].dropLast()) // 去掉 "]"
            rest = String(rest[..<bracket.lowerBound])
            let ahead = track.range(of: #"ahead (\d+)"#, options: .regularExpression)
                .flatMap { Int(track[$0].dropFirst("ahead ".count)) } ?? 0
            let behind = track.range(of: #"behind (\d+)"#, options: .regularExpression)
                .flatMap { Int(track[$0].dropFirst("behind ".count)) } ?? 0
            result.ahead = ahead
            result.behind = behind
        }
        if let sep = rest.range(of: "...") {
            result.branch = String(rest[..<sep.lowerBound])
            result.upstream = String(rest[sep.upperBound...])
        } else {
            result.branch = rest
        }
    }

    /// 提交历史 + 泳道图数据。
    /// - Parameters:
    ///   - scope: git log 的范围参数,如 `["--all"]`、`["refs/heads/main"]`、`["--glob=refs/remotes/origin/*", "HEAD"]`
    ///   - limit: 最多加载条数(分页)
    public func history(
        scope: [String] = ["--all"],
        limit: Int = 800,
        dateOrder: Bool = false
    ) throws -> HistoryData {
        let remoteNames = Set((try? remotes().map(\.name)) ?? [])
        let format = "%H%x1f%h%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%ct%x1f%D%x1f%B%x1e"

        let raw: String
        do {
            let order = dateOrder ? "--date-order" : "--topo-order"
            raw = try git(["log", order] + scope + ["--max-count=\(limit)", "--pretty=format:\(format)"])
        } catch let error as GitError {
            // 空仓库:git log 会 fatal,这里归一化为空历史
            if error.stderrText.contains("does not have any commits yet") || error.stderrText.contains("fatal: your current branch") {
                return HistoryData(commits: [], rows: [], laneCount: 1)
            }
            throw error
        }
        guard !raw.sg_trimmed().isEmpty else {
            return HistoryData(commits: [], rows: [], laneCount: 1)
        }

        var commits: [GitCommit] = []
        commits.reserveCapacity(min(limit, 2000))
        for record in raw.split(separator: "\u{1e}", omittingEmptySubsequences: true) {
            autoreleasepool {
                let text = record.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
                let fields = text.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 9 else { return }
                let hash = fields[0]
                guard !hash.isEmpty else { return }
                let parents = fields[2].split(separator: " ").map(String.init)
                let authorDate = Date(timeIntervalSince1970: Double(fields[5]) ?? 0)
                let commitDate = Date(timeIntervalSince1970: Double(fields[6]) ?? 0)
                commits.append(
                    GitCommit(
                        hash: hash,
                        shortHash: fields[1],
                        parents: parents,
                        authorName: fields[3],
                        authorEmail: fields[4],
                        authorDate: authorDate,
                        commitDate: commitDate,
                        message: fields[8].trimmingCharacters(in: CharacterSet(charactersIn: "\n")),
                        refs: Self.parseRefs(fields[7], remoteNames: remoteNames)
                    )
                )
            }
        }
        let (rows, laneCount) = GraphBuilder.build(commits)
        return HistoryData(commits: commits, rows: rows, laneCount: laneCount)
    }

    static func parseRefs(_ decorations: String, remoteNames: Set<String>) -> [CommitRef] {
        guard !decorations.isEmpty else { return [] }
        return decorations
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { token in
                if token.hasPrefix("HEAD -> ") {
                    return CommitRef(name: String(token.dropFirst(8)), kind: .currentHead)
                }
                if token.hasPrefix("tag: ") {
                    return CommitRef(name: String(token.dropFirst(5)), kind: .tag)
                }
                if token == "stash" {
                    return CommitRef(name: token, kind: .other)
                }
                if let remote = token.split(separator: "/").first, remoteNames.contains(String(remote)) {
                    return CommitRef(name: token, kind: .remoteBranch)
                }
                return CommitRef(name: token, kind: .localBranch)
            }
    }

    /// 分支列表(本地 + 远程)。
    public func branches() throws -> (local: [GitBranch], remote: [GitBranch]) {
        let raw = try git([
            "for-each-ref", "--format=%(refname)%00%(objectname)%00%(upstream:short)%00%(upstream:track)",
            "refs/heads", "refs/remotes",
        ])
        var local: [GitBranch] = []
        var remote: [GitBranch] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4 else { continue }
            let fullName = fields[0]
            let hash = fields[1]
            let track = fields[3]
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            if fullName.hasPrefix("refs/heads/") {
                let name = String(fullName.dropFirst("refs/heads/".count))
                local.append(
                    GitBranch(
                        fullName: fullName, name: name, hash: hash,
                        isRemote: false, shortName: name, remoteName: nil,
                        upstream: fields[2].isEmpty ? nil : fields[2],
                        upstreamTrack: track.isEmpty ? nil : track
                    )
                )
            } else if fullName.hasPrefix("refs/remotes/") {
                let name = String(fullName.dropFirst("refs/remotes/".count))
                // 跳过 origin/HEAD 符号引用
                if name.hasSuffix("/HEAD") { continue }
                let parts = name.split(separator: "/", maxSplits: 1)
                guard parts.count == 2 else { continue }
                remote.append(
                    GitBranch(
                        fullName: fullName, name: name, hash: hash,
                        isRemote: true, shortName: String(parts[1]), remoteName: String(parts[0]),
                        upstream: nil, upstreamTrack: nil
                    )
                )
            }
        }
        return (local, remote)
    }

    /// 标签列表(附注标签哈希已解引用到提交)。
    public func tags() throws -> [GitTag] {
        let raw = try git([
            "for-each-ref", "--format=%(refname)%00%(objectname)%00%(*objectname)", "refs/tags",
        ])
        return raw.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3, fields[0].hasPrefix("refs/tags/") else { return nil }
            let peeled = fields[2].isEmpty ? fields[1] : fields[2]
            return GitTag(fullName: fields[0], name: String(fields[0].dropFirst("refs/tags/".count)), hash: peeled)
        }
    }

    /// 远端列表。
    public func remotes() throws -> [GitRemote] {
        let raw = try git(["remote", "-v"])
        var fetchURLs: [String: String] = [:]
        var pushURLs: [String: String] = [:]
        var order: [String] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.components(separatedBy: "\t")
            guard parts.count == 2 else { continue }
            let name = parts[0]
            let urlPart = parts[1]
            guard let open = urlPart.lastIndex(of: "("), let close = urlPart.lastIndex(of: ")"), open < close else { continue }
            let kind = String(urlPart[urlPart.index(after: open)..<close])
            let url = String(urlPart[..<open]).trimmingCharacters(in: .whitespaces)
            if !order.contains(name) { order.append(name) }
            if kind == "fetch" { fetchURLs[name] = url } else if kind == "push" { pushURLs[name] = url }
        }
        return order.map {
            GitRemote(name: $0, fetchURL: fetchURLs[$0] ?? "", pushURL: pushURLs[$0] ?? fetchURLs[$0] ?? "")
        }
    }

    /// 贮藏列表。
    public func stashes() throws -> [GitStash] {
        let raw = try git(["stash", "list", "--format=%gd%x1f%H%x1f%s"])
        return raw.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3, fields[0].hasPrefix("stash@{") else { return nil }
            let idx = fields[0]
                .dropFirst("stash@{".count)
                .prefix { $0.isNumber }
            return GitStash(ref: fields[0], index: Int(idx) ?? 0, hash: fields[1], subject: fields[2])
        }
    }

    /// 当前分支名;分离头指针返回 nil。
    public func currentBranch() throws -> String? {
        let out = try git(["rev-parse", "--abbrev-ref", "HEAD"]).sg_trimmed()
        return out == "HEAD" ? nil : out
    }

    /// 某个提交相对其第一父提交(或空树)的变更文件摘要(不含 hunk 内容)。
    /// 大提交时用本方法渲染文件列表,选中文件后再用 diffCommit(path:) 取差分,
    /// 避免一次性解析整个提交的全部 diff(内存策略,见 PLAN §2.2)。
    public func diffCommitChanges(_ hash: String) throws -> [CommitFileChange] {
        let parents = try parents(of: hash)
        let from = parents.first ?? Self.emptyTreeHash
        let namesRaw = try git(["diff", "--name-status", "--no-color", "--find-renames", from, hash])
        // numstat 与 name-status 输出顺序一致,按下标对齐
        let statsRaw = try git(["diff", "--numstat", "--no-color", "--find-renames", from, hash])
        let stats = statsRaw.split(separator: "\n", omittingEmptySubsequences: true)

        var result: [CommitFileChange] = []
        let lines = namesRaw.split(separator: "\n", omittingEmptySubsequences: true)
        for (index, line) in lines.enumerated() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let code = fields.first, !code.isEmpty else { continue }
            let kindChar = code.first!
            var kind = FileChangeKind.modified
            var oldPath: String?
            var path: String
            switch kindChar {
            case "A": kind = .added; path = fields.count > 1 ? fields[1] : ""
            case "D": kind = .deleted; path = fields.count > 1 ? fields[1] : ""
            case "R": kind = .renamed; oldPath = fields.count > 1 ? fields[1] : nil; path = fields.count > 2 ? fields[2] : (oldPath ?? "")
            case "C": kind = .copied; oldPath = fields.count > 1 ? fields[1] : nil; path = fields.count > 2 ? fields[2] : (oldPath ?? "")
            case "T": kind = .typechange; path = fields.count > 1 ? fields[1] : ""
            default: path = fields.count > 1 ? fields[1] : ""   // M / U
            }
            var adds: Int?
            var dels: Int?
            if index < stats.count {
                let sf = stats[index].split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                if sf.count >= 3, sf[0] != "-" {
                    adds = Int(sf[0])
                    dels = Int(sf[1])
                }
            }
            result.append(CommitFileChange(path: path, oldPath: oldPath, kind: kind, adds: adds, dels: dels))
        }
        return result
    }

    /// 指定提交的父提交哈希列表(按顺序)。
    public func parents(of hash: String) throws -> [String] {
        let out = try git(["rev-list", "--parents", "-n", "1", hash]).sg_trimmed()
        let parts = out.split(separator: " ").map(String.init)
        return Array(parts.dropFirst())
    }

    /// .git 目录绝对路径(用于探测进行中的合并/变基)。
    public func gitDir() -> String {
        if let dir = try? git(["rev-parse", "--absolute-git-dir"]).sg_trimmed(), !dir.isEmpty {
            return dir
        }
        return path + "/.git"
    }

    /// 是否有合并进行中(MERGE_HEAD 存在)。
    public var mergeInProgress: Bool {
        FileManager.default.fileExists(atPath: gitDir() + "/MERGE_HEAD")
    }

    /// 是否有变基进行中。
    public var rebaseInProgress: Bool {
        let dir = gitDir()
        let fm = FileManager.default
        return fm.fileExists(atPath: dir + "/rebase-merge") || fm.fileExists(atPath: dir + "/rebase-apply")
    }

    // MARK: - Diff

    /// 未暂存改动(工作区 vs 暂存区)。
    public func diffWorktree(_ path: String? = nil) throws -> [DiffFile] {
        try diffImpl([], path)
    }

    /// 已暂存改动(暂存区 vs HEAD)。
    public func diffStaged(_ path: String? = nil) throws -> [DiffFile] {
        try diffImpl(["--cached"], path)
    }

    /// 全部未提交改动(工作区 vs HEAD)。
    public func diffHead(_ path: String? = nil) throws -> [DiffFile] {
        try diffImpl(["HEAD"], path)
    }

    /// 任意两个提交间的改动;from 传空串表示对空树(即全部为新增)。
    public func diffRange(from: String, to: String, path: String? = nil) throws -> [DiffFile] {
        let base = from.isEmpty ? Self.emptyTreeHash : from
        return try diffImpl([base, to], path)
    }

    /// 某个提交相对其第一父提交(或空树)的改动;合并提交按第一父处理。
    public func diffCommit(_ hash: String, path: String? = nil) throws -> [DiffFile] {
        let parents = try parents(of: hash)
        return try diffRange(from: parents.first ?? "", to: hash, path: path)
    }

    /// 未跟踪文件的内容 diff(借助 --no-index 与 /dev/null 对比)。
    public func diffUntracked(_ path: String) throws -> [DiffFile] {
        let raw = try git(["diff", "--no-color", "--no-index", "--", "/dev/null", path], allowed: [0, 1])
        return DiffParser.parse(raw)
    }

    private func diffImpl(_ extra: [String], _ path: String?) throws -> [DiffFile] {
        var args = ["diff", "--no-color", "--no-ext-diff", "--find-renames", "--unified=3"]
        args += extra
        if let path {
            args += ["--", path]
        }
        return DiffParser.parse(try git(args))
    }

    // MARK: - 工作副本写操作

    /// 暂存文件(含未跟踪文件)。
    public func stage(_ paths: [String]) throws {
        guard !paths.isEmpty else { return }
        try git(["add", "--"] + paths)
    }

    /// 取消暂存。首个提交尚未创建时(无 HEAD)自动回退到 `rm --cached`。
    public func unstage(_ paths: [String]) throws {
        guard !paths.isEmpty else { return }
        do {
            try git(["reset", "-q", "HEAD", "--"] + paths)
        } catch {
            try git(["rm", "--cached", "-q", "-r", "--"] + paths)
        }
    }

    /// 放弃工作区改动(恢复为暂存区版本)。
    public func discardWorktreeChanges(_ paths: [String]) throws {
        guard !paths.isEmpty else { return }
        try git(["checkout", "-q", "--"] + paths)
    }

    /// 删除未跟踪文件。
    public func removeUntracked(_ paths: [String]) throws {
        guard !paths.isEmpty else { return }
        try git(["clean", "-q", "-f", "--"] + paths)
    }

    /// 提交暂存区。
    public func commit(message: String, amend: Bool = false) throws {
        var args = ["commit", "-m", message]
        if amend { args += ["--amend"] }
        try git(args)
    }

    /// HEAD 提交的完整提交信息(用于 amend 预填)。
    public func headMessage() throws -> String {
        try git(["log", "-1", "--pretty=%B"])
    }

    /// 某路径是否存在于 HEAD 提交中(空仓库 / 未跟踪返回 false)。
    public func fileExistsInHEAD(_ path: String) -> Bool {
        (try? git(["cat-file", "-e", "HEAD:\(path)"])) != nil
    }

    // MARK: - 分支操作

    /// 创建分支。
    public func createBranch(_ name: String, from startPoint: String? = nil, checkout: Bool = false) throws {
        let start = startPoint.map { [$0] } ?? []
        if checkout {
            try git(["checkout", "-b", name] + start)
        } else {
            try git(["branch", name] + start)
        }
    }

    /// 切换分支;对远程分支自动创建跟踪分支。
    public func checkout(_ ref: String) throws {
        try git(["checkout", ref])
    }

    /// 切换到远程分支,自动创建同名本地跟踪分支。
    public func checkoutRemote(_ remoteBranch: String) throws {
        try git(["checkout", "-t", remoteBranch])
    }

    /// 删除分支(远程分支实际执行 push --delete)。
    public func deleteBranch(_ branch: GitBranch, force: Bool = false) throws {
        if branch.isRemote {
            guard let remote = branch.remoteName else { return }
            try git(["push", remote, "--delete", branch.shortName])
        } else {
            try git(["branch", force ? "-D" : "-d", branch.name])
        }
    }

    /// 重命名本地分支。
    public func renameBranch(_ from: String, to: String) throws {
        try git(["branch", "-m", from, to])
    }

    // MARK: - 远端操作

    /// 拉取远端对象;remote 为 nil 时抓取全部远端。
    public func fetch(_ remote: String? = nil, prune: Bool = true) throws {
        if let remote {
            try git(["fetch", prune ? "--prune" : nil, remote].compactMap { $0 })
        } else {
            try git(["fetch", "--all", prune ? "--prune" : nil].compactMap { $0 })
        }
    }

    /// 拉取并合并。
    public func pull(remote: String, branch: String, rebase: Bool = false, ffOnly: Bool = false) throws {
        let flags = [rebase ? "--rebase" : nil, ffOnly ? "--ff-only" : nil].compactMap { $0 }
        try git(["pull"] + flags + [remote, branch])
    }

    /// 推送。
    public func push(remote: String, branch: String, setUpstream: Bool = false, forceWithLease: Bool = false) throws {
        let flags = [setUpstream ? "-u" : nil, forceWithLease ? "--force-with-lease" : nil].compactMap { $0 }
        try git(["push"] + flags + [remote, branch])
    }

    /// 合并指定引用到当前分支。
    public func merge(_ ref: String, noFF: Bool = false) throws {
        try git(["merge", noFF ? "--no-ff" : nil, ref].compactMap { $0 })
    }

    /// 终止进行中的合并。
    public func abortMerge() throws {
        try git(["merge", "--abort"])
    }

    // MARK: - 贮藏操作

    /// 创建贮藏。
    public func stashSave(message: String? = nil, includeUntracked: Bool = false, keepIndex: Bool = false) throws {
        var args = ["stash", "push"]
        if includeUntracked { args.append("-u") }
        if keepIndex { args.append("-k") }
        if let message, !message.isEmpty { args += ["-m", message] }
        try git(args)
    }

    /// 应用贮藏(pop=true 同时删除该贮藏;reinstateIndex 恢复暂存状态)。
    public func stashApply(_ stash: GitStash, pop: Bool = false, reinstateIndex: Bool = false) throws {
        var args = ["stash", pop ? "pop" : "apply"]
        if reinstateIndex { args.append("--index") }
        args.append(stash.ref)
        try git(args)
    }

    /// 删除贮藏。
    public func stashDrop(_ stash: GitStash) throws {
        try git(["stash", "drop", stash.ref])
    }
}
