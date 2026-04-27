import SwiftUI
import AppKit

class LightPopupController {
    static let shared = LightPopupController()
    private var window: NSWindow?

    func show(isOn: Bool, onToggle: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        dismiss()

        let view = LightPopupView(
            isOn: isOn,
            onToggle: { [weak self] in onToggle(); self?.dismiss() },
            onDismiss: { [weak self] in onDismiss(); self?.dismiss() }
        )

        let w = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 120),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered, defer: false
        )
        w.title = "Meeting Caller"
        w.contentView = NSHostingView(rootView: view)
        w.isFloatingPanel = true
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.hidesOnDeactivate = false

        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - 300
            let y = screen.visibleFrame.maxY - 140
            w.setFrameOrigin(NSPoint(x: x, y: y))
        }

        w.makeKeyAndOrderFront(nil)
        window = w

        // Auto-close after 10s
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.dismiss()
        }
    }

    func dismiss() {
        window?.close()
        window = nil
    }
}

struct LightPopupView: View {
    let isOn: Bool
    let onToggle: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.title2)
                    .foregroundColor(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("M\u{00f8}de startet")
                        .font(.headline)
                    Text("Lys er \(isOn ? "t\u{00e6}ndt" : "slukket")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button { onToggle() } label: {
                    Text(isOn ? "Sluk lys" : "T\u{00e6}nd lys")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                Button { onDismiss() } label: {
                    Text("OK")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
        }
        .padding()
        .frame(width: 280)
    }
}
