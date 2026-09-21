#if os(iOS)
import Testing
import UIKit

@testable import SwiftTerm

/// A hardware keyboard on an iPad (IPAD_PLAN.md, items 3.5 and 3.6).
///
/// A real key press cannot be made in a test — `UIKey` has no public
/// initialiser — so these check the parts of the path that decide what reaches
/// the far end: the function-key table, and the text-input traits that keep
/// the system from typing on the user's behalf.
@MainActor
@Suite("iOS hardware keyboard")
struct iOSKeyboardTests {
    @Test("F1 to F12 send the same sequences as on the Mac, each its own")
    func functionKeys() {
        let keys: [UIKeyboardHIDUsage] = [
            .keyboardF1, .keyboardF2, .keyboardF3, .keyboardF4, .keyboardF5, .keyboardF6,
            .keyboardF7, .keyboardF8, .keyboardF9, .keyboardF10, .keyboardF11, .keyboardF12,
        ]
        let sent = keys.map { TerminalView.functionKeySequence(for: $0) }
        #expect(sent == EscapeSequences.cmdF.map { Optional($0) })
        // F10 once sent F9's sequence; a duplicate anywhere is that bug again.
        #expect(Set(sent.compactMap { $0 }).count == 12)
        #expect(TerminalView.functionKeySequence(for: .keyboardF13) == nil)
        #expect(TerminalView.functionKeySequence(for: .keyboardA) == nil)
    }

    @Test("Nothing the system suggests is typed into the terminal")
    func noSystemTyping() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(view.autocorrectionType == .no)
        #expect(view.autocapitalizationType == .none)
        #expect(view.spellCheckingType == .no)
        #expect(view.smartQuotesType == .no)
        #expect(view.smartDashesType == .no)
        #expect(view.smartInsertDeleteType == .no)
        if #available(iOS 17.0, *) {
            #expect(view.inlinePredictionType == .no)
        }
        if #available(iOS 18.0, *) {
            #expect(view.writingToolsBehavior == .none)
        }
    }
}
#endif
