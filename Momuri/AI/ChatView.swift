import SwiftUI

/// 말로 루틴 만들기·기록·질문
struct ChatView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var chat = ChatModel()
    @State private var text = ""
    @FocusState private var focused: Bool

    private let suggestions = [
        String(localized: "매일 아침 8시에 비타민 먹기"),
        String(localized: "다음 주 금요일 저녁 7시 강남역에서 유진이랑 저녁"),
        String(localized: "이번 달 러닝 얼마나 했어?"),
        String(localized: "헬스 가슴 했어"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if chat.items.isEmpty {
                                if let reason = chat.unavailableReason { notice(reason) }
                                intro
                            }
                            ForEach(chat.items) { item in
                                bubble(item).id(item.id)
                            }
                            if chat.thinking {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("생각하는 중…").font(.subheadline).foregroundStyle(.secondary)
                                }
                                .id("thinking")
                            }
                        }
                        .padding(20)
                    }
                    .onChange(of: chat.items.count) {
                        withAnimation { proxy.scrollTo(chat.items.last?.id, anchor: .bottom) }
                    }
                }
                inputBar
            }
            .navigationTitle("momuri AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
        }
        .tint(.primary)
        .onAppear { focused = true }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("말로 루틴을 만들고, 기록하고, 물어보세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(suggestions, id: \.self) { s in
                Button { Task { await chat.send(s) } } label: {
                    Text(s)
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
            Text(chat.isFallback ? "기기 안에서만 처리돼요." : "기기 안 AI로 처리돼서 내용이 밖으로 나가지 않아요.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }

    private func notice(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("간단 모드", systemImage: "sparkles").font(.headline)
            Text(reason).font(.subheadline).foregroundStyle(.secondary)
            Text("그동안은 아래 예시 같은 짧은 문장만 알아들어요.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
    }

    @ViewBuilder
    private func bubble(_ item: ChatModel.Item) -> some View {
        switch item {
        case .user(_, let text):
            HStack {
                Spacer(minLength: 48)
                Text(text)
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.primary))
            }
        case .assistant(_, let text):
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
        case .draft(let draft, let added):
            draftCard(draft, added: added)
        }
    }

    private func draftCard(_ draft: RoutineFactory.Draft, added: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: draft.category.symbol).foregroundStyle(.secondary)
                Text(draft.name.localizedValue).font(.headline)
            }
            Text(draft.summary.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if added {
                Label("추가했어요", systemImage: "checkmark").font(.subheadline.weight(.medium))
            } else {
                HStack(spacing: 8) {
                    Button { chat.confirm(draft) } label: {
                        Text(draft.category == .appointment ? "약속 추가" : "루틴 추가")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(.systemBackground))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.primary))
                    }
                    Button { chat.discard(draft) } label: {
                        Text("버리기")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .contentShape(Capsule())
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.15)))
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("루틴이나 일정을 말해 보세요", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.2)))
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.headline)
                    .foregroundStyle(Color(.systemBackground))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.primary.opacity(canSend ? 1 : 0.2)))
            }
            .disabled(!canSend)
            .accessibilityLabel("보내기")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.background)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty && !chat.thinking
    }

    private func send() {
        guard canSend else { return }
        let message = text
        text = ""
        Task { await chat.send(message) }
    }
}
