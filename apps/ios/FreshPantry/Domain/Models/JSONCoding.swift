import Foundation

/// Helpers that make Swift's `Codable` write *every* declared key, including
/// nulls — matching Dart's `toJson()` which always emits a key (with a `null`
/// value) rather than omitting it. Byte-faithful payloads keep Supabase sync
/// parity with the Flutter client.
extension KeyedEncodingContainer {
    /// Encodes an ISO8601-or-null date string at `key`, always writing the key.
    mutating func encodeISODateAlways(_ date: Date?, forKey key: Key) throws {
        if let date {
            try encode(JSONDate.iso8601(date), forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }

    /// Encodes an optional value, always writing the key (null when absent).
    mutating func encodeAlways<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

extension KeyedDecodingContainer {
    /// Decodes an ISO8601 date string, tolerating missing key / null / blank /
    /// unparseable -> nil (mirrors `dateTimeFromJsonValue` + the string-guarded
    /// `DateTime.tryParse` paths used across the Flutter models).
    func decodeISODateIfPresent(forKey key: Key) -> Date? {
        guard let string = try? decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return JSONDate.fromJSONValue(string)
    }

    /// `decodeIfPresent` that also swallows type mismatches -> nil.
    func decodeLenientIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }

    /// Decodes a numeric field tolerant of int/double JSON encodings -> Int.
    func decodeIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    /// Decodes a numeric field tolerant of int/string -> Double.
    func decodeDoubleIfPresent(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        return nil
    }
}

/// Shared JSON coders configured to match the Flutter serialization shape.
enum DomainJSON {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    /// Encodes any domain `Encodable` to a JSON string (payloadJSON form).
    static func encodeToString<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                value,
                .init(codingPath: [], debugDescription: "UTF-8 encoding failed")
            )
        }
        return string
    }

    /// Decodes a domain `Decodable` from a JSON string (payloadJSON form).
    static func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "UTF-8 decoding failed")
            )
        }
        return try decoder.decode(type, from: data)
    }

    /// The domain object's `toJson()` as a `[String: JSONValue]` map — the outbox
    /// patch form. Encodes via the shared encoder then re-decodes into JSONValue so
    /// the patch is byte-identical to what the row codec / gateway consume.
    static func valueMap<T: Encodable>(_ value: T) -> [String: JSONValue]? {
        guard let data = try? encoder.encode(value),
              let map = try? decoder.decode([String: JSONValue].self, from: data)
        else { return nil }
        return map
    }

    /// Decodes a `[String: JSONValue]` domain map (the row codec / remote-repo form)
    /// back into a domain model — the inverse of `valueMap`.
    static func fromValueMap<T: Decodable>(_ type: T.Type, from map: [String: JSONValue]) -> T? {
        guard let data = try? encoder.encode(map),
              let model = try? decoder.decode(T.self, from: data)
        else { return nil }
        return model
    }

    /// Defensive decode of a JSON string-array blob (a UserDefaults preference
    /// list) → a de-duplicated set of its non-blank elements, each passed through
    /// `transform` first (normalize for case-folded sets, identity for
    /// case-sensitive ids). nil/empty/non-array/malformed → empty set.
    static func decodeStringSet(_ raw: String?, transform: (String) -> String = { $0 }) -> Set<String> {
        guard let raw, !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return [] }
        return Set(array.compactMap { $0 as? String }.map(transform).filter { !$0.isEmpty })
    }

    /// Encodes a string array to a compact JSON string for a UserDefaults blob —
    /// the inverse of `decodeStringSet`. nil when serialization fails.
    static func encodeStringArray(_ array: [String]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return json
    }
}
