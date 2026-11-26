import Foundation

/// 宽容的动态 JSON：飞牛接口字段经常 snake/camel 混用、数字/字符串混用，统一用它读取。
enum JSON: Codable, Hashable {
    case null, bool(Bool), number(Double), string(String), array([JSON]), object([String: JSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSON].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSON].self) { self = .object(o) }
        else { self = .null }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
    static func parse(_ data: Data) -> JSON {
        (try? JSONDecoder().decode(JSON.self, from: data)) ?? .null
    }
    static func from(_ any: Any?) -> JSON {
        guard let any else { return .null }
        if let d = try? JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed]) { return parse(d) }
        return .null
    }
    subscript(_ key: String) -> JSON {
        if case .object(let o) = self { return o[key] ?? .null }
        return .null
    }
    subscript(_ i: Int) -> JSON {
        if case .array(let a) = self, i >= 0, i < a.count { return a[i] }
        return .null
    }
    /// 依次尝试多个 key（兼容 snake_case / camelCase）
    func first(_ keys: String...) -> JSON {
        for k in keys { let v = self[k]; if !v.isNull { return v } }
        return .null
    }
    var isNull: Bool { if case .null = self { return true }; return false }
    var array: [JSON] { if case .array(let a) = self { return a }; return [] }
    var object: [String: JSON] { if case .object(let o) = self { return o }; return [:] }
    var string: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }
    var str: String { string ?? "" }
    var double: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }
    var int: Int? { double.map { Int($0) } }
    var bool: Bool {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s): return s == "1" || s.lowercased() == "true"
        default: return false
        }
    }
    var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n
        case .string(let s): return s
        case .array(let a): return a.map { $0.anyValue }
        case .object(let o): return o.mapValues { $0.anyValue }
        }
    }
}
