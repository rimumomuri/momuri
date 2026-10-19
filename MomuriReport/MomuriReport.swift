import DeviceActivity
import ExtensionKit
import SwiftUI

extension DeviceActivityReport.Context {
    static let totalActivity = Self("Total Activity")
}

/// 오늘 사용 시간을 앱 화면에 그려주는 확장 (앱 본체는 사용 시간을 직접 읽을 수 없다)
@main
struct MomuriReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TotalActivityReport { TotalActivityView(total: $0) }
    }
}

struct TotalActivityReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .totalActivity
    let content: (TimeInterval) -> TotalActivityView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TimeInterval {
        var total: TimeInterval = 0
        for await device in data {
            for await segment in device.activitySegments {
                total += segment.totalActivityDuration
            }
        }
        return total
    }
}

struct TotalActivityView: View {
    let total: TimeInterval

    var body: some View {
        let goal = ScreenTimeShared.goalMinutes
        let used = Int(total / 60)
        let ratio = min(Double(used) / Double(max(goal, 1)), 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("오늘 \(ScreenTimeShared.label(minutes: used))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(used >= goal ? Color.red : used * 10 >= goal * 8 ? Color.orange : Color.primary)
                Spacer()
                Text("목표 \(ScreenTimeShared.label(minutes: goal))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(used >= goal ? Color.red : Color.primary).frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 4)
        }
    }
}
