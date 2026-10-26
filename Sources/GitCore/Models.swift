import Foundation

// MARK: - 工作副本(状态)

/// 单个文件的变更类型。
public enum FileChangeKind: String, Sendable, Hashable {
    case added       // 新增
    case modified    // 修改
    case deleted     // 删除
    case renamed     // 重命名
    case copied      // 复制
    case untracked   // 未跟踪
    case conflicted  // 冲突
    case typechange  // 类型变化(文件↔软链等)

    /// 由 porcelain 状态字符映射。
    public static func from(_ c: Character) -> FileChangeKind? {
        switch c {
        case "A": return .added
        case "M": return .modified
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .copied
        case "?": return .untracked
        case "U": return .conflicted
        case "T": return .typechange
        default: return nil
        }
    }
}

/// `git status --porcelain` 中的一个条目。
/// 同一文件可能同时出现在「已暂存」与「未暂存」两个分组(部分暂存)。
public struct WorktreeFile: Identifiable, Hashable, Sendable {
    /// 当前路径(重命名后为新路径)
    public let path: String
    /// 重命名/复制时的原路径
    public let oldPath: String?
    /// 暂存区状态字符 X
    public let indexStatus: Character
    /// 工作区状态字符 Y
    public let worktreeStatus: Character

    public var id: String { path }
    public var isUntracked: Bool { indexStatus == "?" && worktreeStatus == "?" }
    public var isStagedEntry: Bool { !isUntracked && indexStatus != " " }
    public var isWorktreeEntry: Bool { isUntracked || worktreeStatus != " " }
    public var isConflicted: Bool {
        indexStatus == "U" || worktreeStatus == "U"
            || (indexStatus == "A" && worktreeStatus == "A")
            || (indexStatus == "D" && worktreeStatus == "D")
    }
    /// 该文件在「已暂存」分组中的展示类型。
    public var stagedKind: FileChangeKind {
        if isConflicted { return .conflicted }
        return FileChangeKind.from(indexStatus) ?? .modified
    }
    /// 该文件在「未暂存」分组中的展示类型。
    public var worktreeKind: FileChangeKind {
        if isUntracked { return .untracked }
        if isConflicted { return .conflicted }
        return FileChangeKind.from(worktreeStatus) ?? .modified
    }
}

/// `git status` 的完整快照。
public struct RepoStatus: Sendable, Equatable {
    public var branch: String?
    public var upstream: String?
    public var ahead = 0
    public var behind = 0
    public var isDetached = false
    /// 空仓库(尚无任何提交)
    public var isEmptyRepo = false
    public var headHash = ""
    public var entries: [WorktreeFile] = []

    public init() {}

    public var staged: [WorktreeFile] { entries.filter { $0.isStagedEntry } }
    public var unstaged: [WorktreeFile] { entries.filter { $0.isWorktreeEntry } }
    public var hasUpstreamDelta: Bool { ahead > 0 || behind > 0 }
}

// MARK: - 提交与引用

/// 提交上挂着的引用类型。
public enum RefKind: Sendable, Hashable {
    case currentHead   // HEAD -> branch
    case localBranch
    case remoteBranch
    case tag
    case other
}

public struct CommitRef: Sendable, Hashable {
    public let name: String
    public let kind: RefKind

    public init(name: String, kind: RefKind) {
        self.name = name
        self.kind = kind
    }
}

/// 一条提交记录。
public struct GitCommit: Identifiable, Sendable {
    public let id: String            // 完整哈希
    public let hash: String
    public let shortHash: String
    public let parents: [String]
    public let authorName: String
    public let authorEmail: String
    public let authorDate: Date
    public let commitDate: Date
    /// 完整提交信息(%B,已去尾换行)
    public let message: String
    /// 解析自 %D 的引用装饰
    public var refs: [CommitRef] = []

    public init(
        hash: String,
        shortHash: String,
        parents: [String],
        authorName: String,
        authorEmail: String,
        authorDate: Date,
        commitDate: Date,
        message: String,
        refs: [CommitRef] = []
    ) {
        self.id = hash
        self.hash = hash
        self.shortHash = shortHash
        self.parents = parents
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.authorDate = authorDate
        self.commitDate = commitDate
        self.message = message
        self.refs = refs
    }

    /// 提交主题(第一行)。
    public var subject: String {
        guard let idx = message.firstIndex(of: "\n") else { return message }
        return String(message[..<idx])
    }

    /// 主题之后的正文(已去首尾空白,可为空)。
    public var body: String {
        guard let idx = message.firstIndex(of: "\n") else { return "" }
        let start = message.index(after: idx)
        return String(message[start...]).sg_trimmed()
    }
}

// MARK: - 分支 / 标签 / 远端 / 贮藏

