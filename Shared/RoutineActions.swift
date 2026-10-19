import Foundation
import SwiftData
import WidgetKit

enum RoutineActions {
    /// 기록이 바뀌면 알린다 (앱의 공유 동기화가 듣는다)
    static let didChange = Notification.Name("momuriRoutineDidChange")

    /// 그날 기록을 켜고 끈다. 주간형은 다음 추천 항목으로 기록한다.
    static func toggle(_ routine: Routine, on day: Date, in context: ModelContext) {
        let todays = logs(of: routine, on: day).filter { !$0.skipped }
        if routine.kind == .daily && todays.count < routine.times.count {
            // 하루 여러 번인 경우 다 채울 때까지 하나씩 더한다
            add(to: routine, on: day, part: nil, in: context)
        } else if !todays.isEmpty {
            todays.forEach { remove($0, from: routine, in: context) }
        } else if routine.kind == .weekly {
            guard let part = routine.remainingParts(inWeekOf: day).first ?? routine.parts.first else { return }
            add(to: routine, on: day, part: part, in: context)
        } else {
            add(to: routine, on: day, part: nil, in: context)
        }
        commit(context)
    }

    static func togglePart(_ routine: Routine, part: String, on day: Date, in context: ModelContext) {
        if let log = logs(of: routine, on: day).first(where: { $0.part == part }) {
            remove(log, from: routine, in: context)
        } else {
            add(to: routine, on: day, part: part, in: context)
        }
        commit(context)
    }

    /// 부위 기록을 만들고 돌려준다 (세트 입력 화면을 바로 열기 위해)
    @discardableResult
    static func addPart(_ routine: Routine, part: String, on day: Date, in context: ModelContext) -> RoutineLog {
        let log = add(to: routine, on: day, part: part, in: context)
        commit(context)
        return log
    }

    static func removeLog(_ log: RoutineLog, in context: ModelContext) {
        if let routine = log.routine {
            remove(log, from: routine, in: context)
        } else {
            context.delete(log)
        }
        commit(context)
    }

    /// "오늘은 쉬기" 켜고 끄기
    static func toggleSkip(_ routine: Routine, on day: Date, in context: ModelContext) {
        let cal = Calendar.current
        if let log = routine.logs?.first(where: { $0.skipped && cal.isDate($0.date, inSameDayAs: day) }) {
            remove(log, from: routine, in: context)
        } else {
            let log = RoutineLog(date: cal.startOfDay(for: day))
            log.skipped = true
            context.insert(log)
            routine.logs?.append(log)
        }
        commit(context)
    }

    static func addValue(_ routine: Routine, value: Double, on day: Date, in context: ModelContext) {
        let cal = Calendar.current
        let log = RoutineLog(date: cal.isDateInToday(day) ? .now : cal.startOfDay(for: day), value: value)
        context.insert(log)
        routine.logs?.append(log)
        commit(context)
    }

    /// 지운 건강 앱 기록 ID (다시 가져오지 않게)
    static var dismissedExternalIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "dismissedExternalIDs") ?? []) }
        set { UserDefaults.standard.set(Array(newValue.suffix(500)), forKey: "dismissedExternalIDs") }
    }

    static func clear(_ routine: Routine, on day: Date, in context: ModelContext) {
        let removed = logs(of: routine, on: day)
        dismissedExternalIDs.formUnion(removed.compactMap(\.externalID))
        removed.forEach { remove($0, from: routine, in: context) }
        commit(context)
    }

    /// 말·단축어로 "했다"고 할 때: 루틴 종류에 맞게 기록하고 결과 문장을 돌려준다
    @discardableResult
    static func quickLog(_ routine: Routine, amount: Double? = nil, part: String? = nil, on day: Date = .now, in context: ModelContext) -> String {
        if routine.kind == .weekly {
            let chosen = part.flatMap { p in routine.parts.first { $0.contains(p) || p.contains($0) } }
                ?? routine.remainingParts(inWeekOf: day).first ?? routine.parts.first ?? ""
            addPart(routine, part: chosen, on: day, in: context)
            return String(localized: "\(routine.displayName) \(chosen.localizedValue) 기록했어요. \(routine.listStatus(on: day))")
        }
        if routine.kind == .monthly || routine.category == .study {
            guard let amount else {
                return routine.kind == .monthly && routine.targetUnit == "회"
                    ? { addValue(routine, value: 1, on: day, in: context); return String(localized: "\(routine.displayName) 기록했어요. \(routine.listStatus(on: day))") }()
                    : String(localized: "\(routine.displayName)은 양을 같이 말해 주세요. 예: 5km, 20문제")
            }
            addValue(routine, value: amount, on: day, in: context)
            return String(localized: "\(routine.displayName) \(Routine.format(amount)) 기록했어요. 지금 \(routine.listStatus(on: day))")
        }
        if routine.isDone(on: day) { return String(localized: "\(routine.displayName)은 이미 기록돼 있어요.") }
        toggle(routine, on: day, in: context)
        return String(localized: "\(routine.displayName) 기록했어요. \(routine.listStatus(on: day))")
    }

    /// 저장 후 위젯과 알림을 최신 상태로 맞춘다
    static func commit(_ context: ModelContext) {
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
        NotificationScheduler.reschedule(context: context)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    private static func logs(of routine: Routine, on day: Date) -> [RoutineLog] {
        (routine.logs ?? []).filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    // 관계 배열을 직접 바꿔야 화면이 바로 갱신된다
    @discardableResult
    private static func add(to routine: Routine, on day: Date, part: String?, in context: ModelContext) -> RoutineLog {
        let cal = Calendar.current
        let log = RoutineLog(date: cal.isDateInToday(day) ? .now : cal.startOfDay(for: day), part: part)
        context.insert(log)
        routine.logs?.append(log)
        return log
    }

    private static func remove(_ log: RoutineLog, from routine: Routine, in context: ModelContext) {
        routine.logs?.removeAll { $0.id == log.id }
        context.delete(log)
    }
}
