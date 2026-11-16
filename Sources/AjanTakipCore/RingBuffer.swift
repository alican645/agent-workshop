import Foundation

/// Sabit kapasiteli bayt tamponu: dolunca en eski baytlar düşer. Ekleme maliyeti eklenen bayt kadardır.
public struct RingBuffer: Sendable {
    private var storage: [UInt8]
    private var start = 0
    private var count = 0
    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage = [UInt8](repeating: 0, count: self.capacity)
    }

    public mutating func append(_ d: Data) {
        let bytes = d.count > capacity ? d.suffix(capacity) : d[...]
        for b in bytes {
            storage[(start + count) % capacity] = b
            if count < capacity { count += 1 } else { start = (start + 1) % capacity }
        }
    }

    public var contents: Data {
        let end = start + count
        if end <= capacity { return Data(storage[start..<end]) }
        return Data(storage[start...]) + Data(storage[..<(end - capacity)])
    }
}
