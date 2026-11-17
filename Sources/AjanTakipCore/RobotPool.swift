import Foundation

/// Robotun hangi ajanları temsil ettiği.
public enum RobotRole: String, Codable, Sendable, CaseIterable {
    case main, sub, both

    func covers(_ r: RobotRole) -> Bool { self == .both || self == r }
}

/// Kullanıcının yüklediği `.glb` robot.
public struct CustomRobot: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var role: RobotRole
    public var flipped: Bool

    public init(id: String, name: String, role: RobotRole, flipped: Bool) {
        self.id = id; self.name = name; self.role = role; self.flipped = flipped
    }
}

/// `robots.json`: kapalı robotlar (hazır ya da kendi) ve kendi robotları.
public struct RobotPoolConfig: Codable, Equatable, Sendable {
    public var disabled: [String] = []
    public var customs: [CustomRobot] = []
    public init() {}
}

/// Sahneye giden kayıt: yalnız açık robotlar.
public struct PoolRobot: Codable, Equatable, Sendable {
    public var id: String
    public var role: RobotRole
    public var builtin: Bool
    public var url: String?
    public var flipped: Bool
}

public enum RobotPoolError: Error, Equatable {
    case notGLB, tooLarge, lastInRole
}

public enum RobotPool {
    /// Hazır robotlar; sahnedeki `robots.mjs` kataloğuyla aynı kimlikler.
    public static let builtins: [(id: String, name: String, role: RobotRole)] = [
        ("usta", "Usta", .main), ("muhendis", "Mühendis", .main), ("kasif", "Kâşif", .main),
        ("kivilcim", "Kıvılcım", .sub), ("pit", "Pıt", .sub), ("vida", "Vida", .sub),
    ]
    public static let maxBytes = 31_457_280

    public static func validate(_ data: Data) throws {
        guard data.count >= 4, data.prefix(4).elementsEqual([0x67, 0x6C, 0x54, 0x46]) else { throw RobotPoolError.notGLB }
        guard data.count <= maxBytes else { throw RobotPoolError.tooLarge }
    }

    static func roles(_ c: RobotPoolConfig) -> [(id: String, role: RobotRole)] {
        builtins.map { ($0.id, $0.role) } + c.customs.map { ($0.id, $0.role) }
    }

    /// `id` kapanırsa (ya da silinirse) her rolde en az bir açık robot kalıyor mu.
    public static func canDisable(_ id: String, in c: RobotPoolConfig) -> Bool {
        let open = roles(c).filter { $0.id != id && !c.disabled.contains($0.id) }
        return [RobotRole.main, .sub].allSatisfy { r in open.contains { $0.role.covers(r) } }
    }

    public static func sceneRobots(_ c: RobotPoolConfig) -> [PoolRobot] {
        let b = builtins.filter { !c.disabled.contains($0.id) }
            .map { PoolRobot(id: $0.id, role: $0.role, builtin: true, url: nil, flipped: false) }
        let u = c.customs.filter { !c.disabled.contains($0.id) }
            .map { PoolRobot(id: $0.id, role: $0.role, builtin: false, url: "atolye://app/robots/\($0.id).glb", flipped: $0.flipped) }
        return b + u
    }
}

/// `robots/` klasörü: `<id>.glb` dosyaları ve `robots.json`.
public final class RobotPoolStore: @unchecked Sendable {
    public let dir: URL
    public private(set) var config = RobotPoolConfig()

    public init(dir: URL) { self.dir = dir }

    var configURL: URL { dir.appendingPathComponent("robots.json") }
    public func fileURL(_ id: String) -> URL { dir.appendingPathComponent("\(id).glb") }

    public func load() {
        guard let d = try? Data(contentsOf: configURL), let c = try? JSONDecoder().decode(RobotPoolConfig.self, from: d) else { return }
        config = c
    }

    func save() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(config).write(to: configURL, options: .atomic)
    }

    @discardableResult
    public func add(data: Data, name: String, role: RobotRole) throws -> CustomRobot {
        try RobotPool.validate(data)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let r = CustomRobot(id: UUID().uuidString.lowercased(), name: name, role: role, flipped: false)
        try data.write(to: fileURL(r.id), options: .atomic)
        config.customs.append(r)
        try save()
        return r
    }

    public func remove(_ id: String) throws {
        guard config.customs.contains(where: { $0.id == id }) else { return }
        guard config.disabled.contains(id) || RobotPool.canDisable(id, in: config) else { throw RobotPoolError.lastInRole }
        config.customs.removeAll { $0.id == id }
        config.disabled.removeAll { $0 == id }
        try? FileManager.default.removeItem(at: fileURL(id))
        try save()
    }

    public func setEnabled(_ id: String, _ on: Bool) throws {
        if on {
            config.disabled.removeAll { $0 == id }
        } else {
            guard !config.disabled.contains(id) else { return }
            guard RobotPool.canDisable(id, in: config) else { throw RobotPoolError.lastInRole }
            config.disabled.append(id)
        }
        try save()
    }

    public func update(_ id: String, name: String? = nil, role: RobotRole? = nil, flipped: Bool? = nil) throws {
        guard let i = config.customs.firstIndex(where: { $0.id == id }) else { return }
        var r = config.customs[i]
        if let name { r.name = name }
        if let flipped { r.flipped = flipped }
        if let role, role != r.role {
            var test = config; test.customs[i].role = role
            let open = RobotPool.roles(test).filter { !test.disabled.contains($0.id) }
            guard [RobotRole.main, .sub].allSatisfy({ x in open.contains { $0.role.covers(x) } }) else { throw RobotPoolError.lastInRole }
            r.role = role
        }
        config.customs[i] = r
        try save()
    }
}
