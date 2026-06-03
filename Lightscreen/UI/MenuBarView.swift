import SwiftUI

/// The dropdown that appears under the menu bar icon. Three direct capture
/// buttons up top, then quick links to the library, settings, and quit.
/// Captures here inherit the session's sticky Raw/Beautified mode — no toggle.
struct MenuBarView: View {
    var onCapture: (CaptureMode) -> Void
    var onShowLibrary: () -> Void
    var onSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(CaptureMode.allCases, id: \.self) { mode in
                        captureButton(mode)
                    }
                }
            }

            Divider()

            VStack(spacing: 2) {
                MenuRow(title: "Show Library", icon: "photo.on.rectangle", action: onShowLibrary)
                MenuRow(title: "Settings…", icon: "gearshape", action: onSettings)
                MenuRow(title: "Quit Lightscreen", icon: "power", action: onQuit)
            }
        }
        .padding(14)
        .frame(width: 264)
    }

    private func captureButton(_ mode: CaptureMode) -> some View {
        Button {
            onCapture(mode)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 20, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                Text(mode.label)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(width: 72, height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.glass)
    }
}

/// A full-width row in the lower menu, with a soft hover highlight.
private struct MenuRow: View {
    let title: String
    let icon: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(title)
                Spacer()
            }
            .font(.system(size: 13))
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(hovering ? Color.primary.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Temporary contents for the Library and Settings windows until their real
/// stages land.
struct PlaceholderView: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
