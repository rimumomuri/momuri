import SwiftUI

/// 루틴 상세: 3주 잔디, 같이 하는 사람, 기록, 공유. 수정은 오른쪽 위.
struct RoutineDetailView: View {
    @Environment(\.modelContext) private var context
    let routine: Routine
    let onEdit: () -> Void
    @State private var cheered: Set<String> = []

    private let days = 21

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(routine.category.title, systemImage: routine.category.symbol)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(routine.displayName).font(.title2.weight(.semibold))
                    Text(routine.scheduleLabel)
                        .font(.subheadline)
                        .foregroundStyle(routine.urgency().color ?? .secondary)
                }

                if routine.kind == .daily, let score = routine.weekScore {
                    HStack(alignment: .bottom, spacing: 28) {
                        stat("\(routine.streak)일", "연속")
                        stat("\(score.done)/\(score.due)", "이번 주")
                        Spacer()
                        if routine.category != .screen && !routine.isDone(on: .now) {
                            Button {
                                RoutineActions.toggleSkip(routine, on: .now, in: context)
                            } label: {
                                Label(routine.isSkipped(on: .now) ? "쉬기 취소" : "오늘은 쉬기", systemImage: "moon.zzz")
                                    .font(.footnote)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .contentShape(Capsule())
                                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.2)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if routine.kind != .once {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("최근 3주").font(.caption).foregroundStyle(.secondary)
                        grass(Calendar.current.days(endingAt: .now, count: days).map { routine.grassCell(on: $0) })
                        ForEach(ShareSync.shared.others(of: routine)) { member in
                            HStack {
                                Text(member.name).font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                CheerButton(sent: cheered.contains(member.id)) {
                                    try? await ShareSync.shared.cheer(routine, member: member)
                                    cheered.insert(member.id)
                                }
                            }
                            .padding(.top, 4)
                            grass(member.cells(days: days)).opacity(0.6)
                        }
                        if routine.kind == .weekly {
                            PartChips(routine: routine, day: .now, compact: true).padding(.top, 4)
                        }
                    }
                }

                if routine.kind == .weekly {
                    WeeklyHistoryView(routine: routine)
                } else if routine.kind != .once {
                    RecentLogsView(routine: routine)
                }

                ShareSection(routine: routine)
            }
            .padding(20)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("수정", action: onEdit) }
        }
    }

    private func stat(_ value: LocalizedStringKey, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func grass(_ cells: [GrassCell]) -> some View {
        HStack(spacing: 3) {
            ForEach(cells.indices, id: \.self) { i in
                GrassCellView(cell: cells[i]).aspectRatio(1, contentMode: .fit)
            }
        }
    }
}
