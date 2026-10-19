import SwiftUI
import SwiftData

/// 루틴 수정 화면의 "같이 하기"
struct ShareSection: View {
    @Environment(\.modelContext) private var context
    let routine: Routine

    @State private var working = false
    @State private var error: String?
    @State private var askingName = false
    @State private var name = ""
    @State private var confirmingLeave = false

    private var sync: ShareSync { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("같이 하기").font(.caption).foregroundStyle(.secondary)
            if let code = routine.shareCode {
                HStack {
                    Text(code).font(.title3.monospaced().weight(.semibold))
                    Spacer()
                    ShareLink(item: String(localized: "momuri에서 '\(routine.displayName)' 같이 해요. 초대 코드: \(code)")) {
                        Label("초대 보내기", systemImage: "square.and.arrow.up").font(.subheadline)
                    }
                }
                let members = sync.members[routine.shareId ?? ""] ?? []
                if !members.isEmpty {
                    Text(members.map { $0.id == ShareClient.me?.id ? String(localized: "\($0.name)(나)") : $0.name }.joined(separator: ", "))
                        .font(.subheadline)
                }
                Text("각자 체크하고, 루틴 목록에서 서로의 잔디를 볼 수 있어요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("공유 그만하기", role: .destructive) { confirmingLeave = true }
                    .font(.subheadline)
                    .padding(.top, 4)
            } else {
                Button {
                    if ShareClient.me == nil { askingName = true } else { Task { await start() } }
                } label: {
                    HStack {
                        Image(systemName: "person.2")
                        Text(working ? "만드는 중…" : "공유하기")
                        Spacer()
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .contentShape(Rectangle())
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .disabled(working)
                Text("초대 코드를 보내면 상대도 같은 루틴을 갖고, 서로의 기록을 볼 수 있어요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .alert("내 이름", isPresented: $askingName) {
            TextField("상대에게 보일 이름", text: $name)
            Button("확인") { Task { await start() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("공유한 사람들에게 이 이름으로 보여요")
        }
        .confirmationDialog("이 루틴 공유를 그만할까요? 내 기록은 그대로 남아요.", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("그만하기", role: .destructive) {
                Task {
                    do { try await sync.leave(routine, context: context) } catch { self.error = error.localizedDescription }
                }
            }
        }
    }

    private func start() async {
        working = true
        defer { working = false }
        do {
            if ShareClient.me == nil {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { error = String(localized: "이름을 적어 주세요"); return }
                _ = try await ShareClient.register(name: trimmed)
            }
            try await sync.share(routine, context: context)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 초대 코드로 참여
struct JoinShareView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let onJoined: () -> Void

    @State private var code = ""
    @State private var name = ""
    @State private var working = false
    @State private var error: String?
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                if ShareClient.me == nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("내 이름").font(.caption).foregroundStyle(.secondary)
                        TextField("상대에게 보일 이름", text: $name).font(.title3)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("초대 코드").font(.caption).foregroundStyle(.secondary)
                    TextField("ABC234", text: $code)
                        .font(.title2.monospaced().weight(.semibold))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($codeFocused)
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Spacer()
                Button(action: { Task { await join() } }) {
                    Text(working ? "참여하는 중…" : "참여하기")
                        .font(.headline)
                        .foregroundStyle(Color(.systemBackground))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(Color.primary.opacity(canJoin ? 1 : 0.2)))
                }
                .disabled(!canJoin || working)
            }
            .padding(20)
            .onAppear { if ShareClient.me != nil { codeFocused = true } }
            .navigationTitle("초대 코드로 참여")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .tint(.primary)
    }

    private var canJoin: Bool {
        code.trimmingCharacters(in: .whitespaces).count >= 6 && (ShareClient.me != nil || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func join() async {
        working = true
        defer { working = false }
        do {
            if ShareClient.me == nil { _ = try await ShareClient.register(name: name.trimmingCharacters(in: .whitespaces)) }
            _ = try await ShareSync.shared.join(code: code, context: context)
            dismiss()
            onJoined()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
