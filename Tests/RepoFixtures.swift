import Foundation

/// 测试夹具:在临时目录创建真实 git 仓库。
/// 全部走真实 git 命令,保证与生产路径一致。
final class FixtureRepo {
    let dir: String

    init() throws {
        dir = NSTemporaryDirectory() + "sourcegit-tests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try git("init", "-b", "main")
        try git("config", "user.email", "test@sourcegit.local")
        try git("config", "user.name", "SourceGit 测试")
        try git("config", "commit.gpgsign", "false")
    }

    deinit {
        try? FileManager.default.removeItem(atPath: dir)
    }

    /// 以仓库为 cwd 执行 git 命令,返回去除首尾空白的结果。
    @discardableResult
    func git(_ args: String...) throws -> String {
        try Git.run(args, cwd: dir).sg_trimmed()
    }

    /// 写文件(自动创建父目录)。
    func write(_ path: String, content: String) throws {
        try write(path, data: Data(content.utf8))
    }

    func write(_ path: String, data: Data) throws {
        let full = (dir as NSString).appendingPathComponent(path)
        try FileManager.default.createDirectory(
            atPath: (full as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try data.write(to: URL(fileURLWithPath: full))
    }

    /// 写文件 + add + commit,返回提交哈希。
    @discardableResult
    func commit(_ fileName: String, content: String, message: String) throws -> String {
        try write(fileName, content: content)
        try git("add", "-A")
        try git("commit", "-m", message)
        return try git("rev-parse", "HEAD")
    }

    func open() throws -> GitRepository {
        try GitRepository.open(dir)
    }
}
