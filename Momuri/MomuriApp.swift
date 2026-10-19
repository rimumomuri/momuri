import SwiftUI
import SwiftData
import WidgetKit

import UserNotifications

/// 앱을 보고 있을 때도 알림 배너를 띄운다 (같이 하기 소식 등)
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@main
struct MomuriApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AlarmScheduler.startObserving()
        ShareSync.registerBackgroundRefresh()
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, Locale.app)
                #if DEBUG
                .onAppear {
                    DebugSeed.runIfRequested()
                    DebugRestore.runIfRequested()
                }
                #endif
        }
        .modelContainer(SharedStore.container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { ShareSync.scheduleBackgroundRefresh() }
            guard phase == .active else { return }
            NotificationScheduler.reschedule(context: SharedStore.container.mainContext)
            DietLiveActivity.sync(context: SharedStore.container.mainContext)
            AlarmScheduler.reschedule(context: SharedStore.container.mainContext)
            Backup.autoBackupIfNeeded(context: SharedStore.container.mainContext)
            ScreenTimeManager.syncLogs(context: SharedStore.container.mainContext)
            Task {
                #if DEBUG
                await AlarmScheduler.scheduleTestIfRequested(context: SharedStore.container.mainContext)
                await HealthSeed.runIfRequested()
                #endif
                await HealthSync.sync(context: SharedStore.container.mainContext)
                await ShareSync.shared.refreshAll(context: SharedStore.container.mainContext)
            }
            WidgetCenter.shared.reloadAllTimelines()
            // Siri 문장에 루틴 이름이 들어가도록 최신 목록을 알린다
            MomuriShortcuts.updateAppShortcutParameters()
        }
    }
}
