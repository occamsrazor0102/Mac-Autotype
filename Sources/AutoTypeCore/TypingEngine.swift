import Foundation

public protocol TypingEventSink: Sendable {
    func sendUnicode(_ text: String) async throws
    func sendPhysical(_ text: String) async throws -> Bool
    func sendSpecialKey(_ key: SpecialKey) async throws
}

public protocol TypingSafetyMonitoring: Sendable {
    func status(for target: TargetApplication) async -> TargetSafetyStatus
}

public protocol TypingClock: Sendable {
    func sleep(seconds: TimeInterval) async throws
}

public struct SystemTypingClock: TypingClock {
    public init() {}

    public func sleep(seconds: TimeInterval) async throws {
        guard seconds > 0 else {
            try Task.checkCancellation()
            return
        }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

public enum TypingEngineError: LocalizedError, Equatable, Sendable {
    case alreadyRunning
    case emptyText
    case textTooLarge

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning: "A typing job is already active."
        case .emptyText: "Enter text before starting AutoType."
        case .textTooLarge: "AutoType limits each run to 1 MB of UTF-8 text."
        }
    }
}

private enum TypingUnit: Sendable {
    case text(String)
    case special(SpecialKey)

    var isReturn: Bool {
        if case .special(.returnKey) = self { return true }
        return false
    }
}

