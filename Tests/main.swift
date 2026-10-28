// 测试入口:新增测试函数后在下方登记即可。
// (swiftc 多文件编译仅允许 main.swift 含顶层代码,故采用显式登记。)

print("GitCore 单元测试")
print("")

// 基础
MiniTest.run("GitCore 模块可加载且版本正确") {
    try assertEq(GitCore.moduleVersion, "0.1.0", "moduleVersion")
}

// status 解析
MiniTest.run("status:基本解析(暂存/未暂存/未跟踪)") { try testStatusBasicParsing() }
MiniTest.run("status:中文与空格路径") { try testStatusChinesePath() }
MiniTest.run("status:重命名条目") { try testStatusRenameParsing() }
MiniTest.run("status:空仓库") { try testStatusEmptyRepo() }
MiniTest.run("status:分离头指针") { try testStatusDetachedHead() }
MiniTest.run("status:ahead/behind") { try testStatusAheadBehind() }

// history / refs
MiniTest.run("history:线性历史") { try testHistoryLinear() }
MiniTest.run("history:引用装饰与标签") { try testHistoryRefsAndTags() }
MiniTest.run("history:合并与泳道") { try testHistoryMergeAndGraph() }
MiniTest.run("history:多行提交信息") { try testHistoryMultiLineMessage() }

// diff 解析
MiniTest.run("diff:工作区修改") { try testDiffWorktreeModified() }
MiniTest.run("diff:暂存新增文件") { try testDiffStagedNewFile() }
MiniTest.run("diff:暂存重命名") { try testDiffStagedRename() }
MiniTest.run("diff:删除文件") { try testDiffDeletedFile() }
MiniTest.run("diff:二进制文件") { try testDiffBinary() }
MiniTest.run("diff:根提交与子提交") { try testDiffCommitRootAndChild() }
MiniTest.run("diff:变更文件摘要(name-status+numstat)") { try testDiffCommitChangesSummary() }
MiniTest.run("diff:未跟踪文件内容") { try testDiffUntrackedFile() }
MiniTest.run("diff:路径过滤") { try testDiffPathFilter() }

// refs / remotes / stash
MiniTest.run("branches+remotes:本地远程与上游") { try testBranchesAndRemotes() }
MiniTest.run("stash:保存/弹出/删除") { try testStashLifecycle() }

// 写操作
MiniTest.run("工作副本:暂存/取消/提交/放弃/清理") { try testStageUnstageCommitDiscard() }

// 图算法(纯单元)
MiniTest.run("graph:线性") { try testGraphLinear() }
MiniTest.run("graph:合并") { try testGraphMerge() }
MiniTest.run("graph:侧分支汇入主线") { try testGraphSideBranchConvergesIntoMainline() }
MiniTest.run("graph:章鱼合并") { try testGraphOctopusMerge() }
MiniTest.run("graph:孤儿根") { try testGraphOrphanRoots() }

// 错误路径
MiniTest.run("open:非 git 目录抛错") { try testOpenInvalidRepoFails() }

// 远端流程(本地裸仓库作为远端)
MiniTest.run("fetch/pull:远端同步") { try testFetchAndPull() }
MiniTest.run("push:推送与上游设置") { try testPushFlow() }
MiniTest.run("push:force-with-lease") { try testPushForceWithLease() }
MiniTest.run("merge:冲突与终止") { try testMergeConflictAndAbort() }
MiniTest.run("checkout:远程分支建跟踪分支") { try testCheckoutRemoteBranch() }
MiniTest.run("branch:删除/强删/重命名") { try testBranchDeleteRenameForce() }

// 更新机制(M6)
MiniTest.run("update:版本比较") { try testVersionCompare() }
MiniTest.run("update:Release 解析") { try testReleaseParsing() }
MiniTest.run("update:自动检查频率") { try testShouldAutoCheckFrequency() }
MiniTest.run("update:版本号格式") { try testAppVersionFormat() }

// UI 状态机集成测试(M6 之后新增:驱动真实 RepoModel 走完整流程)
await MiniTest.runAsync("model:打开仓库与刷新") { try await testModelOpenRepoAndRefresh() }
await MiniTest.runAsync("model:暂存与提交") { try await testModelStageAndCommit() }
await MiniTest.runAsync("model:选择文件与差异加载") { try await testModelSelectFileAndLoadDiff() }
await MiniTest.runAsync("model:历史详情与文件差异") { try await testModelHistoryDetailAndFileDiff() }
await MiniTest.runAsync("model:分支操作(建/切/改名)") { try await testModelBranchOperations() }
await MiniTest.runAsync("model:贮藏流程") { try await testModelStashFlow() }
await MiniTest.runAsync("model:空提交被拒绝") { try await testModelEmptyCommitIsRejected() }
await MiniTest.runAsync("model:轮询不阻塞界面") { try await testModelPollingDoesNotBlockUI() }
MiniTest.run("update:配置持久化") { try testModelUpdateSettingsPersistence() }
MiniTest.run("update:LRU 缓存淘汰") { try testModelDiffLRUCacheEviction() }

// 评审修复回归测试
await MiniTest.runAsync("regression:切换仓库重新加载") { try await testRegressionSwitchRepositoryReloadsState() }
await MiniTest.runAsync("regression:切换范围重载历史") { try await testRegressionHistoryScopeReloadsOnSectionChange() }
await MiniTest.runAsync("regression:放弃修改保留已暂存") { try await testRegressionDiscardKeepsStagedContent() }
await MiniTest.runAsync("regression:合并进行中状态缓存") { try await testRegressionMergeInProgressCached() }
await MiniTest.runAsync("regression:加载更多的显示条件") { try await testRegressionHasMoreHistory() }

MiniTest.finish()
