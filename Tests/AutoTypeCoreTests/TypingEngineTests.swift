import Foundation
import Testing
@testable import AutoTypeCore

@Test func unicodeTypingPreservesGraphemesNewlinesAndConfiguredTabs() async throws {
    let sink = RecordingEventSink()
    let states = StateRecorder()
    let engine = TypingEngine(
        eventSink: sink,
        safetyMonitor: MutableSafetyMonitor(status: .safe),
        clock: YieldingClock(),
        stateHandler: { await states.record($0) }
    )
    let configuration = TypingConfiguration(
        inputMode: .unicode,
        tabBehavior: .spaces(2),
        startDelay: 0,
        charactersPerSecond: 100,
        lineDelay: 0,
        repeatCount: 1,
        repeatInterval: 0
    )

    try await engine.start(TypingJob(text: "A\t👩🏽‍💻\nB", target: .testTarget, configuration: configuration))
    try await waitForTerminalState(states)

    #expect(await sink.events() == [.unicode("A"), .unicode(" "), .unicode(" "), .unicode("👩🏽‍💻"), .special(.returnKey), .unicode("B")])
    guard case let .completed(progress) = await engine.state else {
        Issue.record("Expected a completed state")
        return
    }
    #expect(progress.completedUnits == 6)
    #expect(progress.fractionCompleted == 1)
}

@Test func physicalModeFallsBackToUnicodeWithoutSubstitution() async throws {
    let sink = RecordingEventSink(unsupportedPhysicalText: ["é"])
    let states = StateRecorder()
    let engine = TypingEngine(
        eventSink: sink,
        safetyMonitor: MutableSafetyMonitor(status: .safe),
        clock: YieldingClock(),
        stateHandler: { await states.record($0) }
    )
    let configuration = TypingConfiguration(inputMode: .physical, startDelay: 0, charactersPerSecond: 100)

    try await engine.start(TypingJob(text: "aé", target: .testTarget, configuration: configuration))
    try await waitForTerminalState(states)

    #expect(await sink.events() == [.physical("a"), .physicalAttempt("é"), .unicode("é")])
    guard case let .completed(progress) = await engine.state else {
        Issue.record("Expected a completed state")
        return
    }
    #expect(progress.unicodeFallbacks == 1)
}

@Test func focusLossPausesUntilExplicitSafeResume() async throws {
    let sink = RecordingEventSink()
    let safety = MutableSafetyMonitor(status: .focusChanged)
    let states = StateRecorder()
    let engine = TypingEngine(
        eventSink: sink,
        safetyMonitor: safety,
        clock: YieldingClock(),
        stateHandler: { await states.record($0) }
    )
    let configuration = TypingConfiguration(startDelay: 0, charactersPerSecond: 100)

    try await engine.start(TypingJob(text: "x", target: .testTarget, configuration: configuration))
    try await waitForPausedState(states)
    #expect(await sink.events() == [])
    #expect(await engine.resume() == false)

    await safety.setStatus(.safe)
    #expect(await engine.resume())
    try await waitForTerminalState(states)
    #expect(await sink.events() == [.unicode("x")])
}

@Test func stopCancelsCountdownBeforeAnyInput() async throws {
    let sink = RecordingEventSink()
    let states = StateRecorder()
    let engine = TypingEngine(
        eventSink: sink,
        safetyMonitor: MutableSafetyMonitor(status: .safe),
        clock: BlockingClock(),
        stateHandler: { await states.record($0) }
    )

    try await engine.start(TypingJob(text: "never", target: .testTarget, configuration: .default))
    try await waitForCountdownState(states)
    await engine.stop()
    try await waitForTerminalState(states)

    #expect(await sink.events() == [])
    guard case .cancelled = await engine.state else {
        Issue.record("Expected cancellation")
        return
    }
}

@Test func fractionalCountdownSleepsForExactlyTheConfiguredDelay() async throws {
    let sink = RecordingEventSink()
    let clock = RecordingClock()
    let states = StateRecorder()
    let engine = TypingEngine(
        eventSink: sink,
        safetyMonitor: MutableSafetyMonitor(status: .safe),
        clock: clock,
        stateHandler: { await states.record($0) }
    )
    let configuration = TypingConfiguration(startDelay: 1.25, charactersPerSecond: 100)

    try await engine.start(TypingJob(text: "x", target: .testTarget, configuration: configuration))
    try await waitForTerminalState(states)

    let sleeps = await clock.values()
    #expect(sleeps.count == 3)
    #expect(abs(sleeps[0] - 1) < 0.000_001)
    #expect(abs(sleeps[1] - 0.25) < 0.000_001)
    #expect(abs(sleeps[2] - 0.01) < 0.000_001)
    #expect(await states.countdownValues() == [2, 1])
}

