import Foundation
import ActivityKit

/// 식단 루틴의 지금 상태: 식사 시간이거나 금식 중
struct DietPhase: Equatable {
    let eating: Bool
    let start: Date
    let end: Date

    var title: String { eating ? String(localized: "식사 시간") : String(localized: "금식 중") }
}

extension Routine {
    func dietPhase(at now: Date = .now) -> DietPhase {
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        func at(_ dayOffset: Int, _ minutes: Int) -> Date {
            let d = cal.date(byAdding: .day, value: dayOffset, to: day) ?? day
            return cal.date(byAdding: .minute, value: minutes, to: d) ?? d
        }
        let open = at(0, windowStart)
        let close = at(0, windowEnd)
        if now < open { return DietPhase(eating: false, start: at(-1, windowEnd), end: open) }
        if now < close { return DietPhase(eating: true, start: open, end: close) }
        return DietPhase(eating: false, start: close, end: at(1, windowStart))
    }

    var windowLabel: String {
        Routine.timeLabel(windowStart) + "–" + Routine.timeLabel(windowEnd)
    }

    var dietStatus: String {
        let phase = dietPhase()
        let until = Routine.timeLabel(phase.eating ? windowEnd : windowStart)
        return String(localized: "\(phase.title) · \(until)까지")
    }
}

struct DietActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var eating: Bool
        var start: Date
        var end: Date
    }

    var name: String
    var window: String
}
