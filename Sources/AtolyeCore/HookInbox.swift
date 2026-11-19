import Foundation

/// Claude Code hook'undan (`atolye-hook`) gelen olay: hook'un stdin'i olduğu gibi.
public struct HookEvent: Equatable, Sendable {
    public var event: String
    public var session: String
    public var tool: String?
    public var input: [String: JSONValue]
    /// PermissionRequest'in "bir daha sorma" önerileri (cevapta `updatedPermissions` olarak geri gider).
    public var suggestions: JSONValue?

    public init(event: String, session: String, tool: String?, input: [String: JSONValue], suggestions: JSONValue? = nil) {
        self.event = event; self.session = session; self.tool = tool; self.input = input; self.suggestions = suggestions
    }

    public static func parse(_ data: Data) -> HookEvent? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = o["hook_event_name"] as? String, let session = o["session_id"] as? String,
              !session.isEmpty else { return nil }
        let input = (o["tool_input"] as? [String: Any] ?? [:]).mapValues(JSONValue.init(any:))
        let sug = (o["permission_suggestions"] as? [Any]).flatMap { $0.isEmpty ? nil : JSONValue(any: $0) }
        return HookEvent(event: event, session: session, tool: o["tool_name"] as? String, input: input, suggestions: sug)
    }
}

/// Hook'un beklettiği izin isteği (soru, plan onayı ya da araç izni). Bağlantı açık durdukça terminaldeki
/// menü de açıktır; hangisi önce cevaplanırsa o geçer (hook'un geç cevabını Claude Code yok sayar).
public struct HookRequest: Equatable, Sendable {
    public var id: String
    public var session: String
    public var tool: String
    public var input: [String: JSONValue]
    public var suggestions: JSONValue?
    public var at: Date
    /// Çok sorulu soruda şimdiye kadar verilen cevaplar (soru metni → cevap).
    public var answers: [String: String] = [:]
}

/// Balondan verilen cevabın sonucu.
public enum HookAnswerResult: Equatable, Sendable {
    /// Hook'a bu JSON yazılır ve bağlantı kapanır.
    case reply(id: String, json: String)
    /// Çok sorulu soruda bir sayfa cevaplandı; sıradaki soru gösterilir.
    case next
}

/// Hook'tan gelen bekleyen istekler, oturum başına geliş sırasıyla.
public struct HookInbox: Sendable {
    public static let menuPrefix = "hook:"
    /// Kayıt "bekliyor"a geç düşebilir: yeni istek bu süre dolmadan "beklemiyor" diye atılmaz.
    public static let grace: TimeInterval = 4
    static let freeText = "Type something."
    static let denyMessage = "The user declined this in Agent Workshop."
    static let planDenyMessage = "The user rejected the plan in Agent Workshop. Keep planning; ask what to change."

    public private(set) var requests: [HookRequest] = []

    public init() {}

    /// Bekletilecek bir izin isteği mi (PermissionRequest)? Öyleyse saklanır; çağıran bağlantıyı açık tutar.
    public mutating func receive(_ e: HookEvent, id: String, now: Date) -> Bool {
        guard e.event == "PermissionRequest", let tool = e.tool else { return false }
        requests.append(HookRequest(id: id, session: e.session, tool: tool, input: e.input, suggestions: e.suggestions, at: now))
        return true
    }

    /// Araç çalıştı (ya da hata verdi): terminalden cevaplanmış demektir. Bırakılacak isteklerin kimlikleri.
    public mutating func toolFinished(_ e: HookEvent) -> [String] {
        guard e.event == "PostToolUse" || e.event == "PostToolUseFailure", let tool = e.tool else { return [] }
        let done = Self.comparable(e.input)
        // Aynı girdili ilk istek: PostToolUse'taki girdi (sorunun `answers`'ı gibi) güncellenmiş olabilir.
        guard let i = requests.firstIndex(where: { $0.session == e.session && $0.tool == tool && Self.comparable($0.input) == done })
        else { return [] }
        return [requests.remove(at: i).id]
    }

    /// Artık beklemeyen oturumların (süresi geçmiş) istekleri ve canlı olmayan oturumlarınkiler bırakılır.
    public mutating func drop(waiting: Set<String>, live: Set<String>, now: Date) -> [String] {
        var out: [String] = []
        requests.removeAll { r in
            let gone = !live.contains(r.session) && now.timeIntervalSince(r.at) > Self.grace
            let answered = live.contains(r.session) && !waiting.contains(r.session) && now.timeIntervalSince(r.at) > Self.grace
            if gone || answered { out.append(r.id) }
            return gone || answered
        }
        return out
    }

    /// Bağlantısı kopan (hook süresi doldu, Claude kapandı) istek.
    public mutating func remove(id: String) { requests.removeAll { $0.id == id } }

    public func current(session: String) -> HookRequest? { requests.first { $0.session == session } }

