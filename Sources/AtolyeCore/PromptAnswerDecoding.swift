import Foundation

extension PromptAnswer {
    /// Sahneden gelen `answer` mesajını çözer. Emin olunmayan her durumda nil (hiçbir şey gönderilmez):
    /// zorunlu alan (robot, labels, menuId) eksik/yanlış tipte, ya da var olan bir alan yanlış tipte ise mesaj tümden reddedilir.
    public static func decode(_ body: [String: Any]) -> (robot: String, answer: PromptAnswer)? {
        guard let robot = body["robot"] as? String, let menuId = body["menuId"] as? String,
              let rawLabels = body["labels"] as? [Any] else { return nil }
        var labels: [String] = []
        for l in rawLabels {
            guard let s = l as? String else { return nil }
            labels.append(s)
        }
        var option: Int?
        if let v = body["option"] {
            guard let i = integer(v) else { return nil }
            option = i
        }
        var checks: [Int] = []
        if let v = body["checks"] {
            guard let arr = v as? [Any] else { return nil }
            for e in arr {
                guard let i = integer(e) else { return nil }
                checks.append(i)
            }
        }
        var text: String?
        if let v = body["text"] {
            guard let s = v as? String else { return nil }
            text = s
        }
        return (robot, PromptAnswer(option: option, checks: checks, text: text, labels: labels, menuId: menuId))
    }

    /// Yalnız tam sayı olan, boolean olmayan sayıyı Int'e çevirir (true→1, 1.5→1 kabul edilmez).
    private static func integer(_ v: Any) -> Int? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return Int(exactly: n.doubleValue)
    }
}
