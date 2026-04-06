//
//  TestClock.swift
//  VoxNotchTests
//

import Foundation
@testable import VoxNotch

/// Controllable clock for deterministic tests.
/// Advance time manually with `advance(by:)` to fire scheduled timers.
@MainActor
final class TestClock: AppClock, @unchecked Sendable {

    private(set) var currentDate: Date

    init(now: Date = Date(timeIntervalSinceReferenceDate: 0)) {
        self.currentDate = now
    }

    func now() -> Date {
        currentDate
    }

    // MARK: - Sleep

    private var sleepContinuations: [(duration: TimeInterval, continuation: CheckedContinuation<Void, Error>)] = []

    func sleep(for duration: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sleepContinuations.append((duration, continuation))
        }
    }

    // MARK: - Timers

    private(set) var scheduledTimers: [TestClockTimer] = []

    func scheduleTimer(
        interval: TimeInterval,
        repeats: Bool,
        block: @escaping @MainActor @Sendable () -> Void
    ) -> ClockTimer {
        let timer = TestClockTimer(interval: interval, repeats: repeats, block: block)
        scheduledTimers.append(timer)
        return timer
    }

    // MARK: - Time Control

    /// Advance the clock by `seconds`, firing any timers whose interval has elapsed.
    func advance(by seconds: TimeInterval) {
        currentDate = currentDate.addingTimeInterval(seconds)

        // Fire eligible timers
        for timer in scheduledTimers where !timer.isInvalidated {
            timer.elapsed += seconds
            while timer.elapsed >= timer.interval && !timer.isInvalidated {
                timer.block()
                timer.elapsed -= timer.interval
                if !timer.repeats {
                    timer.invalidate()
                    break
                }
            }
        }

        // Resume eligible sleeps
        let pending = sleepContinuations
        sleepContinuations.removeAll()
        for entry in pending {
            if entry.duration <= seconds {
                entry.continuation.resume()
            } else {
                sleepContinuations.append((entry.duration - seconds, entry.continuation))
            }
        }
    }
}

// MARK: - TestClockTimer

@MainActor
final class TestClockTimer: ClockTimer {
    let interval: TimeInterval
    let repeats: Bool
    let block: @MainActor @Sendable () -> Void
    var elapsed: TimeInterval = 0
    private(set) var isInvalidated = false

    init(interval: TimeInterval, repeats: Bool, block: @escaping @MainActor @Sendable () -> Void) {
        self.interval = interval
        self.repeats = repeats
        self.block = block
    }

    nonisolated func invalidate() {
        // Safe to set from any context — only checked on MainActor in advance(by:)
        MainActor.assumeIsolated {
            isInvalidated = true
        }
    }
}
