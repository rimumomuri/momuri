import BackgroundTasks
import Foundation
import SwiftData
import Observation
import UserNotifications

/// 공유 루틴의 내 기록 올리기와 상대 기록 받아오기
@MainActor
@Observable
final class ShareSync {
    static let shared = ShareSync()

    /// shareId → 멤버들 (나 포함). 앱을 다시 열어도 바로 보이도록 저장해 둔다.
    private(set) var members: [String: [ShareMember]] = [:]
    private var pushTask: Task<Void, Never>?

    private init() {
        if let data = UserDefaults.standard.data(forKey: "shareMembers"),
           let saved = try? JSONDecoder().decode([String: [ShareMember]].self, from: data) {
            members = saved
        }
        NotificationCenter.default.addObserver(forName: RoutineActions.didChange, object: nil, queue: .main) { _ in
            Task { @MainActor in ShareSync.shared.schedulePush() }
        }
    }

    /// 나를 뺀 멤버
    func others(of routine: Routine) -> [ShareMember] {
        guard let id = routine.shareId else { return [] }
        return (members[id] ?? []).filter { $0.id != ShareClient.me?.id }
    }

    func share(_ routine: Routine, context: ModelContext) async throws {
        let view = try await ShareClient.createShare(RoutineDefinition(routine))
        routine.shareId = view.id
        routine.shareCode = view.code
        routine.shareOwner = true
        try? context.save()
        try await push(routine)
    }

    func join(code: String, context: ModelContext) async throws -> Routine {
        let view = try await ShareClient.join(code: code)
        let all = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
        if let existing = all.first(where: { $0.shareId == view.id }) { return existing }
        let routine = Routine(name: view.routine.name, kind: .daily, sortOrder: all.count)
        view.routine.apply(to: routine)
        routine.shareId = view.id
        routine.shareCode = view.code
        routine.shareOwner = view.ownerId == ShareClient.me?.id
        context.insert(routine)
        RoutineActions.commit(context)
        store(view, name: routine.name)
        return routine
    }

    func leave(_ routine: Routine, context: ModelContext) async throws {
        guard let id = routine.shareId else { return }
        try await ShareClient.leave(id)
        members[id] = nil
        routine.shareId = nil
        routine.shareCode = nil
        routine.shareOwner = false
        try? context.save()
        save()
    }

    /// 앱을 열 때: 내 기록을 올리고 상대 기록을 받는다. 만든 사람이 바꾼 설정도 따라간다.
    func refreshAll(context: ModelContext) async {
        guard ShareClient.me != nil else { return }
        let shared = ((try? context.fetch(FetchDescriptor<Routine>())) ?? []).filter { $0.shareId != nil }
        var changed = false
        for routine in shared {
            let view: ShareView
            do {
                view = try await push(routine)
            } catch let error as ShareClient.ServerError where error.status == 404 {
                // 서버에서 사라진 공유(서버 초기화 등)는 연결을 풀어 다시 공유할 수 있게 한다
                if let id = routine.shareId { members[id] = nil }
                routine.shareId = nil
                routine.shareCode = nil
                routine.shareOwner = false
                changed = true
                continue
            } catch {
                continue
            }
            if routine.shareOwner {
                if view.routine != RoutineDefinition(routine), let id = routine.shareId {
                    _ = try? await ShareClient.updateRoutine(id, RoutineDefinition(routine))
                }
            } else if view.routine != RoutineDefinition(routine) {
                view.routine.apply(to: routine)
                changed = true
            }
        }
        if changed { RoutineActions.commit(context) }
    }

    func cheer(_ routine: Routine, member: ShareMember) async throws {
        guard let id = routine.shareId else { return }
        store(try await ShareClient.cheer(id, to: member.id), name: routine.name)
    }

