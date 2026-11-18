import Foundation
import Testing
@testable import AtolyeCore

@Suite struct PromptAnswerDecodingTests {
    private func body(_ extra: [String: Any] = [:]) -> [String: Any] {
        var b: [String: Any] = ["type": "answer", "robot": "r1", "labels": ["A", "B"]]
        for (k, v) in extra { b[k] = v }
        return b
    }

    @Test func valid() {
        let d = PromptAnswer.decode(body(["option": NSNumber(value: 1), "checks": [0, 2], "text": "x"]))
        #expect(d?.robot == "r1")
        #expect(d?.answer == PromptAnswer(option: 1, checks: [0, 2], text: "x", labels: ["A", "B"]))
        #expect(PromptAnswer.decode(body())?.answer == PromptAnswer(labels: ["A", "B"]))
    }

    @Test func rejects() {
        #expect(PromptAnswer.decode(["labels": ["A"]]) == nil)
        #expect(PromptAnswer.decode(["robot": "r"]) == nil)
        #expect(PromptAnswer.decode(["robot": 1, "labels": []]) == nil)
        #expect(PromptAnswer.decode(body(["labels": ["A", 2]])) == nil)
        #expect(PromptAnswer.decode(body(["labels": "A"])) == nil)
        #expect(PromptAnswer.decode(body(["checks": [0, "x", 2]])) == nil)
        #expect(PromptAnswer.decode(body(["checks": "0"])) == nil)
        #expect(PromptAnswer.decode(body(["checks": [true]])) == nil)
        #expect(PromptAnswer.decode(body(["checks": [1.5]])) == nil)
        #expect(PromptAnswer.decode(body(["option": "1"])) == nil)
        #expect(PromptAnswer.decode(body(["option": true])) == nil)
        #expect(PromptAnswer.decode(body(["option": 1.5])) == nil)
        #expect(PromptAnswer.decode(body(["text": 5])) == nil)
        #expect(PromptAnswer.decode(body(["text": NSNull()])) == nil)
    }
}
