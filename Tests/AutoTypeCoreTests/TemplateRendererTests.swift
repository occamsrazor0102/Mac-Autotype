import Foundation
import Testing
@testable import AutoTypeCore

@Test func discoversPromptedPlaceholdersOnceAndExcludesBuiltIns() throws {
    let parsed = try TemplateRenderer().parse("Hello {{name}}, {{name}} — {{date}}")
    #expect(parsed.promptedPlaceholders == ["name"])
}

@Test func rendersValuesBuiltInsAndEscapedDelimiter() throws {
    let rendered = try TemplateRenderer().render(
        "Hi {{name}} on {{date}} at {{time}}; literal: \\{{name}}",
        values: ["name": "Sam"],
        date: Date(timeIntervalSince1970: 0),
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: TimeZone(secondsFromGMT: 0)!
    )

    #expect(rendered == "Hi Sam on 1/1/70 at 12:00\u{202F}AM; literal: {{name}}")
}

@Test func allowsExplicitlyEmptyTemplateValues() throws {
    #expect(try TemplateRenderer().render("A{{value}}B", values: ["value": ""]) == "AB")
}

@Test func rejectsMalformedAndMissingTemplateValues() {
    #expect(throws: TemplateError.invalidIdentifier("not valid")) {
        try TemplateRenderer().parse("{{not valid}}")
    }
    #expect(throws: TemplateError.unclosedPlaceholder) {
        try TemplateRenderer().parse("{{name")
    }
    #expect(throws: TemplateError.missingValue("name")) {
        try TemplateRenderer().render("{{name}}", values: [:])
    }
}
