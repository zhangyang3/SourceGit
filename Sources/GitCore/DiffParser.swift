import Foundation

/// unified diff 文本解析器。
///
/// 处理 `git diff` 输出的全部头域:
/// `diff --git` / `old mode` / `new mode` / `new file mode` / `deleted file mode` /
/// `similarity index` / `rename from|to` / `copy from|to` / `index` /
/// `--- a/…|/dev/null` / `+++ b/…|/dev/null` / `@@ hunk @@` /
/// `Binary files … differ` / `GIT binary patch` / `\ No newline at end of file`。
public enum DiffParser {

    public static func parse(_ raw: String) -> [DiffFile] {
        guard !raw.isEmpty else { return [] }

        var files: [DiffFile] = []
        var builder = FileBuilder()
        var hunk: HunkBuilder?
        var lineSeq = 0

        func flushHunk() {
            if let h = hunk {
                builder.hunks.append(h.build())
                hunk = nil
            }
        }
        func flushFile() {
            flushHunk()
            if let f = builder.build() {
                files.append(f)
            }
            builder = FileBuilder()
        }

        var lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // 丢弃输出末尾换行符产生的空段,避免误当作上下文行
        if lines.last == "" { lines.removeLast() }

        for line in lines {
            autoreleasepool {
                if line.hasPrefix("diff --git ") {
                    flushFile()
                    builder.parseHeaderPaths(line)
                    return
                }
                if line.hasPrefix("old mode ") { builder.oldMode = String(line.dropFirst("old mode ".count)); return }
                if line.hasPrefix("new mode ") { builder.newMode = String(line.dropFirst("new mode ".count)); return }
                if line.hasPrefix("new file mode ") { builder.sawNewFile = true; return }
                if line.hasPrefix("deleted file mode ") { builder.sawDeleted = true; return }
                if line.hasPrefix("similarity index ") {
                    let digits = line.dropFirst("similarity index ".count).prefix { $0.isNumber }
                    builder.renameScore = Int(digits)
                    return
                }
                if line.hasPrefix("rename from ") { builder.oldPath = String(line.dropFirst("rename from ".count)); builder.sawRename = true; return }
                if line.hasPrefix("rename to ") { builder.newPath = String(line.dropFirst("rename to ".count)); builder.sawRename = true; return }
                if line.hasPrefix("copy from ") { builder.oldPath = String(line.dropFirst("copy from ".count)); builder.sawCopy = true; return }
                if line.hasPrefix("copy to ") { builder.newPath = String(line.dropFirst("copy to ".count)); builder.sawCopy = true; return }
                if line.hasPrefix("index ") { return }
                if line.hasPrefix("--- ") { builder.oldPath = parsePath(line.dropFirst("--- ".count)); return }
                if line.hasPrefix("+++ ") { builder.newPath = parsePath(line.dropFirst("+++ ".count)); return }
                if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") { builder.sawBinary = true; return }

                if line.hasPrefix("@@") {
                    flushHunk()
                    hunk = HunkBuilder(headerLine: line)
                    return
                }
                if line.hasPrefix("diff --") {
                    // 罕见兜底(如 --no-index 且无 git 头)
                    flushFile()
                    return
                }
                if hunk != nil {
                    lineSeq += 1
                    let first = line.first.map(String.init) ?? ""
                    switch first {
                    case "+":
                        hunk?.append(.added, oldNo: nil, newNo: hunk!.nextNew, text: String(line.dropFirst()), seq: lineSeq)
                        hunk?.nextNew += 1
                    case "-":
                        hunk?.append(.deleted, oldNo: hunk!.nextOld, newNo: nil, text: String(line.dropFirst()), seq: lineSeq)
                        hunk?.nextOld += 1
                    case "\\":
                        hunk?.append(.meta, oldNo: nil, newNo: nil, text: line, seq: lineSeq)
                    default:
                        // 上下文行(前导空格)与空字符串行
                        hunk?.append(.context, oldNo: hunk!.nextOld, newNo: hunk!.nextNew, text: String(line.dropFirst(line.hasPrefix(" ") ? 1 : 0)), seq: lineSeq)
                        hunk?.nextOld += 1
                        hunk?.nextNew += 1
                    }
                }
            }
        }
        flushFile()
        return files
    }

