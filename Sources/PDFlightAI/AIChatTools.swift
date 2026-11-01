import Foundation

/// JSON values let provider-specific tool schemas travel through native chat
/// without relying on non-Sendable Foundation collections.
public indirect enum AIJSONValue: Codable, Sendable, Equatable {
    case object([String: AIJSONValue])
    case array([AIJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let v = try? value.decode(Bool.self) { self = .bool(v) }
        else if let v = try? value.decode(Double.self) { self = .number(v) }
        else if let v = try? value.decode(String.self) { self = .string(v) }
        else if let v = try? value.decode([AIJSONValue].self) { self = .array(v) }
        else { self = .object(try value.decode([String: AIJSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let v): try value.encode(v)
        case .array(let v): try value.encode(v)
        case .string(let v): try value.encode(v)
        case .number(let v): try value.encode(v)
        case .bool(let v): try value.encode(v)
        case .null: try value.encodeNil()
        }
    }
}

public struct AIChatToolDefinition: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let parameters: AIJSONValue

    public init(name: String, description: String, parameters: AIJSONValue) {
        self.name = name; self.description = description; self.parameters = parameters
    }
}

public struct AIChatToolCall: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    /// Original JSON text, including incomplete or invalid input, is retained.
    public var arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id; self.name = name; self.arguments = arguments
    }
}

public struct AIChatToolCallDelta: Sendable, Equatable {
    public let index: Int
    public let id: String?
    public let name: String?
    public let arguments: String?

    public init(index: Int, id: String? = nil, name: String? = nil, arguments: String? = nil) {
        self.index = index; self.id = id; self.name = name; self.arguments = arguments
    }
}
