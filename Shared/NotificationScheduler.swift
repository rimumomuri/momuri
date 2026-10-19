import Foundation
import SwiftData
import UserNotifications

/// 로컬 알림은 64개 제한이 있어 앞으로 며칠치만 굴려가며 다시 예약한다
enum NotificationScheduler {
    static let nagHour = 21

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func reschedule(context: ModelContext) {
        let routines = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        buildRequests(routines, now: .now).forEach { center.add($0) }
    }

    static func buildRequests(_ routines: [Routine], now: Date) -> [UNNotificationRequest] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var items: [(fire: Date, id: String, title: String, body: String)] = []

        func at(_ day: Date, _ hour: Int, _ minute: Int) -> Date? {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        }

        for r in routines {
            let key = r.id.uuidString
            // 쉬는 날은 알리지 않는다 (아래 날짜별 반복에서 거른다)
            // 폰 사용 알림은 Screen Time 모니터 확장이 보낸다
            if r.category == .screen { continue }
            if r.category == .study {
                for offset in 0..<7 {
                    guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
                    if r.studyTogether, let t = at(day, r.studyStart / 60, r.studyStart % 60) {
                        items.append((t, "\(key)-\(offset)-together", r.displayName, String(localized: "같이 공부할 시간이에요 · \(r.studyTimeLabel)")))
                    }
                    guard !r.isSettled(on: day), let t = at(day, r.reminderHour, r.reminderMinute) else { continue }
                    let body = offset == 0
                        ? String(localized: "오늘 \(r.studyProgress(on: day)) · 목표까지 \(Routine.format(max(r.studyGoal - r.dayTotal(on: day), 0)))\(r.studyUnit.localizedValue) 남았어요")
                        : String(localized: "오늘 목표 \(Routine.format(r.studyGoal))\(r.studyUnit.localizedValue)")
                    items.append((t, "\(key)-\(offset)-goal", r.displayName, body + (r.examLabel.map { String(localized: " · 시험 \($0)") } ?? "")))
                }
                // 시험 30·7·1일 전 아침
                if let exam = r.examDate {
                    for before in [30, 7, 1] {
                        guard let day = cal.date(byAdding: .day, value: -before, to: cal.startOfDay(for: exam)),
                              let t = at(day, 9, 0) else { continue }
                        items.append((t, "\(key)-exam-\(before)", r.displayName, String(localized: "시험 \(before)일 전이에요")))
                    }
                }
                continue
            }
            if r.category == .diet {
                // 식단은 시간대의 시작·끝을 알린다
                for offset in 0..<7 {
                    guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
                    let open = Routine.timeLabel(r.windowStart)
                    let close = Routine.timeLabel(r.windowEnd)
                    if let t = at(day, r.windowStart / 60, r.windowStart % 60) {
                        items.append((t, "\(key)-\(offset)-open", r.displayName, String(localized: "식사 시간 시작 · \(close)까지")))
                    }
                    let before = r.windowEnd - 30
                    if before > r.windowStart, let t = at(day, before / 60, before % 60) {
                        items.append((t, "\(key)-\(offset)-soon", r.displayName, String(localized: "식사 종료 30분 전이에요")))
                    }
                    if let t = at(day, r.windowEnd / 60, r.windowEnd % 60) {
                        items.append((t, "\(key)-\(offset)-close", r.displayName, String(localized: "금식 시작 · 다음 식사 \(open)")))
                    }
                }
                continue
            }
            switch r.kind {
            case .daily:
                for offset in 0..<7 {
                    guard let day = cal.date(byAdding: .day, value: offset, to: today), !r.isRestDay(day) else { continue }
                    let count = r.logCount(on: day)
                    guard count < r.times.count else { continue }
                    for (i, minutes) in r.times.enumerated() where i >= count {
                        guard let t = at(day, minutes / 60, minutes % 60) else { continue }
                        let body = r.times.count > 1 ? String(localized: "\(i + 1)번째 시간이에요") : String(localized: "할 시간이에요")
                        items.append((t, "\(key)-\(offset)-\(i)", r.displayName, body))
                    }
                    if (r.times.last ?? 0) < nagHour * 60, let t = at(day, nagHour, 0) {
                        items.append((t, "\(key)-\(offset)-nag", r.displayName, String(localized: "아직 안 했어요")))
                    }
                }
            case .interval:
                guard let due = r.nextDue else { continue }
                if r.remindDaysBefore > 0,
                   let pre = cal.date(byAdding: .day, value: -r.remindDaysBefore, to: due),
                   let t = at(pre, r.reminderHour, r.reminderMinute) {
                    items.append((t, "\(key)-pre", r.displayName, String(localized: "\(r.remindDaysBefore)일 남았어요")))
                }
                let start = max(due, today)
                for offset in 0..<7 {
                    guard let day = cal.date(byAdding: .day, value: offset, to: start),
                          let t = at(day, r.reminderHour, r.reminderMinute) else { continue }
                    let late = cal.dateComponents([.day], from: r.dueEnd ?? due, to: day).day ?? 0
                    let body = late > 0 ? String(localized: "\(late)일 지났어요") : r.weekendOnly ? String(localized: "이번 주말에 할 차례예요") : String(localized: "오늘 할 차례예요")
                    items.append((t, "\(key)-due-\(offset)", r.displayName, body))
                }
            case .weekly:
                // 남은 날보다 남은 항목이 많아 빠듯할 때만 알린다
                let remaining = r.remainingParts(inWeekOf: today)
                guard !remaining.isEmpty,
                      let weekEnd = Routine.weekCalendar.dateInterval(of: .weekOfYear, for: today)?.end else { continue }
                let daysLeft = cal.dateComponents([.day], from: today, to: weekEnd).day ?? 0
                for offset in 0..<min(3, daysLeft) {
                    guard remaining.count >= daysLeft - offset,
                          let day = cal.date(byAdding: .day, value: offset, to: today),
                          !(offset == 0 && r.isDone(on: today)),
                          let t = at(day, r.reminderHour, r.reminderMinute) else { continue }
                    items.append((t, "\(key)-week-\(offset)", r.displayName, String(localized: "이번 주 남은 항목: \(remaining.map(\.localizedValue).joined(separator: ", "))")))
                }
            case .monthly:
                continue
            case .once:
                guard !r.isDone(on: r.eventDate) else { continue }
                let place = r.location.isEmpty ? "" : " · " + r.location
                if r.allDay {
                    if let t = at(r.eventDate, 9, 0) { items.append((t, "\(key)-once-day", r.displayName, String(localized: "오늘이에요") + place)) }
                    continue
                }
                for offset in r.remindOffsets {
                    let t = r.eventDate.addingTimeInterval(TimeInterval(-offset * 60))
                    let when = offset == 0 ? String(localized: "지금") : offset < 60 ? String(localized: "\(offset)분 후") : offset < 1440 ? String(localized: "\(offset / 60)시간 후") : String(localized: "내일 \(r.eventTimeLabel)")
                    items.append((t, "\(key)-once-\(offset)", r.displayName, when + place))
                }
            }
        }

        return items
            .filter { $0.fire > now }
            .sorted { $0.fire < $1.fire }
            .prefix(60)
            .map { item in
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: item.fire)
                return UNNotificationRequest(identifier: item.id, content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            }
    }
}
