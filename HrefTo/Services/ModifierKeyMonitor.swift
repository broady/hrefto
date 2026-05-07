import Foundation
import AppKit
import Carbon.HIToolbox

class ModifierKeyMonitor {
    func currentModifiers() -> Set<String> {
        let flags = NSEvent.modifierFlags
        var modifiers = Set<String>()

        if flags.contains(.shift) { modifiers.insert("shift") }
        if flags.contains(.option) { modifiers.insert("option") }
        if flags.contains(.command) { modifiers.insert("command") }
        if flags.contains(.control) { modifiers.insert("control") }
        if flags.contains(.function) { modifiers.insert("function") }

        return modifiers
    }

    /// Check whether all configured force-picker modifiers are currently held.
    func isBypassModifierActive(_ keys: Set<AppSettings.ModifierKey>) -> Bool {
        guard !keys.isEmpty else { return false }
        let active = currentModifiers()
        return keys.allSatisfy { active.contains($0.rawValue) }
    }

    /// Get the current modifier keys as a space-separated string
    func currentModifierString() -> String {
        let modifiers = currentModifiers()
        let parts = ["shift", "option", "command", "control", "function"].filter { modifiers.contains($0) }
        return parts.joined(separator: " ")
    }
}
