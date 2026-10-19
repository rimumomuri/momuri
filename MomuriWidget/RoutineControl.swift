import AppIntents
import SwiftUI
import WidgetKit

/// 제어 센터·잠금화면 버튼: 고른 루틴을 한 번에 기록
struct RoutineControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "MomuriRoutineControl", intent: SelectRoutineControlIntent.self) { config in
            ControlWidgetButton(action: config.logIntent) {
                Label(config.routine?.name ?? String(localized: "루틴 고르기"), systemImage: config.routine?.symbol ?? "checkmark.circle")
            }
        }
        .displayName("momuri 기록")
        .description("누르면 고른 루틴을 바로 기록해요.")
    }
}

struct SelectRoutineControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "기록할 루틴"

    @Parameter(title: "루틴")
    var routine: RoutineEntity?

    var logIntent: LogRoutineIntent {
        var intent = LogRoutineIntent()
        if let routine { intent = LogRoutineIntent(routine: routine) }
        return intent
    }
}
