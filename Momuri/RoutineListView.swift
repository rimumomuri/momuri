import SwiftUI

/// 루틴 탭: 분류별로 묶고 한 줄씩. 누르면 상세.
struct RoutineListView: View {
    let routines: [Routine]
    let onCreate: () -> Void
    let onOpen: (Routine) -> Void

    @AppStorage("collapsedGroups") private var collapsedRaw = ""
    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: "|").map(String.init)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                let appointments = routines.filter(\.isUpcoming).sorted { $0.eventDate < $1.eventDate }
                if !appointments.isEmpty {
                    group("약속", appointments)
                }
                ForEach(RoutineCategory.groupOrder, id: \.self) { name in
                    let items = routines.filter { $0.kind != .once && $0.category.group == name }
                    if !items.isEmpty { group(name, items) }
                }
                Button(action: onCreate) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("새 루틴 만들기")
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }

    private func group(_ name: String, _ items: [Routine]) -> some View {
        let isCollapsed = collapsed.contains(name)
        return VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { toggle(name) }
            } label: {
                HStack(spacing: 6) {
                    Text(name.localizedValue).font(.caption.weight(.medium))
                    Text("\(items.count)").font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up").font(.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !isCollapsed {
                ForEach(items) { routine in
                    Button { onOpen(routine) } label: { row(routine) }
                        .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }

    private func toggle(_ name: String) {
        var set = collapsed
        if set.contains(name) { set.remove(name) } else { set.insert(name) }
        collapsedRaw = set.sorted().joined(separator: "|")
    }

    private func row(_ routine: Routine) -> some View {
        HStack(spacing: 8) {
            Image(systemName: routine.category.symbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(routine.displayName).lineLimit(1)
            if routine.shareId != nil {
                Image(systemName: "person.2").font(.caption2).foregroundStyle(.tertiary)
            }
            if routine.isCritical {
                Circle().fill(Color.primary).frame(width: 4, height: 4)
                    .accessibilityLabel("필수")
            }
            Spacer(minLength: 8)
            trailing(routine)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    /// 주기·약속은 D-day, 나머지는 최근 7일 점
    @ViewBuilder
    private func trailing(_ routine: Routine) -> some View {
        if routine.kind == .interval || routine.kind == .once {
            Text(routine.statusLabel)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(routine.urgency().color ?? .secondary)
        } else {
            let cells = Calendar.current.days(endingAt: .now, count: 7).map { routine.grassCell(on: $0) }
            HStack(spacing: 2) {
                ForEach(cells.indices, id: \.self) { i in
                    GrassCellView(cell: cells[i]).frame(width: 8, height: 8)
                }
            }
            .overlay(alignment: .trailing) {
                if let color = routine.urgency().color {
                    Circle().fill(color).frame(width: 6, height: 6).offset(x: 9)
                }
            }
            .padding(.trailing, routine.urgency() == .none ? 0 : 8)
        }
    }
}
