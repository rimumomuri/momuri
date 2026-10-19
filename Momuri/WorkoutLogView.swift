import SwiftUI
import SwiftData

/// 부위 기록 하나에 종목·세트·무게를 적는 화면
struct WorkoutLogView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let log: RoutineLog

    @State private var customExercise = ""
    @State private var confirmingRemove = false
    @State private var removing = false

    /// 부위·종목 이름은 저장 값(한국어). 화면에는 localizedValue 로 보여 준다.
    private static let presets = StoredValue.exercises

    private var routine: Routine? { log.routine }
    private var exercises: [String] { log.exercises }

    private var suggestions: [String] {
        let used = routine?.usedExercises(for: log.part) ?? []
        let preset = Self.presets[log.part ?? ""] ?? []
        var seen = Set(exercises)
        return (used + preset).filter { seen.insert($0).inserted }
    }

    private var title: String {
        let date = log.date.formatted(.dateTime.month().day().weekday(.abbreviated).locale(.app))
        return "\(log.part?.localizedValue ?? String(localized: "운동")) · \(date)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if exercises.isEmpty {
                        Text("아래에서 종목을 고르면 세트를 적을 수 있어요")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(exercises, id: \.self) { exercise in
                        exerciseCard(exercise)
                    }
                    addExerciseSection
                    Button("이 부위 기록 취소", role: .destructive) { confirmingRemove = true }
                        .font(.subheadline)
                        .padding(.top, 8)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("완료") { save(); dismiss() } }
            }
            .confirmationDialog("이 부위 기록과 세트를 모두 지울까요?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("지우기", role: .destructive) {
                    removing = true
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        RoutineActions.removeLog(log, in: context)
                    }
                }
            }
        }
        .tint(.primary)
        .onDisappear { if !removing { save() } }
    }

    private func exerciseCard(_ exercise: String) -> some View {
        let sets = log.sortedSets.filter { $0.exercise == exercise }
        let previous = routine?.previousSets(of: exercise, before: log.date) ?? []
        let best = routine?.bestSet(of: exercise)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.localizedValue).font(.headline)
                Spacer()
                if let best, best.weight > 0 {
                    Text("최고 \(best.summary)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let last = previous.last {
                Text("지난번 \(last.summary) · \(previous.count)세트")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                SetRow(set: set, index: index + 1) { delete(set) }
            }
            Button {
                addSet(exercise)
            } label: {
                Label("세트 추가", systemImage: "plus").font(.subheadline)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.15)))
    }

    private var addExerciseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("종목 추가").font(.caption).foregroundStyle(.secondary)
            if !suggestions.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                    ForEach(suggestions, id: \.self) { name in
                        Button { addExercise(name) } label: {
                            Text(name.localizedValue)
                                .font(.footnote)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                TextField("직접 입력", text: $customExercise).onSubmit(addCustom)
                Button("추가", action: addCustom)
                    .disabled(customExercise.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .font(.subheadline)
        }
    }

    // MARK: - 편집

    private var nextOrder: Int { (log.sets ?? []).map(\.order).max().map { $0 + 1 } ?? 0 }

    private func addExercise(_ name: String) {
        // 지난번 첫 세트 값으로 미리 채운다
        let first = routine?.previousSets(of: name, before: log.date).first
        insert(WorkoutSet(exercise: name, weight: first?.weight ?? 0, reps: first?.reps ?? 10, order: nextOrder))
    }

    private func addCustom() {
        let name = customExercise.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        addExercise(name)
        customExercise = ""
    }

    private func addSet(_ exercise: String) {
        let last = log.sortedSets.last { $0.exercise == exercise }
        insert(WorkoutSet(exercise: exercise, weight: last?.weight ?? 0, reps: last?.reps ?? 10, order: nextOrder))
    }

    private func insert(_ set: WorkoutSet) {
        context.insert(set)
        log.sets?.append(set)
    }

    private func delete(_ set: WorkoutSet) {
        log.sets?.removeAll { $0.id == set.id }
        context.delete(set)
    }

    private func save() {
        try? context.save()
    }
}

private struct SetRow: View {
    @Bindable var set: WorkoutSet
    let index: Int
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index)")
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
            field { TextField("0", value: $set.weight, format: .number).keyboardType(.decimalPad) }
            Text("kg").foregroundStyle(.secondary)
            Text("×").foregroundStyle(.tertiary)
            field { TextField("0", value: $set.reps, format: .number).keyboardType(.numberPad) }
            Text("회").foregroundStyle(.secondary)
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary).frame(width: 28, height: 28)
            }
            .accessibilityLabel("\(index)세트 삭제")
        }
        .font(.body.monospacedDigit())
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .multilineTextAlignment(.center)
            .frame(width: 64)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}
