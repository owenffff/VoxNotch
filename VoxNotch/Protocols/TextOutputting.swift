//
//  TextOutputting.swift
//  VoxNotch
//
//  Protocol abstracting TextOutputManager for testability.
//

import AppKit

/// Abstraction over text output so QuickDictationController can be tested with mocks.
protocol TextOutputting: AnyObject {
    func hasFocusedTextInput(for app: NSRunningApplication?) -> Bool
    func output(_ text: String) async throws
    func copyToClipboardOnly(_ text: String)
}

extension TextOutputManager: TextOutputting {}
