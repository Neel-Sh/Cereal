import AppKit
import SwiftUI

enum CallPromptKind {
    case start, end
}

/// A small floating window in the top-right corner that appears over every app and Space
/// without taking focus from the call.
@MainActor
final class CallPromptPanel {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private(set) var kind: CallPromptKind?

    func show(_ content: CallPromptView, kind: CallPromptKind, dismissAfter seconds: TimeInterval) {
        dismiss()
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.contentView = hosting
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 16, y: screen.maxY - size.height - 16))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        self.panel = panel
        self.kind = kind
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel = nil
        kind = nil
    }
}

struct CallPromptView: View {
    let kind: CallPromptKind
    let app: MicrophoneUser
    let eventTitle: String?
    let primary: () -> Void
    let secondary: () -> Void
    let ignore: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 11) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 42, height: 42)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CEREAL")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let ignore {
                    Menu {
                        Button("Don’t ask for \(app.name)", action: ignore)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Call options")
                }
            }

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(action: primary) {
                    Label(kind == .start ? "Record" : "Stop & Save",
                          systemImage: kind == .start ? "record.circle" : "stop.fill")
                }
                .buttonStyle(PromptButtonStyle(prominent: true))
                Button(kind == .start ? "Not now" : "Keep recording", action: secondary)
                    .buttonStyle(PromptButtonStyle(prominent: false))
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .padding(8)
    }

    private var title: String {
        switch kind {
        case .start: eventTitle.map { "Record “\($0)”?" } ?? "Record this call?"
        case .end: "Call ended?"
        }
    }

    private var subtitle: String {
        switch kind {
        case .start: "\(app.name) is using your microphone. Cereal can take notes."
        case .end: "\(app.name) stopped using the microphone. Save the recording?"
        }
    }

    /// Drawn by hand because system button styles render dimmed in a panel that never becomes key.
    private struct PromptButtonStyle: ButtonStyle {
        let prominent: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(prominent ? .white : .primary)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(prominent ? AnyShapeStyle(Color.red) : AnyShapeStyle(.white.opacity(0.14)), in: Capsule())
                .opacity(configuration.isPressed ? 0.75 : 1)
                .contentShape(Capsule())
        }
    }

}
