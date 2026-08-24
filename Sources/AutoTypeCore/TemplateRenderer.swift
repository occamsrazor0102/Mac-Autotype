import Foundation

public enum TemplateError: LocalizedError, Equatable, Sendable {
    case unclosedPlaceholder
    case invalidIdentifier(String)
    case missingValue(String)

    public var errorDescription: String? {
        switch self {
        case .unclosedPlaceholder:
            "A template placeholder is missing its closing braces."
        case let .invalidIdentifier(identifier):
            "Invalid template placeholder: {{\(identifier)}}. Use letters, numbers, underscores, or hyphens."
        case let .missingValue(identifier):
            "No value was provided for {{\(identifier)}}."
        }
    }
}

public enum TemplateToken: Equatable, Sendable {
    case text(String)
    case placeholder(String)
}

public struct ParsedTemplate: Equatable, Sendable {
    public let tokens: [TemplateToken]
    public let promptedPlaceholders: [String]

    public init(tokens: [TemplateToken], promptedPlaceholders: [String]) {
        self.tokens = tokens
        self.promptedPlaceholders = promptedPlaceholders
    }
}

public struct TemplateRenderer: Sendable {
    public static let builtInIdentifiers: Set<String> = ["date", "time", "datetime"]

    public init() {}

    public func parse(_ template: String) throws -> ParsedTemplate {
        var tokens: [TemplateToken] = []
        var textBuffer = ""
        var prompted: [String] = []
        var seenPrompted = Set<String>()
        var index = template.startIndex

        func flushText() {
            guard !textBuffer.isEmpty else { return }
            tokens.append(.text(textBuffer))
            textBuffer.removeAll(keepingCapacity: true)
        }

        while index < template.endIndex {
            if template[index] == "\\" {
                let next = template.index(after: index)
                if next < template.endIndex, template[next...].hasPrefix("{{") {
                    textBuffer.append("{{")
                    index = template.index(next, offsetBy: 2)
                    continue
                }
            }

            if template[index...].hasPrefix("{{") {
                flushText()
                let contentStart = template.index(index, offsetBy: 2)
                guard let closingRange = template.range(of: "}}", range: contentStart..<template.endIndex) else {
                    throw TemplateError.unclosedPlaceholder
                }

                let identifier = String(template[contentStart..<closingRange.lowerBound])
                guard Self.isValidIdentifier(identifier) else {
                    throw TemplateError.invalidIdentifier(identifier)
                }

                tokens.append(.placeholder(identifier))
                if !Self.builtInIdentifiers.contains(identifier), seenPrompted.insert(identifier).inserted {
                    prompted.append(identifier)
                }
                index = closingRange.upperBound
                continue
            }

            textBuffer.append(template[index])
            index = template.index(after: index)
        }

        flushText()
        return ParsedTemplate(tokens: tokens, promptedPlaceholders: prompted)
    }

    public func render(
        _ parsedTemplate: ParsedTemplate,
        values: [String: String],
        date: Date = Date(),
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) throws -> String {
        var rendered = ""
        let builtIns = Self.builtInValues(date: date, locale: locale, timeZone: timeZone)

        for token in parsedTemplate.tokens {
            switch token {
            case let .text(text):
                rendered.append(text)
            case let .placeholder(identifier):
                if let value = builtIns[identifier] {
                    rendered.append(value)
                } else if let value = values[identifier] {
                    rendered.append(value)
                } else {
                    throw TemplateError.missingValue(identifier)
                }
            }
        }

        return rendered
    }

    public func render(
        _ template: String,
        values: [String: String],
        date: Date = Date(),
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) throws -> String {
        try render(parse(template), values: values, date: date, locale: locale, timeZone: timeZone)
    }

    private static func isValidIdentifier(_ identifier: String) -> Bool {
        guard !identifier.isEmpty else { return false }
        return identifier.range(of: "^[A-Za-z][A-Za-z0-9_-]*$", options: .regularExpression) != nil
    }

    private static func builtInValues(date: Date, locale: Locale, timeZone: TimeZone) -> [String: String] {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = timeZone
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = timeZone
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.locale = locale
        dateTimeFormatter.timeZone = timeZone
        dateTimeFormatter.dateStyle = .short
        dateTimeFormatter.timeStyle = .short

        return [
            "date": dateFormatter.string(from: date),
            "time": timeFormatter.string(from: date),
            "datetime": dateTimeFormatter.string(from: date)
        ]
    }
}