public actor TypingEngine {
    public static let maximumTextBytes = 1 * 1_024 * 1_024

    public typealias StateHandler = @Sendable (TypingState) async -> Void

    private let eventSink: TypingEventSink
    private let safetyMonitor: TypingSafetyMonitoring
    private let clock: TypingClock
    private let stateHandler: StateHandler

    private var jobTask: Task<Void, Never>?
    private var currentJob: TypingJob?
    private var currentProgress: TypingProgress?
    private var paused = false
    private var pauseContinuation: CheckedContinuation<Void, Never>?

    public private(set) var state: TypingState = .idle

    public init(
        eventSink: TypingEventSink,
        safetyMonitor: TypingSafetyMonitoring,
        clock: TypingClock = SystemTypingClock(),
        stateHandler: @escaping StateHandler = { _ in }
    ) {
        self.eventSink = eventSink
        self.safetyMonitor = safetyMonitor
        self.clock = clock
        self.stateHandler = stateHandler
    }

    public func start(_ job: TypingJob) throws {
        guard jobTask == nil else { throw TypingEngineError.alreadyRunning }
        guard job.text.lengthOfBytes(using: .utf8) <= Self.maximumTextBytes else {
            throw TypingEngineError.textTooLarge
        }

        let units = Self.units(for: job.text, tabBehavior: job.configuration.tabBehavior)
        guard !units.isEmpty else { throw TypingEngineError.emptyText }

        currentJob = job
        paused = false
        let progress = TypingProgress(
            completedUnits: 0,
            totalUnits: units.count * job.configuration.repeatCount,
            repeatIndex: 1,
            repeatCount: job.configuration.repeatCount,
            unicodeFallbacks: 0
        )
        currentProgress = progress

        jobTask = Task { [weak self] in
            await self?.run(job: job, units: units)
        }
    }

    public func pause() async {
        guard jobTask != nil, !paused, let progress = currentProgress else { return }
        guard case .typing = state else { return }
        paused = true
        await publish(.paused(reason: .user, progress: progress))
    }

    @discardableResult
    public func resume() async -> Bool {
        guard paused, let job = currentJob, let progress = currentProgress else { return false }

        let safety = await safetyMonitor.status(for: job.target)
        guard safety == .safe else {
            await publish(.paused(reason: pauseReason(for: safety, target: job.target), progress: progress))
            return false
        }

        paused = false
        await publish(.typing(progress))
        let continuation = pauseContinuation
        pauseContinuation = nil
        continuation?.resume()
        return true
    }

    public func stop() {
        guard let jobTask else { return }
        jobTask.cancel()
        paused = false
        let continuation = pauseContinuation
        pauseContinuation = nil
        continuation?.resume()
    }

    private func run(job: TypingJob, units: [TypingUnit]) async {
        var progress = currentProgress!

        do {
            var countdownRemaining = job.configuration.startDelay
            while countdownRemaining > 0.000_001 {
                try Task.checkCancellation()
                await publish(.countdown(secondsRemaining: Int(ceil(countdownRemaining))))
                let step = min(countdownRemaining, 1)
                try await clock.sleep(seconds: step)
                countdownRemaining -= step
            }

            await publish(.typing(progress))
            let characterDelay = 1 / job.configuration.charactersPerSecond

            for repeatIndex in 1...job.configuration.repeatCount {
                for unit in units {
                    try Task.checkCancellation()
                    await waitWhilePaused()
                    try Task.checkCancellation()

                    let safety = await safetyMonitor.status(for: job.target)
                    if safety != .safe {
                        await pauseForSafety(safety, job: job, progress: progress)
                        await waitWhilePaused()
                        try Task.checkCancellation()
                    }
                    await waitWhilePaused()
                    try Task.checkCancellation()

                    var fallbackCount = progress.unicodeFallbacks
                    switch unit {
                    case let .text(text):
                        switch job.configuration.inputMode {
                        case .unicode:
                            try await eventSink.sendUnicode(text)
                        case .physical:
                            if try await !eventSink.sendPhysical(text) {
                                try await eventSink.sendUnicode(text)
                                fallbackCount += 1
                            }
                        }
                    case let .special(key):
                        try await eventSink.sendSpecialKey(key)
                    }

                    progress = TypingProgress(
                        completedUnits: progress.completedUnits + 1,
                        totalUnits: progress.totalUnits,
                        repeatIndex: repeatIndex,
                        repeatCount: progress.repeatCount,
                        unicodeFallbacks: fallbackCount
                    )
                    currentProgress = progress
                    await publish(.typing(progress))

                    let delay = characterDelay + (unit.isReturn ? job.configuration.lineDelay : 0)
                    try await clock.sleep(seconds: delay)
                }

                if repeatIndex < job.configuration.repeatCount {
                    try await clock.sleep(seconds: job.configuration.repeatInterval)
                }
            }

            await publish(.completed(progress))
        } catch is CancellationError {
            await publish(.cancelled(currentProgress))
        } catch {
            await publish(.failed(message: error.localizedDescription, progress: currentProgress))
        }

        currentJob = nil
        currentProgress = nil
        paused = false
        pauseContinuation = nil
        jobTask = nil
    }

    private func pauseForSafety(
        _ safety: TargetSafetyStatus,
        job: TypingJob,
        progress: TypingProgress
    ) async {
        paused = true
        await publish(.paused(reason: pauseReason(for: safety, target: job.target), progress: progress))
    }

    private func pauseReason(for status: TargetSafetyStatus, target: TargetApplication) -> PauseReason {
        switch status {
        case .safe:
            .user
        case .focusChanged:
            .focusChanged(expectedApplication: target.name)
        case .secureField:
            .secureField
        case .accessibilityPermissionLost:
            .accessibilityPermissionLost
        case .targetTerminated:
            .targetTerminated
        }
    }

    private func waitWhilePaused() async {
        guard paused else { return }
        await withCheckedContinuation { continuation in
            if paused {
                pauseContinuation = continuation
            } else {
                continuation.resume()
            }
        }
    }

    private func publish(_ newState: TypingState) async {
        state = newState
        await stateHandler(newState)
    }

    private static func units(for text: String, tabBehavior: TabBehavior) -> [TypingUnit] {
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var units: [TypingUnit] = []
        units.reserveCapacity(normalizedText.count)

        for character in normalizedText {
            switch character {
            case "\n":
                units.append(.special(.returnKey))
            case "\t":
                switch tabBehavior {
                case let .spaces(count):
                    units.append(contentsOf: Array(repeating: .text(" "), count: count))
                case .physical:
                    units.append(.special(.tab))
                case .skip:
                    break
                }
            default:
                units.append(.text(String(character)))
            }
        }

        return units
    }
}