    /// 공부 타이머를 켜고 끌 때 상대에게 알린다
    func setStudying(_ routine: Routine, since: Date?) async {
        guard let id = routine.shareId, let view = try? await ShareClient.setStudying(id, since: since) else { return }
        store(view, name: routine.name)
    }

    /// 공부 화면을 보는 동안 상대 상태를 다시 받아온다
    func reload(_ routine: Routine) async {
        guard let id = routine.shareId, let view = try? await ShareClient.fetch(id) else { return }
        store(view, name: routine.name)
    }

    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let shared = ((try? SharedStore.container.mainContext.fetch(FetchDescriptor<Routine>())) ?? []).filter { $0.shareId != nil }
            for routine in shared { _ = try? await push(routine) }
        }
    }

    @discardableResult
    private func push(_ routine: Routine) async throws -> ShareView {
        guard let id = routine.shareId else { throw ShareClient.ServerError(message: String(localized: "공유되지 않은 루틴이에요")) }
        let since = Calendar.current.date(byAdding: .day, value: -120, to: .now) ?? .now
        let recent = routine.activeLogs.filter { $0.date >= since }
        // 공부처럼 목표량이 있는 루틴은 "완료한 날"만 잔디로, 양은 progress로
        let doneDays = Set(recent.map { Calendar.current.startOfDay(for: $0.date) }).filter { routine.isDone(on: $0) }
        var progress: [String: Double] = [:]
        if routine.category == .study {
            for log in recent { progress[ShareClient.dayKey(log.date), default: 0] += log.value ?? 1 }
        }
        let view = try await ShareClient.pushDays(id, days: doneDays.map(ShareClient.dayKey).sorted(), progress: progress)
        store(view, name: routine.name)
        return view
    }

    /// 새 상태를 저장하면서 바뀐 점(상대가 공부 시작·오늘 완료·응원)을 알림으로 띄운다
    private func store(_ view: ShareView, name: String) {
        let before = members[view.id]
        members[view.id] = view.members
        save()
        if let before { notifyChanges(view, before: before, name: name) }
    }

    private func notifyChanges(_ view: ShareView, before: [ShareMember], name: String) {
        let me = ShareClient.me?.id
        let today = ShareClient.dayKey(.now)
        var messages: [(String, String)] = []
        for member in view.members where member.id != me {
            let old = before.first { $0.id == member.id }
            if member.studyingSince != nil && old?.studyingSince == nil {
                messages.append(("\(view.id)-study-\(member.id)", String(localized: "\(member.name)님이 \(name) 공부를 시작했어요")))
            }
            if member.days.contains(today) && !(old?.days.contains(today) ?? false) {
                messages.append(("\(view.id)-done-\(member.id)-\(today)", String(localized: "\(member.name)님이 오늘 \(name)을(를) 했어요")))
            }
        }
        var seen = Set(UserDefaults.standard.array(forKey: "seenCheers") as? [Int] ?? [])
        for cheer in view.cheers ?? [] where !seen.contains(cheer.id) {
            seen.insert(cheer.id)
            messages.append(("cheer-\(cheer.id)", String(localized: "\(cheer.fromName)님이 \(name) 응원을 보냈어요")))
        }
        UserDefaults.standard.set(Array(seen.suffix(200)), forKey: "seenCheers")
        for (id, body) in messages {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "같이 하기")
            content.body = body
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    // MARK: - 백그라운드 새로고침 (앱이 꺼져 있어도 가끔 상대 소식을 확인)

    static let refreshTaskID = "com.rymchoi.momuri.share-refresh"

    nonisolated static func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            scheduleBackgroundRefresh()
            let work = Task { @MainActor in
                let context = SharedStore.container.mainContext
                NotificationScheduler.reschedule(context: context)
                AlarmScheduler.reschedule(context: context)
                await ShareSync.shared.refreshAll(context: context)
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// iOS가 정하는 때에 다시 깨운다 (최소 15분 뒤)
    nonisolated static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(members), forKey: "shareMembers")
    }
}
