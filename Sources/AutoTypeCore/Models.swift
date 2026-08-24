import Foundation

public enum InputMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case unicode
    case physical

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .unicode: "Unicode"
        case .physical: "Physical keys"
        }
    }
}

public enum TabBehavior: Equatable, Sendable {
    case spaces(Int)
    case physical
    case skip

    public static let `default`: TabBehavior = .spaces(4)

    public var displayName: String {
        switch self {
        case let .spaces(count): "\(count) spaces"
        case .physical: "Tab key"
        case .skip: "Skip tabs"
        }
    }
}

extension TabBehavior: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case count
    }

    private enum Kind: String, Codable {
        case spaces
        case physical
        case skip
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .spaces:
            self = .spaces(min(max(try container.decode(Int.self, forKey: .count), 1), 8))
        case .physical:
            self = .physical
        case .skip:
            self = .skip
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .spaces(count):
            try container.encode(Kind.spaces, forKey: .kind)
            try container.encode(min(max(count, 1), 8), forKey: .count)
        case .physical:
            try container.encode(Kind.physical, forKey: .kind)
        case .skip:
            try container.encode(Kind.skip, forKey: .kind)
        }
    }
}

public struct TypingConfiguration: Codable, Equatable, Sendable {
    public var inputMode: InputMode
    public var tabBehavior: TabBehavior
    public var startDelay: TimeInterval
    public var charactersPerSecond: Double
    public var lineDelay: TimeInterval
    public var repeatCount: Int
    public var repeatInterval: TimeInterval

    public init(
        inputMode: InputMode = .unicode,
        tabBehavior: TabBehavior = .default,
        startDelay: TimeInterval = 3,
        charactersPerSecond: Double = 30,
        lineDelay: TimeInterval = 0,
        repeatCount: Int = 1,
        repeatInterval: TimeInterval = 0
    ) {
        self.inputMode = inputMode
        self.tabBehavior = tabBehavior
        self.startDelay = startDelay
        self.charactersPerSecond = charactersPerSecond
        self.lineDelay = lineDelay
        self.repeatCount = repeatCount
        self.repeatInterval = repeatInterval
        normalize()
    }

    public mutating func normalize() {
        startDelay = min(max(startDelay, 0), 30)
        charactersPerSecond = min(max(charactersPerSecond, 1), 100)
        lineDelay = min(max(lineDelay, 0), 5)
        repeatCount = min(max(repeatCount, 1), 100)
        repeatInterval = min(max(repeatInterval, 0), 60)
        if case let .spaces(count) = tabBehavior {
            tabBehavior = .spaces(min(max(count, 1), 8))
        }
    }

    public var normalized: TypingConfiguration {
        var copy = self
        copy.normalize()
        return copy
    }

    public static let `default` = TypingConfiguration()
}

public struct TargetApplication: Codable, Equatable, Identifiable, Sendable {
    public let processIdentifier: Int32
    public let bundleIdentifier: String?
    public let name: String

    public init(processIdentifier: Int32, bundleIdentifier: String?, name: String) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }

    public var id: Int32 { processIdentifier }
}

public struct TypingJob: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let text: String
    public let target: TargetApplication
    public let configuration: TypingConfiguration

    public init(
        id: UUID = UUID(),
        text: String,
        target: TargetApplication,
        configuration: TypingConfiguration
    ) {
        self.id = id
        self.text = text
        self.target = target
        self.configuration = configuration.normalized
    }
}

public struct TypingProgress: Equatable, Sendable {
    public let completedUnits: Int
    public let totalUnits: Int
    public let repeatIndex: Int
    public let repeatCount: Int
    public let unicodeFallbacks: Int

    public init(
        completedUnits: Int,
        totalUnits: Int,
        repeatIndex: Int,
        repeatCount: Int,
        unicodeFallbacks: Int
    ) {
        self.completedUnits = completedUnits
        self.totalUnits = totalUnits
        self.repeatIndex = repeatIndex
        self.repeatCount = repeatCount
        self.unicodeFallbacks = unicodeFallbacks
    }

    public var fractionCompleted: Double {
        guard totalUnits > 0 else { return 0 }
        return min(max(Double(completedUnits) / Double(totalUnits), 0), 1)
    }
}

public enum PauseReason: Equatable, Sendable {
    case user
    case focusChanged(expectedApplication: String)
    case secureField
    case accessibilityPermissionLost
    case targetTerminated
}

public enum TypingState: Equatable, Sendable {
    case idle
    case countdown(secondsRemaining: Int)
    case typing(TypingProgress)
    case paused(reason: PauseReason, progress: TypingProgress)
    case completed(TypingProgress)
    case cancelled(TypingProgress?)
    case failed(message: String, progress: TypingProgress?)

    public var isActive: Bool {
        switch self {
        case .countdown, .typing, .paused: true
        default: false
        }
    }
}

public enum TargetSafetyStatus: Equatable, Sendable {
    case safe
    case focusChanged
    case secureField
    case accessibilityPermissionLost
    case targetTerminated
}

public enum SpecialKey: Equatable, Sendable {
    case returnKey
    case tab
}

public struct Preset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var text: String
    public var tags: [String]
    public var isFavorite: Bool
    public var configurationOverride: TypingConfiguration?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        text: String,
        tags: [String] = [],
        isFavorite: Bool = false,
        configurationOverride: TypingConfiguration? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = text
        self.tags = Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        self.isFavorite = isFavorite
        self.configurationOverride = configurationOverride?.normalized
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PresetCollection: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var presets: [Preset]

    public init(schemaVersion: Int = currentSchemaVersion, presets: [Preset]) {
        self.schemaVersion = schemaVersion
        self.presets = presets
    }
}

public struct ImportResult: Equatable, Sendable {
    public let imported: Int
    public let skippedIdentical: Int
    public let duplicatedConflicts: Int

    public init(imported: Int, skippedIdentical: Int, duplicatedConflicts: Int) {
        self.imported = imported
        self.skippedIdentical = skippedIdentical
        self.duplicatedConflicts = duplicatedConflicts
    }
}
