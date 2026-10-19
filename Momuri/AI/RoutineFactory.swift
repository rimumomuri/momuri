import Foundation
import SwiftData

/// AI 채팅·단축어 등 화면 밖에서 루틴을 만들 때 쓰는 공용 생성기 (분류별 기본값은 만들기 화면과 같게)
@MainActor
enum RoutineFactory {
    struct Draft: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var category: RoutineCategory
        var intervalValue: Int?
        var intervalUnit: IntervalUnit?
        var time: (hour: Int, minute: Int)?
        var parts: [String] = []
        var goal: Double?
        var date: Date?
        var location: String = ""

        static func == (a: Draft, b: Draft) -> Bool { a.id == b.id }

        /// 확인 카드에 보여줄 요약
        var summary: [String] {
            var lines: [String] = [category.title]
            switch category {
            case .appointment:
                if let date {
                    let c = Calendar.current.dateComponents([.month, .day], from: date)
                    let m = c.month ?? 0, d = c.day ?? 0
                    lines.append(time.map { String(localized: "\(m)월 \(d)일 \(String(format: "%02d:%02d", $0.hour, $0.minute))") }
                        ?? String(localized: "\(m)월 \(d)일 하루 종일"))
                }
                if !location.isEmpty { lines.append(location) }
            case .care, .pet:
                lines.append(String(localized: "\(intervalValue ?? 1)\((intervalUnit ?? .month).label)마다"))
            case .other:
                lines.append(intervalValue.map { String(localized: "\($0)\((intervalUnit ?? .month).label)마다") } ?? String(localized: "매일"))
            case .gym:
                // 부위는 한국어로 저장되는 값이라 보여 줄 때만 번역
                let shown = (parts.isEmpty ? StoredValue.defaultParts : parts).map(\.localizedValue).joined(separator: " · ")
                lines.append(String(localized: "이번 주 \(shown)"))
            case .study:
                lines.append(String(localized: "하루 \(Routine.format(goal ?? 30))문제"))
                if let date {
                    let c = Calendar.current.dateComponents([.month, .day], from: date)
                    lines.append(String(localized: "시험 \(c.month ?? 0)월 \(c.day ?? 0)일"))
                }
            case .cardio:
                lines.append(String(localized: "한 달 \(Routine.format(goal ?? 30))km"))
            default:
                lines.append(String(localized: "매일"))
            }
            if category != .appointment, let time { lines.append(String(localized: "알림 \(String(format: "%02d:%02d", time.hour, time.minute))")) }
            return lines
        }
    }

    @discardableResult
    static func create(_ d: Draft, in context: ModelContext) -> Routine {
        let count = (try? context.fetchCount(FetchDescriptor<Routine>())) ?? 0
        let kind: RoutineKind = d.category.fixedKind ?? (d.intervalValue != nil ? .interval : .daily)
        let r = Routine(name: d.name, kind: kind, sortOrder: count)
        r.category = d.category
        if let t = d.time {
            r.reminderHour = t.hour
            r.reminderMinute = t.minute
        }
        switch d.category {
        case .appointment:
            let cal = Calendar.current
            let day = cal.startOfDay(for: d.date ?? .now)
            if let t = d.time {
                r.eventDate = cal.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: day) ?? day
            } else {
                r.eventDate = day
                r.allDay = true
            }
            r.location = d.location
            r.showInWidget = false
        case .medicine:
            r.isCritical = true
        case .gym:
            r.parts = d.parts.isEmpty ? StoredValue.defaultParts : d.parts
            if d.time == nil { r.reminderHour = 19 }
        case .cardio:
            r.targetUnit = "km"
            r.targetValue = d.goal ?? 30
            r.autoHealth = HealthSync.isAvailable
        case .study:
            r.studyGoal = d.goal ?? 30
            r.examDate = d.date.map { Calendar.current.startOfDay(for: $0) }
            if d.time == nil { r.reminderHour = 22 }
        case .care, .pet, .other:
            r.intervalValue = d.intervalValue ?? 1
            r.intervalUnit = d.intervalUnit ?? .month
            r.weekendOnly = d.category == .care
        default:
            break
        }
        context.insert(r)
        RoutineActions.commit(context)
        return r
    }
}
