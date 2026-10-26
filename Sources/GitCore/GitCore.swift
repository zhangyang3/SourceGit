/// GitCore — 纯逻辑层入口。
///
/// M0 仅提供模块占位标识;M1 起在此层实现:
/// git 子进程封装(`Git`)、数据模型(`Models`)、高层仓库 API
/// (`GitRepository`)、diff 解析(`DiffParser`)、提交图泳道算法(`GraphBuilder`)。
public enum GitCore {
    /// 模块版本,与产品版本(见 make-app.sh 的 APP_VERSION)独立维护。
    public static let moduleVersion = "0.1.0"
}