    /// Balonda gösterilecek menü. Hook'tan geldiği için her oturumda cevaplanabilir.
    public static func info(_ r: HookRequest) -> PromptInfo {
        switch r.tool {
        case "AskUserQuestion":
            let qs = questions(r.input)
            let page = qs.firstIndex { r.answers[$0.question] == nil } ?? 0
            guard qs.indices.contains(page) else { return permission(r) }
            let q = qs[page]
            var opts = q.options.map { PromptOptionInfo(label: $0.label, description: $0.description, checked: q.multi ? false : nil) }
            if !q.multi { opts.append(PromptOptionInfo(label: freeText, freeText: true)) }
            return PromptInfo(kind: .question, question: q.question, options: opts, multi: q.multi,
                              page: qs.count > 1 ? page : nil, pages: qs.count > 1 ? qs.count : nil,
                              answerable: true, menuId: menuId(r, page: page))
        case "ExitPlanMode":
            return PromptInfo(kind: .plan, question: "", options: [PromptOptionInfo(label: "Yes"), PromptOptionInfo(label: "No")],
                              multi: false, answerable: true, menuId: menuId(r, page: 0))
        default:
            return permission(r)
        }
    }

    private static func permission(_ r: HookRequest) -> PromptInfo {
        var opts = [PromptOptionInfo(label: "Yes")]
        if r.suggestions != nil { opts.append(PromptOptionInfo(label: "Yes, and don't ask again")) }
        opts.append(PromptOptionInfo(label: "No"))
        return PromptInfo(kind: .permission, question: "", detail: detail(r), options: opts, multi: false,
                          answerable: true, menuId: menuId(r, page: 0))
    }

    /// İzin ayrıntısı: komut, dosya yolu, adres… (tamamı; web kısaltır).
    static func detail(_ r: HookRequest) -> String {
        for k in ["command", "file_path", "notebook_path", "url", "path", "pattern", "query", "description"] {
            if let s = r.input[k]?.string, !s.isEmpty { return "\(r.tool): \(s)" }
        }
        return r.tool
    }

    static func menuId(_ r: HookRequest, page: Int) -> String { "\(menuPrefix)\(r.id):\(page)" }

    /// Balondan gelen cevap. Menü kimliği ya da etiketler gösterilenle tutmazsa ya da cevap eksikse nil
    /// (hiçbir şey gönderilmez).
    public mutating func answer(_ a: PromptAnswer, session: String) -> HookAnswerResult? {
        guard let idx = requests.firstIndex(where: { $0.session == session }) else { return nil }
        let r = requests[idx]
        let shown = Self.info(r)
        guard a.menuId == shown.menuId, a.labels == shown.options.map(\.label) else { return nil }
        switch (r.tool, shown.kind) {
        case ("AskUserQuestion", .question):
            let value: String
            if shown.multi {
                let picked = a.checks.filter { shown.options.indices.contains($0) }.map { shown.options[$0].label }
                guard !picked.isEmpty else { return nil }
                value = picked.joined(separator: ", ")
            } else {
                guard let i = a.option, shown.options.indices.contains(i) else { return nil }
                if shown.options[i].freeText {
                    guard let t = a.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
                    value = t
                } else {
                    value = shown.options[i].label
                }
            }
            requests[idx].answers[shown.question] = value
            let qs = Self.questions(r.input)
            if qs.contains(where: { requests[idx].answers[$0.question] == nil }) { return .next }
            var input = r.input
            input["answers"] = .object(requests[idx].answers.mapValues { .string($0) })
            requests.remove(at: idx)
            return .reply(id: r.id, json: Self.allow(updatedInput: input))
        default:
            guard let i = a.option, shown.options.indices.contains(i) else { return nil }
            let label = shown.options[i].label
            requests.remove(at: idx)
            if label == "No" {
                return .reply(id: r.id, json: Self.deny(r.tool == "ExitPlanMode" ? Self.planDenyMessage : Self.denyMessage))
            }
            return .reply(id: r.id, json: Self.allow(permissions: label == "Yes" ? nil : r.suggestions))
        }
    }

    // MARK: Cevap JSON'u

    static func allow(updatedInput: [String: JSONValue]? = nil, permissions: JSONValue? = nil) -> String {
        var d: [String: JSONValue] = ["behavior": .string("allow")]
        if let updatedInput { d["updatedInput"] = .object(updatedInput) }
        if let permissions { d["updatedPermissions"] = permissions }
        return output(d)
    }

    static func deny(_ message: String) -> String {
        output(["behavior": .string("deny"), "message": .string(message)])
    }

    private static func output(_ decision: [String: JSONValue]) -> String {
        let v: JSONValue = .object(["hookSpecificOutput": .object([
            "hookEventName": .string("PermissionRequest"), "decision": .object(decision)])])
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? enc.encode(v)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    // MARK: Yardımcılar

    struct Question { var question: String; var multi: Bool; var options: [(label: String, description: String?)] }

    static func questions(_ input: [String: JSONValue]) -> [Question] {
        (input["questions"]?.array ?? []).compactMap { v in
            guard let o = v.object, let q = o["question"]?.string else { return nil }
            let opts: [(label: String, description: String?)] = (o["options"]?.array ?? []).compactMap { v in
                guard let l = v.object?["label"]?.string else { return nil }
                let d = v.object?["description"]?.string
                return (l, d?.isEmpty == true ? nil : d)
            }
            return opts.isEmpty ? nil : Question(question: q, multi: o["multiSelect"]?.bool ?? false, options: opts)
        }
    }

    /// Karşılaştırma için girdi: cevaplar ve Claude Code'un sonradan eklediği plan alanları hariç.
    static func comparable(_ input: [String: JSONValue]) -> [String: JSONValue] {
        input.filter { !["answers", "plan", "planFilePath"].contains($0.key) }
    }
}
