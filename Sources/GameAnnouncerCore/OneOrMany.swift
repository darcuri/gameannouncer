/// MFL's JSON is converted from XML: a list with one element arrives as a bare object,
/// and an empty list may be missing entirely. This decodes all three shapes as an array.
public struct OneOrMany<Element: Decodable & Sendable>: Decodable, Sendable {
    public var values: [Element]

    public init(_ values: [Element]) { self.values = values }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let many = try? container.decode([Element].self) {
            values = many
        } else {
            values = [try container.decode(Element.self)]
        }
    }
}

extension KeyedDecodingContainer {
    /// Missing key → empty list, so callers don't have to special-case leagues/weeks with no entries.
    public func decode<E>(_ type: OneOrMany<E>.Type, forKey key: Key) throws -> OneOrMany<E> {
        try decodeIfPresent(type, forKey: key) ?? OneOrMany([])
    }
}

/// MFL sends every number as a string, sometimes empty ("" before kickoff).
@propertyWrapper
public struct LenientInt: Decodable, Sendable {
    public var wrappedValue: Int?
    public init(wrappedValue: Int?) { self.wrappedValue = wrappedValue }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            wrappedValue = Int(s)
        } else {
            wrappedValue = try? c.decode(Int.self)
        }
    }
}

extension KeyedDecodingContainer {
    public func decode(_ type: LenientInt.Type, forKey key: Key) throws -> LenientInt {
        try decodeIfPresent(type, forKey: key) ?? LenientInt(wrappedValue: nil)
    }
}
