import Foundation

/// git 命令执行失败的错误。
public struct GitError: Error, CustomStringConvertible {
    /// 失败的 git 子命令(不含全局参数)
    public let command: String
    public let exitCode: Int32
    public let stderrText: String
    public let stdoutText: String

    public init(command: String, exitCode: Int32, stderrText: String, stdoutText: String) {
        self.command = command
        self.exitCode = exitCode
        self.stderrText = stderrText
        self.stdoutText = stdoutText
    }

    public var description: String {
        let err = stderrText.sg_trimmed()
        let out = stdoutText.sg_trimmed()
        let detail = err.isEmpty ? out : err
        if detail.isEmpty {
            return "git \(command) 执行失败(退出码 \(exitCode))"
        }
        return "\(detail)\n\n[git \(command),退出码 \(exitCode)]"
    }
}

/// git 子进程封装。
///
/// 统一注入的参数与环境:
/// - `-c core.quotepath=false`:中文/特殊字符路径原样输出,不做 C 风格转义
/// - `-c color.ui=false`:禁用颜色与 ANSI 转义
/// - `GIT_OPTIONAL_LOCKS=0`:只读命令不抢 index 锁
/// - `GIT_TERMINAL_PROMPT=0`:凭据缺失时快速失败而不是挂起等待输入
public enum Git {
    /// 系统 git(避免 PATH 环境差异)。
    public static let binaryPath = "/usr/bin/git"

    /// 执行 git 命令并返回 stdout 文本。
    /// - Parameters:
    ///   - args: git 子命令与参数(不含 git 本身)
    ///   - cwd: 工作目录(通常为仓库路径,内部通过 `-C` 传入)
    ///   - extraEnv: 追加的环境变量
    ///   - allowedExitCodes: 视为成功的退出码集合(如 `diff --no-index` 差异时返回 1)
    @discardableResult
    public static func run(
        _ args: [String],
        cwd: String? = nil,
        extraEnv: [String: String] = [:],
        allowedExitCodes: Set<Int32> = [0]
    ) throws -> String {
        var arguments = ["-c", "core.quotepath=false", "-c", "color.ui=false"]
        if let cwd {
            arguments += ["-C", cwd]
        }
        arguments += args

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["GIT_TERMINAL_PROMPT"] = "0"
        for (key, value) in extraEnv {
            env[key] = value
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw GitError(
                command: args.first ?? "",
                exitCode: -1,
                stderrText: "无法启动 git 进程:\(error.localizedDescription)",
                stdoutText: ""
            )
        }

        // 并发读取两路输出,避免管道缓冲区(64KB)写满导致死锁
        let group = DispatchGroup()
        let lock = NSLock()
        final class Box { var data = Data() }
        let stdoutBox = Box()
        let stderrBox = Box()

        func readAsync(_ handle: FileHandle, into box: Box) {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let chunk = handle.readDataToEndOfFile()
                lock.lock()
                box.data.append(chunk)
                lock.unlock()
                group.leave()
            }
        }
        readAsync(stdoutPipe.fileHandleForReading, into: stdoutBox)
        readAsync(stderrPipe.fileHandleForReading, into: stderrBox)
        group.wait()
        process.waitUntilExit()

        let stdoutText = String(decoding: stdoutBox.data, as: UTF8.self)
        let stderrText = String(decoding: stderrBox.data, as: UTF8.self)

        guard allowedExitCodes.contains(process.terminationStatus) else {
            throw GitError(
                command: args.first ?? "",
                exitCode: process.terminationStatus,
                stderrText: stderrText,
                stdoutText: stdoutText
            )
        }
        return stdoutText
    }

    /// 执行 git 命令,返回按行拆分的结果(已去除空行与行尾空白)。
    public static func runLines(_ args: [String], cwd: String? = nil) throws -> [String] {
        let raw = try run(args, cwd: cwd)
        return raw
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

extension String {
    /// 去除首尾空白与换行。
    public func sg_trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
