//
//  AppClock.swift
//  VoxNotch
//
//  Protocol abstracting time and timers for testability.
//

import Foundation

/// A timer handle that can be invalidated.
protocol ClockTimer: AnyObject {
    func invalidate()
}

extension Timer: ClockTimer {}

/// Abstraction over `Date`, `Timer`, and `Task.sleep` so time-dependent
/// code (state machine timers, cooldowns) can be tested deterministically.
protocol AppClock: Sendable {
    /// Returns the current date (replaces `Date()`).
    func now() -> Date

    /// Suspends the current task for `duration` seconds (replaces `Task.sleep`).
    func sleep(for duration: TimeInterval) async throws

    /// Schedules a repeating or one-shot timer (replaces `Timer.scheduledTimer`).
    /// Returns a `ClockTimer` handle whose `invalidate()` cancels the timer.
    @MainActor func scheduleTimer(
        interval: TimeInterval,
        repeats: Bool,
        block: @escaping @MainActor @Sendable () -> Void
    ) -> ClockTimer
}
