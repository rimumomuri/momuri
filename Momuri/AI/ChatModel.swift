import Foundation
import FoundationModels
import Observation
import SwiftData

/// 기기 안 AI(Foundation Models)와의 대화. 루틴 만들기는 확인 카드를 거친다.
@MainActor
@Observable
final class ChatModel {
    enum Item: Identifiable {
        case user(UUID, String)
        case assistant(UUID, String)
        case draft(RoutineFactory.Draft, added: Bool)

        var id: UUID {
            switch self {
            case .user(let id, _), .assistant(let id, _): id
            case .draft(let d, _): d.id
            }
        }
    }

    private(set) var items: [Item] = []
    private(set) var thinking = false
    private var session: LanguageModelSession?

    var isFallback: Bool { useFallback || unavailableReason != nil }

    /// 쓸 수 없으면 이유를 사람 말로
    var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): String(localized: "이 기기는 Apple Intelligence를 지원하지 않아요.")
        case .unavailable(.appleIntelligenceNotEnabled): String(localized: "설정 > Apple Intelligence를 켜면 쓸 수 있어요.")
        case .unavailable(.modelNotReady): String(localized: "AI 모델을 내려받는 중이에요. 잠시 뒤에 다시 해 주세요.")
        case .unavailable: String(localized: "지금은 AI를 쓸 수 없어요.")
        }
    }

    func send(_ text: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking else { return }
        items.append(.user(UUID(), text))
        // AI를 못 쓰는 기기는 규칙 기반으로
        guard unavailableReason == nil, !useFallback else {
            applyFallback(text)
            return
        }
        thinking = true
        defer { thinking = false }
        do {
            let reply = try await currentSession().respond(to: text)
            items.append(.assistant(UUID(), reply.content))
        } catch let error as LanguageModelSession.GenerationError {
            NSLog("momuri AI error: \(String(describing: error))")
            if case .exceededContextWindowSize = error {
                // 대화가 길어지면 새로 시작한다
                session = nil
                items.append(.assistant(UUID(), String(localized: "대화가 길어져서 새로 시작할게요. 다시 말해 주세요.")))
            } else {
                applyFallback(text)
            }
        } catch {
            NSLog("momuri AI error: \(String(describing: error))")
            applyFallback(text)
        }
    }

    /// AI가 실패하면 그 뒤로는 규칙 기반으로 처리한다 (같은 오류 반복 방지)
    private var useFallback = false

    private func applyFallback(_ text: String) {
        useFallback = true
        switch ChatFallback.handle(text) {
        case .reply(let reply):
            items.append(.assistant(UUID(), reply))
        case .draft(let draft, let reply):
            items.append(.assistant(UUID(), reply))
            items.append(.draft(draft, added: false))
        }
    }

    func addDraft(_ draft: RoutineFactory.Draft) {
        items.append(.draft(draft, added: false))
    }

    func confirm(_ draft: RoutineFactory.Draft) {
        RoutineFactory.create(draft, in: SharedStore.container.mainContext)
        replace(draft, added: true)
        session = nil  // 루틴 목록이 바뀌었으니 다음 질문부터 새 목록으로
    }

    func discard(_ draft: RoutineFactory.Draft) {
        items.removeAll { $0.id == draft.id }
    }

    private func replace(_ draft: RoutineFactory.Draft, added: Bool) {
        guard let i = items.firstIndex(where: { $0.id == draft.id }) else { return }
        items[i] = .draft(draft, added: added)
    }

    private func currentSession() -> LanguageModelSession {
        if let session { return session }
        let new = LanguageModelSession(
            tools: [ProposeRoutineTool(chat: self), ProposeAppointmentTool(chat: self), LogRoutineTool(), StatsTool()],
            instructions: instructions()
        )
        session = new
        return new
    }

    private func instructions() -> String {
        let f = DateFormatter()
        f.locale = Locale.app
        f.dateFormat = "yyyy-MM-dd (E)"
        let routines = ((try? SharedStore.container.mainContext.fetch(FetchDescriptor<Routine>())) ?? [])
            .filter { $0.kind != .once || $0.isUpcoming }
            .map { "- \($0.displayName) [\($0.category.title)] \($0.statusLabel)" }
            .joined(separator: "\n")
        // 답하는 언어는 앱 화면 언어를 따른다
        let replyRule = Locale.app.language.languageCode?.identifier == "ja"
            ? "답은 일본어 정중체(です・ます)로 한두 문장, 짧게."
            : "답은 한국어 존댓말로 한두 문장, 짧게."
        return """
        너는 루틴 앱 momuri의 도우미야. 오늘은 \(f.string(from: .now))이야.
        - 새로 반복할 일을 만들려는 말이면 proposeRoutine, 날짜가 있는 약속이면 proposeAppointment를 불러. 날짜는 오늘 기준으로 계산해.
        - '했어', '먹었어', '뛰었어', '풀었어'처럼 한 일을 말하면 logRoutine을 불러.
        - 기록에 대한 질문이면 getStats로 확인한 뒤 그 숫자로만 답해. 숫자를 지어내지 마.
        - \(replyRule)
        현재 루틴:
        \(routines.isEmpty ? "(없음)" : routines)
        """
    }
}
