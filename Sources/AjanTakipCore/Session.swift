import Foundation

public enum SessionState: Int, Comparable, Sendable {
    case waiting = 0, working = 1, done = 2, idle = 3

    public static func < (a: SessionState, b: SessionState) -> Bool { a.rawValue < b.rawValue }

    /// Sıralama grubu: done ve idle aynı gruptadır.
    var sortGroup: Int { min(rawValue, 2) }
}

public struct Session: Identifiable, Equatable, Sendable {
    public let id: String
    public var projectName: String
    public var state: SessionState
    public var activity: String
    public var stateSince: Date
    public var lastEventAt: Date
    public var workspace: String?
    public var surface: String?
    public var pid: Int32?
    var lastTool: String?
}

public enum AlertKind: Equatable, Sendable {
    case attention, finished
}

public struct Counts: Equatable, Sendable {
    public var working: Int
    public var waiting: Int
    /// done + idle
    public var done: Int

    public init(working: Int, waiting: Int, done: Int) {
        self.working = working
        self.waiting = waiting
        self.done = done
    }
}
