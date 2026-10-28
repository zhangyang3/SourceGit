import Foundation

// MARK: - 极简测试工具(不依赖 XCTest / swift-testing)
// 说明:本机 CLT 不含 XCTest,测试与应用编译进同一模块,直接调用被测函数。

/// 断言失败时抛出的错误。
public struct TestFailure: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

public func assertTrue(
    _ condition: Bool,
    _ message: String = "",
    file: StaticString = #fileID,
    line: UInt = #line
) throws {
    guard condition else {
        throw TestFailure("\(message.isEmpty ? "断言失败" : message) @ \(file):\(line)")
    }
}

public func assertEq<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ label: String = "",
    file: StaticString = #fileID,
    line: UInt = #line
) throws {
    guard actual == expected else {
        let prefix = label.isEmpty ? "" : "\(label): "
        throw TestFailure("\(prefix)实际值 \(actual) ≠ 期望值 \(expected) @ \(file):\(line)")
    }
}

/// 断言指定代码会抛出错误。
public func assertThrows(
    _ message: String = "",
    file: StaticString = #fileID,
    line: UInt = #line,
    _ body: () throws -> Void
) throws {
    do {
        try body()
        throw TestFailure("\(message.isEmpty ? "期望抛出错误但没有" : message) @ \(file):\(line)")
    } catch let error as TestFailure where error.message.contains("期望抛出错误但没有") {
        throw error
    } catch {
        // 预期内抛出,通过
    }
}

/// 解包可选值,失败则抛错(XCTest 不可用时的替代)。
public func unwrap<T>(_ value: T?, _ message: String = "值为 nil") throws -> T {
    guard let value else { throw TestFailure(message) }
    return value
}

public enum MiniTest {
    public private(set) static var passed = 0
    public private(set) static var failed = 0

    /// 测试体在主 actor 上执行(便于直接驱动 @MainActor 的状态机)。
    @MainActor
    public static func run(_ name: String, _ body: @MainActor () throws -> Void) {
        do {
            try body()
            passed += 1
            print("  ✅ \(name)")
        } catch {
            failed += 1
            print("  ❌ \(name)")
            print("     \(error)")
        }
    }

    /// 异步测试体(用于驱动 await 的状态机方法)。
    @MainActor
    public static func runAsync(_ name: String, _ body: @MainActor () async throws -> Void) async {
        do {
            try await body()
            passed += 1
            print("  ✅ \(name)")
        } catch {
            failed += 1
            print("  ❌ \(name)")
            print("     \(error)")
        }
    }

    /// 等待条件成立(用于等待 fire-and-forget 的操作完成)。
    @MainActor
    public static func waitUntil(
        timeout: TimeInterval = 15,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        throw TestFailure("等待条件超时(\(timeout)s)")
    }

    public static func finish() -> Never {
        print("")
        print("结果:通过 \(passed),失败 \(failed)")
        exit(failed == 0 ? 0 : 1)
    }
}
