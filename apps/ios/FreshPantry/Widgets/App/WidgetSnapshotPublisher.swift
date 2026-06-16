import Foundation
import SwiftData

/// **app 侧**小组件刷新入口:在主进程(内存充足)算好四类快照写进 App Group,
/// 再重载所有时间线。取代散落的裸 `WidgetRefreshCoordinator.reloadAll()` —— widget
/// 时间线进程因此不必自己打开 SwiftData(其内存预算约 30MB,开 13 模型容器会被
/// jetsam 杀,组件停在占位)。
enum WidgetSnapshotPublisher {
    /// 算 + 写 + 重载。读 store 在 app 进程,故安全。失败容忍(reader 各方法内部
    /// `try?`,异常退化为空快照)。
    static func publish(container: ModelContainer, householdID: String, now: Date = .now) async {
        let bundle = await WidgetDataReader(container: container).snapshotBundle(householdID: householdID, now: now)
        WidgetSnapshotStore.write(bundle)
        WidgetRefreshCoordinator.reloadAll()
    }
}
