import Foundation
import AppKit
import Carbon.HIToolbox

class ModifierKeyMonitor {
    /// Get the current modifier keys as a space-separated string
    func currentModifierString() -> String {
        let flags = NSEvent.modifierFlags
        var parts: [String] = []

        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.option) { parts.append("option") }
        if flags.contains(.command) { parts.append("command") }
        if flags.contains(.control) { parts.append("control") }
        if flags.contains(.function) { parts.append("function") }

        return parts.joined(separator: " ")
    }
}
