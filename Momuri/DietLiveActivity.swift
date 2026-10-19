import ActivityKit
import Foundation
import SwiftData

/// 식단 루틴의 Live Activity를 지금 상태에 맞춘다.
/// 앱이 백그라운드에서 돌 수 없으므로 앱을 열 때·저장할 때 갱신한다.
enum DietLiveActivity {
    @MainActor
    static func sync(context: ModelContext) {
        let routines = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
        let diet = routines.first { $0.category == .diet && $0.showLive }
        let activities = Activity<DietActivityAttributes>.activities

        guard let diet, ActivityAuthorizationInfo().areActivitiesEnabled else {
            Task { for a in activities { await a.end(nil, dismissalPolicy: .immediate) } }
            return
        }

        let phase = diet.dietPhase()
        let state = DietActivityAttributes.ContentState(eating: phase.eating, start: phase.start, end: phase.end)
        let content = ActivityContent(state: state, staleDate: phase.end)

        if let current = activities.first, current.attributes.name == diet.displayName, current.attributes.window == diet.windowLabel {
            Task { await current.update(content) }
        } else {
            Task {
                for a in activities { await a.end(nil, dismissalPolicy: .immediate) }
                _ = try? Activity.request(attributes: DietActivityAttributes(name: diet.displayName, window: diet.windowLabel), content: content)
            }
        }
    }
}