@Test func pauseDuringCountdownIsIgnoredAndStopStillCancels() async throws {
    let sink = RecordingEventSink()
    let states = StateRecorder()
    let engine = TypingEngine(
        eventSink: sink,
        safetyMonitor: MutableSafetyMonitor(status: .safe),
        clock: BlockingClock(),
        stateHandler: { await states.record($0) }
    )

    try await engine.start(TypingJob(text: "never", target: .testTarget, configuration: .default))
    try await waitForCountdownState(states)
    await engine.pause()
    guard case .countdown = await engine.state else {
        Issue.record("Expected the countdown to remain active")
        return
    }

    await engine.stop()
    try await waitForTerminalState(states)
    #expect(await sink.events() == [])
}

@Test func rejectsRunsLargerThanOneMegabyteBeforeCreatingEvents() async {
    let sink = RecordingEventSink()
    let engine = TypingEngine(
        eventSink: sink,
        safetyMonitor: MutableSafetyMonitor(status: .safe),
        clock: YieldingClock()
    )
    let oversizedText = String(repeating: "a", count: TypingEngine.maximumTextBytes + 1)

    await #expect(throws: TypingEngineError.textTooLarge) {
        try await engine.start(TypingJob(text: oversizedText, target: .testTarget, configuration: .default))
    }
    #expect(await sink.events() == [])
}

private func waitForTerminalState(_ recorder: StateRecorder) async throws {
    try await eventually {
        await recorder.states().contains { state in
            switch state {
            case .completed, .cancelled, .failed: true
            default: false
            }
        }
    }
}

private func waitForPausedState(_ recorder: StateRecorder) async throws {
    try await eventually { await recorder.states().contains { if case .paused = $0 { true } else { false } } }
}

private func waitForCountdownState(_ recorder: StateRecorder) async throws {
    try await eventually { await recorder.states().contains { if case .countdown = $0 { true } else { false } } }
}

private enum TestTimeout: Error { case elapsed }

private func eventually(_ predicate: @escaping () async -> Bool) async throws {
    for _ in 0..<500 {
        if await predicate() { return }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    throw TestTimeout.elapsed
}

private enum RecordedEvent: Equatable {
    case unicode(String)
    case physical(String)
    case physicalAttempt(String)
    case special(SpecialKey)
}

private actor RecordingEventSink: TypingEventSink {
    private var recorded: [RecordedEvent] = []
    private let unsupportedPhysicalText: Set<String>

    init(unsupportedPhysicalText: Set<String> = []) {
        self.unsupportedPhysicalText = unsupportedPhysicalText
    }

    func sendUnicode(_ text: String) { recorded.append(.unicode(text)) }

    func sendPhysical(_ text: String) -> Bool {
        if unsupportedPhysicalText.contains(text) {
            recorded.append(.physicalAttempt(text))
            return false
        }
        recorded.append(.physical(text))
        return true
    }

    func sendSpecialKey(_ key: SpecialKey) { recorded.append(.special(key)) }
    func events() -> [RecordedEvent] { recorded }
}

private actor MutableSafetyMonitor: TypingSafetyMonitoring {
    private var currentStatus: TargetSafetyStatus

    init(status: TargetSafetyStatus) { currentStatus = status }
    func status(for target: TargetApplication) -> TargetSafetyStatus { currentStatus }
    func setStatus(_ status: TargetSafetyStatus) { currentStatus = status }
}

private struct YieldingClock: TypingClock {
    func sleep(seconds: TimeInterval) async throws {
        try Task.checkCancellation()
        await Task.yield()
    }
}

private struct BlockingClock: TypingClock {
    func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: 60_000_000_000)
    }
}

private actor RecordingClock: TypingClock {
    private var recorded: [TimeInterval] = []

    func sleep(seconds: TimeInterval) {
        recorded.append(seconds)
    }

    func values() -> [TimeInterval] { recorded }
}

private actor StateRecorder {
    private var recorded: [TypingState] = []
    func record(_ state: TypingState) { recorded.append(state) }
    func states() -> [TypingState] { recorded }
    func countdownValues() -> [Int] {
        recorded.compactMap { state in
            if case let .countdown(seconds) = state { seconds } else { nil }
        }
    }
}

private extension TargetApplication {
    static let testTarget = TargetApplication(processIdentifier: 42, bundleIdentifier: "test.app", name: "Test App")
}
