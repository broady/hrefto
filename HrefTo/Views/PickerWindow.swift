import AppKit
import SwiftUI

class PickerWindowController {
    private var panel: NSPanel?
    private var monitor: Any?

    func show(with view: some View) {
        close()  // dismiss any existing picker

        let hostingView = NSHostingView(rootView: view)
        hostingView.setFrameSize(hostingView.fittingSize)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 300),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = hostingView
        panel.isReleasedWhenClosed = false

        // Size to content
        let fittingSize = hostingView.fittingSize
        panel.setContentSize(fittingSize)

        // Position near cursor
        let mouseLocation = NSEvent.mouseLocation
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero

        var origin = NSPoint(
            x: mouseLocation.x - fittingSize.width / 2,
            y: mouseLocation.y + 10
        )

        // Keep on screen
        origin.x = max(screenFrame.minX + 10, min(origin.x, screenFrame.maxX - fittingSize.width - 10))
        origin.y = max(screenFrame.minY + 10, min(origin.y, screenFrame.maxY - fittingSize.height - 10))

        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        panel.makeKey()

        // Dismiss on click outside
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.close()
        }

        // Dismiss on Escape via panel delegate
        panel.delegate = PickerPanelDelegate { [weak self] in
            self?.close()
        }

        self.panel = panel
    }

    func close() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        panel?.close()
        panel = nil
    }
}

private class PickerPanelDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    // Allow Escape to close
    func cancelOperation(_ sender: Any?) {
        onClose()
    }
}
