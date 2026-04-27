import SwiftUI
import AppKit

class StopPopupController {
    static let shared = StopPopupController()
    private var window: NSWindow?
    private var autoCloseTimer: Timer?

    func show(timeText: String, onStop: @escaping () -> Void, onPause: @escaping () -> Void) {
        dismiss()

        let view = StopPopupView(
            timeText: timeText,
            onStop: { [weak self] in onStop(); self?.dismiss() },
            onPause: { [weak self] in onPause(); self?.dismiss() },
            onDismiss: { [weak self] in self?.dismiss() }
        )

        let w = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 140),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        w.title = "Meeting Caller"
        w.contentView = NSHostingView(rootView: view)
        w.isFloatingPanel = true
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.hidesOnDeactivate = false

        // Position top-right, below menu bar
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - 340
            let y = screen.visibleFrame.maxY - 160
            w.setFrameOrigin(NSPoint(x: x, y: y))
        }

        w.makeKeyAndOrderFront(nil)
        window = w
        NSSound.beep()

        // Auto-close after 30s if no action
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        window?.close()
        window = nil
    }
}

struct StopPopupView: View {
    let timeText: String
    let onStop: () -> Void
    let onPause: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "video.slash")
                    .font(.title2)
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kamera slukket")
                        .font(.headline)
                    Text("Slukket i \(timeText). Hvad vil du g\u{00f8}re?")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button(role: .destructive) { onStop() } label: {
                    Text("Stop m\u{00f8}de")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                Button { onPause() } label: {
                    Text("Pause")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                Button { onDismiss() } label: {
                    Text("Behold")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
        }
        .padding()
        .frame(width: 320)
    }
}
