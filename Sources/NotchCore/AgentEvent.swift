import Foundation

public enum AgentKind: String, CaseIterable, Sendable {
    case claude, codex, cursor

    public var name: String {
        switch self { case .claude: return "Claude"; case .codex: return "Codex"; case .cursor: return "Cursor" }
    }

    /// Cursor only exposes a hook before every shell command, so it reports completions only.
    public var supportsPermissions: Bool { self != .cursor }
}

public enum AgentEventKind: Sendable {
    /// Allow or deny a tool; denying may carry the user's own instruction.
    case permission
    /// The assistant asks the user to pick options or write an answer.
    case question
    case completion

    public var waitsForAnswer: Bool { self != .completion }
}

public struct AgentOption: Equatable, Sendable {
    public let label: String
    public let description: String

    public init(label: String, description: String = "") {
        self.label = label
        self.description = description
    }
}

public struct AgentQuestion: Equatable, Sendable {
    public let question: String
    public let header: String
    public let options: [AgentOption]
    public let multiSelect: Bool

    public init(question: String, header: String = "", options: [AgentOption], multiSelect: Bool = false) {
        self.question = question
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
    }
}

public enum AgentDecision: Equatable, Sendable {
    case allow
    /// Denies the tool; a message tells the assistant what to do instead.
    case deny(String?)
    /// Answers keyed by question text; several choices are joined with ", ".
    case answer([String: String])
}

public struct AgentEvent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let agent: AgentKind
    public let kind: AgentEventKind
    /// Tool name for permissions and questions; empty for completions.
    public let tool: String
    public let detail: String
    public let project: String?
    public let questions: [AgentQuestion]
    /// The original tool input, echoed back with the answers.
    public let input: Data?

    public init(id: UUID = UUID(), agent: AgentKind, kind: AgentEventKind, tool: String = "", detail: String,
                project: String?, questions: [AgentQuestion] = [], input: Data? = nil) {
        self.id = id
        self.agent = agent
        self.kind = kind
        self.tool = tool
        self.detail = detail
        self.project = project
        self.questions = questions
        self.input = input
    }
}

/// Translates hook payloads into island events and decisions back into hook output.
/// Claude Code and Codex share the PermissionRequest/Stop format; Cursor uses its own `stop`.
public enum AgentHook {
    public static let detailLimit = 400
    public static let planLimit = 1200

    public static func event(agent: AgentKind, payload: Data) -> AgentEvent? {
        guard let json = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else { return nil }
        let name = json["hook_event_name"] as? String ?? ""
        switch (agent, name) {
        case (.claude, "PermissionRequest"), (.codex, "PermissionRequest"):
            let tool = json["tool_name"] as? String ?? "Ferramenta"
            let input = json["tool_input"] as? [String: Any] ?? [:]
            let project = project(json["cwd"])
            let raw = try? JSONSerialization.data(withJSONObject: input)
            let questions = parseQuestions(input["questions"])
            if !questions.isEmpty {
                return AgentEvent(agent: agent, kind: .question, tool: tool, detail: questions[0].question,
                                  project: project, questions: questions, input: raw)
            }
            if let plan = input["plan"] as? String {
                return AgentEvent(agent: agent, kind: .permission, tool: tool, detail: clean(plan, limit: planLimit), project: project, input: raw)
            }
            return AgentEvent(agent: agent, kind: .permission, tool: tool, detail: summary(of: input), project: project, input: raw)
        case (.claude, "Stop"), (.codex, "Stop"):
            // A Stop hook re-entering its own continuation is not a new answer.
            if json["stop_hook_active"] as? Bool == true { return nil }
            let message = clean(json["last_assistant_message"] as? String ?? "")
            return AgentEvent(agent: agent, kind: .completion, detail: message.isEmpty ? "Resposta pronta." : message, project: project(json["cwd"]))
        case (.cursor, "stop"):
            let status = json["status"] as? String ?? "completed"
            if status == "aborted" { return nil }
            let roots = json["workspace_roots"] as? [String]
            return AgentEvent(agent: agent, kind: .completion,
                              detail: status == "error" ? "A tarefa terminou com erro." : "Tarefa concluída.",
                              project: project(roots?.first))
        default:
            return nil
        }
    }

    public static func response(_ decision: AgentDecision, for event: AgentEvent? = nil) -> Data {
        let body: [String: Any]
        switch decision {
        case .allow:
            body = ["behavior": "allow"]
        case .deny(let message):
            let text = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            body = ["behavior": "deny", "message": text.isEmpty ? "Recusado pelo usuário no Notch." : text]
        case .answer(let answers):
            var input = event?.input.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            input["answers"] = answers
            body = ["behavior": "allow", "updatedInput": input]
        }
        let output: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": body]]
        return (try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])) ?? Data()
    }

    static func parseQuestions(_ value: Any?) -> [AgentQuestion] {
        guard let items = value as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let question = item["question"] as? String, !question.isEmpty else { return nil }
            let options = (item["options"] as? [[String: Any]] ?? []).compactMap { option -> AgentOption? in
                guard let label = option["label"] as? String, !label.isEmpty else { return nil }
                return AgentOption(label: label, description: option["description"] as? String ?? "")
            }
            return AgentQuestion(question: question, header: item["header"] as? String ?? "", options: options,
                                 multiSelect: item["multiSelect"] as? Bool ?? false)
        }
    }

    static func summary(of input: [String: Any]) -> String {
        for key in ["command", "file_path", "path", "url", "pattern", "description", "prompt"] {
            if let value = input[key] as? String, !value.isEmpty { return clean(value) }
        }
        if let command = input["command"] as? [String] { return clean(command.joined(separator: " ")) }
        guard !input.isEmpty, let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]) else { return "" }
        return clean(String(decoding: data, as: UTF8.self))
    }

    static func clean(_ text: String, limit: Int = detailLimit) -> String {
        let flat = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        return flat.count > limit ? String(flat.prefix(limit - 1)) + "…" : flat
    }

    static func project(_ value: Any?) -> String? {
        guard let path = value as? String, !path.isEmpty else { return nil }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}
