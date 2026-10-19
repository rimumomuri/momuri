import AlarmKit
import CryptoKit
import Foundation
import SwiftData
import SwiftUI

struct MomuriAlarmMetadata: AlarmMetadata {
    var routineID: String
}

/// "알람으로 울리기"가 켜진 필수 루틴의 다음 알람들을 AlarmKit에 맞춘다.
/// 기록이 바뀔 때마다 통째로 다시 잡는다 (이미 한 일은 울리지 않게).
@MainActor
enum AlarmScheduler {
    static var isAuthorized: Bool { AlarmManager.shared.authorizationState == .authorized }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        if isAuthorized { return true }
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            NSLog("momuri alarm auth: \(String(describing: state))")
            return state == .authorized
        } catch {
            NSLog("momuri alarm auth error: \(String(describing: error))")
            return false
        }
    }

    static func startObserving() {
        NotificationCenter.default.addObserver(forName: RoutineActions.didChange, object: nil, queue: .main) { _ in
            Task { @MainActor in AlarmScheduler.reschedule(context: SharedStore.container.mainContext) }
        }
    }

    /// 재예약이 겹치면 알람이 두 번 잡히므로 한 줄로 세운다
    private static var running: Task<Void, Never>?

    static func reschedule(context: ModelContext) {
        guard isAuthorized else { return }
        let previous = running
        running = Task { @MainActor in
            await previous?.value
            let manager = AlarmManager.shared
            let routines = ((try? context.fetch(FetchDescriptor<Routine>())) ?? []).filter { $0.useAlarm && $0.isCritical }
            let plans = Array(upcoming(routines, now: .now).prefix(12))
            let wanted = Set(plans.map { alarmID($0.routine, $0.date) })
            // 계획에 없는 것만 지우고, 없는 것만 새로 잡는다 (같은 루틴·시각은 늘 같은 ID)
            let existing = (try? manager.alarms) ?? []
            for alarm in existing where !wanted.contains(alarm.id) { try? manager.cancel(id: alarm.id) }
            let have = Set(existing.map(\.id))
            for plan in plans where !have.contains(alarmID(plan.routine, plan.date)) {
                _ = try? await manager.schedule(id: alarmID(plan.routine, plan.date),
                                                configuration: configuration(for: plan.routine, at: plan.date))
            }
        }
    }

    private static func alarmID(_ routine: Routine, _ date: Date) -> UUID {
        let digest = Insecure.MD5.hash(data: Data("\(routine.id.uuidString)-\(Int(date.timeIntervalSince1970))".utf8))
        let b = Array(digest)
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    /// 앞으로 이틀 안에 아직 안 한 일의 알람 시각
    static func upcoming(_ routines: [Routine], now: Date) -> [(routine: Routine, date: Date)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var result: [(Routine, Date)] = []
        for r in routines where r.isSimpleCheck {
            for offset in 0..<2 {
                guard let day = cal.date(byAdding: .day, value: offset, to: today), !r.isSettled(on: day) else { continue }
                let minutes: [Int]
                switch r.kind {
                case .daily:
                    let done = r.category == .study ? 0 : r.logCount(on: day)
                    minutes = r.category == .study ? [r.reminderHour * 60 + r.reminderMinute] : Array(r.times.dropFirst(done))
                case .interval:
                    guard let due = r.nextDue, cal.isDate(due, inSameDayAs: day) || (offset == 0 && due < today) else { continue }
                    minutes = [r.reminderHour * 60 + r.reminderMinute]
                default:
                    continue
                }
                for m in minutes {
                    if let date = cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day), date > now {
                        result.append((r, date))
                    }
                }
            }
        }
        return result.sorted { $0.1 < $1.1 }
    }

    #if DEBUG
    /// 환경변수 MOMURI_ALARMTEST=1: 알람 켠 첫 루틴으로 1분 뒤 시험 알람
    static func scheduleTestIfRequested(context: ModelContext) async {
        guard DebugFlag.isOn("alarmTest"), await requestAuthorization(),
              let routine = ((try? context.fetch(FetchDescriptor<Routine>())) ?? []).first(where: { $0.useAlarm }) else { return }
        _ = try? await AlarmManager.shared.schedule(id: UUID(), configuration: configuration(for: routine, at: .now.addingTimeInterval(60)))
        NSLog("momuri test alarm scheduled for \(routine.name)")
    }
    #endif

    private static func configuration(for routine: Routine, at date: Date) -> AlarmManager.AlarmConfiguration<MomuriAlarmMetadata> {
        let done = AlarmButton(text: "완료", textColor: .black, systemImageName: "checkmark")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: "\(routine.displayName)", secondaryButton: done, secondaryButtonBehavior: .custom)
        } else {
            alert = AlarmPresentation.Alert(title: "\(routine.displayName)",
                                            stopButton: AlarmButton(text: "끄기", textColor: .white, systemImageName: "xmark"),
                                            secondaryButton: done, secondaryButtonBehavior: .custom)
        }
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
                                         metadata: MomuriAlarmMetadata(routineID: routine.id.uuidString),
                                         tintColor: .primary)
        return .alarm(schedule: .fixed(date), attributes: attributes,
                      secondaryIntent: CompleteFromAlarmIntent(routineID: routine.id.uuidString))
    }
}