public struct GitBranch: Identifiable, Hashable, Sendable {
    public var id: String { fullName }
    /// refs/heads/main 或 refs/remotes/origin/main
    public let fullName: String
    /// 展示名:main 或 origin/main
    public let name: String
    public let hash: String
    public let isRemote: Bool
    /// 去掉远端前缀后的短名(origin/main → main)
    public let shortName: String
    /// 仅远程分支:远端名(origin)
    public let remoteName: String?
    /// 仅本地分支:上游分支短名
    public let upstream: String?
    /// 上游跟踪状态原始文本(如 "ahead 2"、"behind 1"、"ahead 1, behind 2"、"gone")
    public let upstreamTrack: String?

    public init(
        fullName: String,
        name: String,
        hash: String,
        isRemote: Bool,
        shortName: String,
        remoteName: String?,
        upstream: String?,
        upstreamTrack: String?
    ) {
        self.fullName = fullName
        self.name = name
        self.hash = hash
        self.isRemote = isRemote
        self.shortName = shortName
        self.remoteName = remoteName
        self.upstream = upstream
        self.upstreamTrack = upstreamTrack
    }
}

public struct GitTag: Identifiable, Hashable, Sendable {
    public var id: String { fullName }
    public let fullName: String   // refs/tags/v1.0
    public let name: String       // v1.0
    /// 附注标签已解引用到指向的提交哈希
    public let hash: String
}

public struct GitRemote: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let fetchURL: String
    public let pushURL: String
}

public struct GitStash: Identifiable, Hashable, Sendable {
    public var id: String { ref }
    /// stash@{0}
    public let ref: String
    public let index: Int
    public let hash: String
    public let subject: String
}

/// 提交的变更文件摘要(不带 hunk,用于列表;大提交时避免一次性解析全部 diff)。
public struct CommitFileChange: Identifiable, Hashable, Sendable {
    public var id: String { (oldPath ?? "") + "→" + path }
    /// 当前(新)路径;删除文件为原路径
    public let path: String
    /// 重命名/复制时的原路径
    public let oldPath: String?
    public let kind: FileChangeKind
    /// 增/删行数;二进制为 nil
    public let adds: Int?
    public let dels: Int?
}

// MARK: - Diff 模型

public enum DiffFileKind: Sendable, Hashable {
    case modified
    case added
    case deleted
    case renamed
    case copied
    case binary
}

public enum DiffLineKind: Sendable, Hashable {
    case context
    case added
    case deleted
    /// "\ No newline at end of file" 等元信息行
    case meta
}

public struct DiffLine: Identifiable, Hashable, Sendable {
    public let id: Int
    public let kind: DiffLineKind
    public let oldNumber: Int?
    public let newNumber: Int?
    public let text: String
}

public struct DiffHunk: Identifiable, Hashable, Sendable {
    public let id: Int
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    /// hunk 头 @@ 行尾的上下文(函数名等)
    public let context: String
    public let lines: [DiffLine]

    public var adds: Int { lines.filter { $0.kind == .added }.count }
    public var dels: Int { lines.filter { $0.kind == .deleted }.count }
    public var header: String { "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@" }
}

public struct DiffFile: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let oldPath: String?    // /dev/null → nil(新增文件)
    public let newPath: String?    // /dev/null → nil(删除文件)
    public let kind: DiffFileKind
    public let oldMode: String?
    public let newMode: String?
    /// 重命名相似度(0–100)
    public let renameScore: Int?
    public let hunks: [DiffHunk]

    public init(
        id: UUID = UUID(),
        oldPath: String?,
        newPath: String?,
        kind: DiffFileKind,
        oldMode: String?,
        newMode: String?,
        renameScore: Int?,
        hunks: [DiffHunk]
    ) {
        self.id = id
        self.oldPath = oldPath
        self.newPath = newPath
        self.kind = kind
        self.oldMode = oldMode
        self.newMode = newMode
        self.renameScore = renameScore
        self.hunks = hunks
    }

    /// 列表展示用的路径。
    public var displayName: String { newPath ?? oldPath ?? "?" }
    /// 重命名展示:"old → new"
    public var renameDisplay: String? {
        guard kind == .renamed || kind == .copied, let old = oldPath, let new = newPath, old != new else { return nil }
        return "\(old) → \(new)"
    }
    public var adds: Int { hunks.reduce(0) { $0 + $1.adds } }
    public var dels: Int { hunks.reduce(0) { $0 + $1.dels } }
}

/// 一次 history 查询的结果:提交列表 + 泳道图数据。
public struct HistoryData: Sendable {
    public let commits: [GitCommit]
    public let rows: [CommitGraphRow]
    public let laneCount: Int

    public init(commits: [GitCommit], rows: [CommitGraphRow], laneCount: Int) {
        self.commits = commits
        self.rows = rows
        self.laneCount = laneCount
    }
}