    /// `a/path`、`b/path`、`/dev/null` → path / nil。
    private static func parsePath(_ s: Substring) -> String? {
        let text = String(s)
        if text == "/dev/null" { return nil }
        if text.hasPrefix("a/") || text.hasPrefix("b/") {
            return String(text.dropFirst(2))
        }
        return text
    }
}

// MARK: - 构建器

private final class HunkBuilder {
    /// @@ -oldStart[,oldCount] +newStart[,newCount] @@ context
    static let headerRegex = try! NSRegularExpression(
        pattern: #"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#
    )

    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let context: String
    var nextOld: Int
    var nextNew: Int
    private var lines: [DiffLine] = []

    init?(headerLine: String) {
        guard let m = Self.headerRegex.firstMatch(in: headerLine, range: NSRange(headerLine.startIndex..., in: headerLine)) else {
            return nil
        }
        func group(_ i: Int) -> String? {
            guard let r = Range(m.range(at: i), in: headerLine) else { return nil }
            return String(headerLine[r])
        }
        oldStart = Int(group(1) ?? "0") ?? 0
        oldCount = Int(group(2) ?? "1") ?? 1
        newStart = Int(group(3) ?? "0") ?? 0
        newCount = Int(group(4) ?? "1") ?? 1
        nextOld = oldStart
        nextNew = newStart
        // 上下文:第二个 @@ 之后的部分
        if let first = headerLine.range(of: "@@") {
            let rest = headerLine[first.upperBound...]
            if let second = rest.range(of: "@@") {
                context = String(rest[second.upperBound...])
            } else {
                context = String(rest)
            }
        } else {
            context = ""
        }
    }

    func append(_ kind: DiffLineKind, oldNo: Int?, newNo: Int?, text: String, seq: Int) {
        lines.append(DiffLine(id: seq, kind: kind, oldNumber: oldNo, newNumber: newNo, text: text))
    }

    func build() -> DiffHunk {
        DiffHunk(
            id: oldStart * 100_003 + newStart,
            oldStart: oldStart, oldCount: oldCount,
            newStart: newStart, newCount: newCount,
            context: context, lines: lines
        )
    }
}

private final class FileBuilder {
    var oldPath: String?
    var newPath: String?
    var oldMode: String?
    var newMode: String?
    var renameScore: Int?
    var sawNewFile = false
    var sawDeleted = false
    var sawRename = false
    var sawCopy = false
    var sawBinary = false
    var hunks: [DiffHunk] = []

    /// 从 `diff --git a/x b/y` 提取路径(仅作为缺少 ---/+++ 时的兜底,如二进制文件)。
    func parseHeaderPaths(_ line: String) {
        // 去掉前缀后形如 "a/x b/y"(x 本身也可能含空格,此兜底不追求完美)
        let payload = String(line.dropFirst("diff --git ".count))
        guard let bRange = payload.range(of: " b/") else { return }
        let old = String(payload[..<bRange.lowerBound])
        newPath = String(payload[bRange.upperBound...])
        oldPath = old.hasPrefix("a/") ? String(old.dropFirst(2)) : old
    }

    func build() -> DiffFile? {
        let kind: DiffFileKind
        if sawBinary {
            kind = .binary
        } else if sawRename {
            kind = .renamed
        } else if sawCopy {
            kind = .copied
        } else if sawNewFile || oldPath == nil {
            kind = .added
        } else if sawDeleted || newPath == nil {
            kind = .deleted
        } else {
            kind = .modified
        }
        guard sawBinary || sawNewFile || sawDeleted || sawRename || sawCopy
            || oldPath != nil || newPath != nil || !hunks.isEmpty else { return nil }
        return DiffFile(
            oldPath: oldPath,
            newPath: newPath,
            kind: kind,
            oldMode: oldMode,
            newMode: newMode,
            renameScore: renameScore,
            hunks: hunks
        )
    }
}
