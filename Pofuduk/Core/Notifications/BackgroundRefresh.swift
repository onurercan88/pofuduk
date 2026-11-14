import BackgroundTasks
import Foundation

/// Best-effort background forecast refresh (BGAppRefreshTask). iOS decides if and when it runs;
/// nothing here guarantees a notification at an exact time. Reliable delivery needs the optional
/// backend + APNs (see NOTIFICATIONS.md).
enum BackgroundRefresh {
    static let identifier = "com.pofuduk.app.refresh"

    /// Must be called before the app finishes launching.
    static func register(handler: @escaping @MainActor () async -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            schedule()
            let work = Task { @MainActor in
                await handler()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
