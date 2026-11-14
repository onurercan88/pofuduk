import Foundation
import UserNotifications
import PofudukCore

enum NotificationPermission: Equatable {
    case notDetermined, authorized, denied
}

/// Thin abstraction over UNUserNotificationCenter so planning logic is testable.
@MainActor
protocol NotificationScheduling: AnyObject {
    func permission() async -> NotificationPermission
    func requestAuthorization() async -> Bool
    /// Replaces all pending Pofuduk notifications with `planned`.
    func replacePending(with planned: [PlannedNotification], now: Date) async
}

@MainActor
final class UserNotificationService: NotificationScheduling {
    private let center = UNUserNotificationCenter.current()
    static let prefix = "pofuduk."

    func permission() async -> NotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        default: return .notDetermined
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func replacePending(with planned: [PlannedNotification], now: Date) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for n in planned {
            let content = UNMutableNotificationContent()
            content.title = n.title
            content.body = n.body
            content.sound = .default
            content.threadIdentifier = n.category.rawValue
            // Time-sensitive needs the entitlement; without it iOS delivers as .active.
            content.interruptionLevel = n.isTimeSensitive ? .timeSensitive : .active
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, n.fireDate.timeIntervalSince(now)), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: Self.prefix + n.id, content: content, trigger: trigger))
        }
    }
}

/// Glue between preferences, the planner and the system scheduler.
@MainActor
@Observable
final class NotificationCoordinator {
    private(set) var preferences: NotificationPreferences
    private(set) var permission: NotificationPermission = .notDetermined
    private(set) var lastPlanned: [PlannedNotification] = []

    @ObservationIgnored private let scheduler: NotificationScheduling
    @ObservationIgnored private let store: NotificationPreferenceStore
    @ObservationIgnored private let log: NotificationDeliveryLog
    @ObservationIgnored private let engine = RainNotificationEngine()
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var lastSnapshot: WeatherSnapshot?
    @ObservationIgnored private var lastWarnings: [OfficialWarning] = []

    init(scheduler: NotificationScheduling, store: NotificationPreferenceStore, log: NotificationDeliveryLog,
         now: @escaping () -> Date) {
        self.scheduler = scheduler
        self.store = store
        self.log = log
        self.now = now
        self.preferences = store.load()
    }

    func refreshPermission() async {
        permission = await scheduler.permission()
    }

    /// Turning notifications on asks for permission at that moment (never earlier).
    func setEnabled(_ enabled: Bool) async {
        if enabled {
            if await scheduler.permission() == .notDetermined { _ = await scheduler.requestAuthorization() }
            permission = await scheduler.permission()
            preferences.isEnabled = permission == .authorized
        } else {
            preferences.isEnabled = false
        }
        store.save(preferences)
        await replan()
    }

    func update(_ change: (inout NotificationPreferences) -> Void) async {
        change(&preferences)
        store.save(preferences)
        await replan()
    }

    /// Call after every fresh forecast (foreground load or background refresh).
    func refresh(snapshot: WeatherSnapshot, warnings: [OfficialWarning]) async {
        lastSnapshot = snapshot
        lastWarnings = warnings
        await replan()
    }

    private func replan() async {
        permission = await scheduler.permission()
        guard preferences.isEnabled, permission == .authorized, let snapshot = lastSnapshot else {
            lastPlanned = []
            await scheduler.replacePending(with: [], now: now())
            return
        }
        let current = now()
        log.prune(before: current.addingTimeInterval(-2 * 86_400))
        let planned = engine.plan(snapshot: snapshot, warnings: lastWarnings, preferences: preferences, log: log, now: current)
        await scheduler.replacePending(with: planned, now: current)
        planned.forEach { log.record($0.id, fireDate: $0.fireDate) }
        lastPlanned = planned
    }
}
