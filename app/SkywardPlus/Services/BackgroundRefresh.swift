#if os(iOS)
import BackgroundTasks
import Foundation

/// Lets iOS wake the app now and then to check Skyward and alert about new
/// grades. iOS decides when (usually every 15 minutes to a few hours, more often
/// for apps opened often); it never runs after the app is swiped away.
enum BackgroundRefresh {
    static let identifier = "com.skywardplus.app.refresh"

    /// Must run before the app finishes launching.
    @MainActor static func register(model: AppModel) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            MainActor.assumeIsolated { run(task, model: model) }
        }
    }

    @MainActor static func schedule(model: AppModel) {
        guard model.settings.backgroundSync, model.profiles.contains(where: { !$0.isDemo }) else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(max(15, Double(model.settings.syncMinutes)) * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor private static func run(_ task: BGAppRefreshTask, model: AppModel) {
        schedule(model: model)
        let work = Task { @MainActor in
            await model.backgroundCheck()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
#endif
