import Combine
import SwiftUI

// MARK: - @State兼容垫片
//
// 背景:macOS 15+ SDK 中 SwiftUI 的@State改为宏实现(SwiftUIMacros 插件),
// 而 CLT 不附带该插件,只有完整 Xcode 才有。本机仅有 CLT,因此:
// - 用 @StateObject(普通属性包装器,可用)持有 ObservableObject 盒子;
// - 盒子内 @Published 存值,保证跨渲染持久 + 视图自动刷新;
// - SGState 实现 DynamicProperty,SwiftUI 会递归驱动嵌套的 @StateObject。
//
// 语义与 SwiftUI 的State包装器一致:值按视图身份持久存储;修改触发视图刷新;
// $ 投影提供 Binding。注意:与State相同,不要在 init 中读取初始值。
//
// 规则:UI 层一律使用 @SGState,禁止@State(dev.sh 会做静态检查)。

@MainActor
final class StateBox<Value>: ObservableObject {
    @Published var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

@propertyWrapper
struct SGState<Value>: DynamicProperty {
    @StateObject private var box: StateBox<Value>

    init(wrappedValue value: @autoclosure @escaping () -> Value) {
        _box = StateObject(wrappedValue: StateBox(value()))
    }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    var projectedValue: Binding<Value> {
        $box.value
    }
}
