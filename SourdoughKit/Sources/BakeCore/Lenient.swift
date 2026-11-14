import Foundation

/// Wraps an optional choice so stored data with a choice that no longer exists
/// (e.g. after a list is edited) reads as "not set" instead of failing the whole record.
///
/// Missing keys decode as nil, and nil is left out when encoding, so stored JSON looks the same
/// as for a plain optional.
@propertyWrapper
public struct Lenient<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public var wrappedValue: Value?

    public init(wrappedValue: Value?) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        wrappedValue = try? decoder.singleValueContainer().decode(Value.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

public extension KeyedDecodingContainer {
    func decode<Value>(_ type: Lenient<Value>.Type, forKey key: Key) throws -> Lenient<Value> {
        (try? decodeIfPresent(type, forKey: key)) ?? Lenient(wrappedValue: nil)
    }
}

public extension KeyedEncodingContainer {
    mutating func encode<Value>(_ value: Lenient<Value>, forKey key: Key) throws {
        if let wrapped = value.wrappedValue { try encode(wrapped, forKey: key) }
    }
}

/// Lets reflection (PlanDiff) see through the wrapper.
protocol LenientBox {
    var boxedValue: Any? { get }
}

extension Lenient: LenientBox {
    var boxedValue: Any? { wrappedValue }
}
