import SwiftUI

/// The overlay that appears when you press ⌘⇧7.
///
/// A floating Liquid Glass card with three capture buttons and a sticky
/// Beautified ↔ Raw toggle. Tapping anywhere outside the card dismisses it.
/// For Stage 1 the buttons only log to the console — real capture starts in Stage 2.
struct PickerView: View {
    @ObservedObject var outputMode: OutputModeStore
    var onCapture: (CaptureMode) -> Void
    var onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            // A barely-there scrim: gives the glass something to read against
            // when the screen behind is busy or bright. Tapping it dismisses.
            Color.black.opacity(appeared ? 0.14 : 0)
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
                .ignoresSafeArea()

            card
                .scaleEffect(appeared ? 1 : 0.96)
                .offset(y: appeared ? 0 : 8)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                appeared = true
            }
        }
    }

    private var card: some View {
        VStack(spacing: 22) {
            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 16) {
                    ForEach(CaptureMode.offered, id: \.self) { mode in
                        captureButton(mode)
                    }
                }
            }

            OutputModeToggle(mode: $outputMode.mode)

            Text(outputMode.mode.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .id(outputMode.mode)
                .transition(.blurReplace)
        }
        .padding(28)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        // Swallow taps on the card so they don't reach the dismiss scrim.
        .onTapGesture { }
        .frame(maxWidth: 440)
    }

    private func captureButton(_ mode: CaptureMode) -> some View {
        CaptureButton(mode: mode) { onCapture(mode) }
    }
}

/// One capture-mode button. Lifts and brightens slightly under the pointer
/// so the trio feels alive on a desktop where hover is real.
private struct CaptureButton: View {
    let mode: CaptureMode
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 26, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                Text(mode.label)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(width: 100, height: 92)
            .contentShape(Rectangle())
        }
        .buttonStyle(.glass)
        .scaleEffect(hovering ? 1.04 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// A two-segment pill that slides a tinted highlight between Beautified and Raw.
private struct OutputModeToggle: View {
    @Binding var mode: OutputMode
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 4) {
            segment(.beautified)
            segment(.raw)
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }

    private func segment(_ value: OutputMode) -> some View {
        let isSelected = mode == value
        return Button {
            withAnimation(.snappy(duration: 0.28)) { mode = value }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: value.symbolName)
                Text(value.label)
            }
            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            .padding(.vertical, 8)
            .padding(.horizontal, 18)
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .background {
                if isSelected {
                    Capsule()
                        .fill(.tint.opacity(0.28))
                        .matchedGeometryEffect(id: "selection", in: highlight)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
