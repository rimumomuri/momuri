import SwiftUI
import SwiftData

/// 자격증 공부: 오늘 쌓기, 공부 타이머, 같이 공부하는 사람 보기
struct StudyLogView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let routine: Routine
    let day: Date

    @State private var custom = ""
    @State private var cheered: Set<String> = []
    @FocusState private var customFocused: Bool

    private var sync: ShareSync { .shared }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var quickAmounts: [Double] { routine.studyUnit == "분" ? [10, 30, 60] : [1, 5, 10, 20] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    progressCard
                    addSection
                    if isToday { timerCard }
                    if routine.shareId != nil { togetherSection }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(routine.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
        .tint(.primary)
        // 보는 동안 15초마다 상대 상태를 다시 받는다
        .task {
            guard routine.shareId != nil else { return }
            while !Task.isCancelled {
                await sync.reload(routine)
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private var progressCard: some View {
        let total = routine.dayTotal(on: day)
        let ratio = min(total / max(routine.studyGoal, 1), 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(Routine.format(total)).font(.system(size: 44, weight: .semibold).monospacedDigit())
                Text("/ \(Routine.format(routine.studyGoal))\(routine.studyUnit.localizedValue)").font(.title3).foregroundStyle(.secondary)
                Spacer()
                if let exam = routine.examLabel {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("시험").font(.caption).foregroundStyle(.secondary)
                        Text(exam).font(.title3.weight(.semibold).monospacedDigit())
                    }
                }
            }
            ProgressView(value: ratio).tint(.primary)
            Text(total >= routine.studyGoal ? "오늘 목표를 채웠어요"
                 : "목표까지 \(Routine.format(routine.studyGoal - total))\(routine.studyUnit.localizedValue)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isToday ? String(localized: "더하기") : String(localized: "\(dayTitle)에 더하기")).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(quickAmounts, id: \.self) { amount in
                    Button { add(amount) } label: {
                        Text("+\(Routine.format(amount))")
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                TextField("직접 입력", text: $custom)
                    .keyboardType(.decimalPad)
                    .focused($customFocused)
                Text(routine.studyUnit.localizedValue).foregroundStyle(.secondary)
                Button("더하기") {
                    if let value = Double(custom.replacingOccurrences(of: ",", with: ".")), value > 0 { add(value) }
                    custom = ""
                    customFocused = false
                }
                .disabled(Double(custom) == nil)
            }
            .font(.subheadline)
            if routine.dayTotal(on: day) > 0 {
                Button("이 날 기록 지우기", role: .destructive) { RoutineActions.clear(routine, on: day, in: context) }
                    .font(.caption)
                    .padding(.top, 4)
            }
        }
    }

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let since = routine.studyingSince {
                HStack(alignment: .firstTextBaseline) {
                    Text("공부 중").font(.headline)
                    Spacer()
                    Text(since, style: .timer).font(.title2.monospacedDigit())
                }
                Button { Task { await stopTimer(since) } } label: {
                    Text(routine.studyUnit == "분" ? "끝내고 기록하기" : "끝내기")
                        .font(.headline)
                        .foregroundStyle(Color(.systemBackground))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.primary))
                }
            } else {
                Button { Task { await startTimer() } } label: {
                    Label("공부 시작", systemImage: "timer")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .contentShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.3)))
                }
                .buttonStyle(.plain)
                Text(routine.studyUnit == "분"
                     ? "끝내면 공부한 시간이 자동으로 더해져요"
                     : routine.shareId != nil ? "켜 두면 같이 공부하는 사람에게 '공부 중'으로 보여요" : "공부한 시간을 재요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
    }

    private var togetherSection: some View {
        let others = sync.others(of: routine)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("같이 공부").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if routine.studyTogether {
                    Text(routine.isStudyTime() ? String(localized: "지금 같이 공부할 시간이에요") : routine.studyTimeLabel)
                        .font(.caption.weight(routine.isStudyTime() ? .semibold : .regular))
                        .foregroundStyle(routine.isStudyTime() ? .primary : .secondary)
                }
            }
            if others.isEmpty {
                Text("아직 참여한 사람이 없어요. 루틴 설정에서 초대 코드를 보내요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(others) { member in
                let amount = member.progress(on: day)
                HStack {
                    Circle()
                        .fill(member.studyingSince != nil ? Color.primary : Color.primary.opacity(0.15))
                        .frame(width: 8, height: 8)
                    Text(member.name)
                    Spacer()
                    if let since = member.studyingSince, isToday {
                        Text("공부 중 · ").foregroundStyle(.secondary)
                        Text(since, style: .timer).monospacedDigit()
                    } else {
                        Text("\(Routine.format(amount))/\(Routine.format(routine.studyGoal))\(routine.studyUnit.localizedValue)")
                            .monospacedDigit()
                            .foregroundStyle(amount >= routine.studyGoal ? .primary : .secondary)
                    }
                    CheerButton(sent: cheered.contains(member.id)) {
                        try? await sync.cheer(routine, member: member)
                        cheered.insert(member.id)
                    }
                }
                .font(.subheadline)
                .padding(.vertical, 6)
            }
        }
    }

    private var dayTitle: String {
        let c = Calendar.current.dateComponents([.month, .day], from: day)
        return String(localized: "\(c.month ?? 0)월 \(c.day ?? 0)일")
    }

    private func add(_ amount: Double) {
        RoutineActions.addValue(routine, value: amount, on: day, in: context)
    }

    private func startTimer() async {
        let now = Date.now
        routine.studyingSince = now
        try? context.save()
        await sync.setStudying(routine, since: now)
    }

    private func stopTimer(_ since: Date) async {
        routine.studyingSince = nil
        let minutes = (Date.now.timeIntervalSince(since) / 60).rounded()
        if routine.studyUnit == "분" && minutes >= 1 {
            add(minutes)
        } else {
            try? context.save()
        }
        await sync.setStudying(routine, since: nil)
    }
}

/// 상대에게 응원 보내기
struct CheerButton: View {
    let sent: Bool
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: sent ? "hands.clap.fill" : "hands.clap")
                .font(.subheadline)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(sent)
        .accessibilityLabel(sent ? "응원 보냄" : "응원 보내기")
    }
}
