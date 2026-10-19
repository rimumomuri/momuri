import DeviceActivity
import Foundation
import UserNotifications

/// 오늘 사용 시간이 목표의 80%·100%에 닿으면 기록하고 알린다
final class ActivityMonitor: DeviceActivityMonitor {
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        let exceeded = event.rawValue == "limit"
        ScreenTimeShared.mark(exceeded ? .exceeded : .warning, on: .now)

        let goal = ScreenTimeShared.label(minutes: ScreenTimeShared.goalMinutes)
        let content = UNMutableNotificationContent()
        content.title = String(localized: "폰 사용")
        content.body = exceeded ? String(localized: "오늘 목표 \(goal)을 넘었어요") : String(localized: "오늘 목표 \(goal)의 80%를 썼어요")
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "screen-\(event.rawValue)", content: content, trigger: nil))
    }
}
