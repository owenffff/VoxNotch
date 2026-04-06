//
//  SystemClock.swift
//  VoxNotch
//
//  Production implementation of AppClock using Foundation timers.
//

import Foundation

/// Production clock that delegates to real `Date`, `Timer`, and `Task.sleep`.
final class SystemClock: AppClock, @unchecked Sendable {

    func now() -> Date {
        Date()
    }

    func sleep(for duration: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(duration))
    }

    @MainActor
    func scheduleTimer(
        interval: TimeInterval,
        repeats: Bool,
        block: @escaping @MainActor @Sendable () -> Void
    ) -> ClockTimer {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
            Task { @MainActor in
                block()
            }
        }
    }
}
