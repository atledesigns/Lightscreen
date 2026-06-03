import SwiftUI

/// The small card that floats over the window while it auto-scrolls: a label, a
/// progress bar that fills as we travel down the page, and a Stop button to
/// bail out early and keep whatever's been caught so far.
struct ScrollRecorderView: View {
    @ObservedObject var model: ScrollRecorderModel

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                    Text("Catching full page…")
                        .font(.system(size: 12, weight: .medium))
                }
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .frame(width: 150)
            }

            Button {
                model.stopRequested = true
            } label: {
                Text("Stop")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

/// The quick look after a scroll finishes: the stitched tall image scaled to
/// fit, with the option to keep it (on to the editor/preview) or redo the
/// scroll by hand for a tricky page.
struct ScrollResultView: View {
    let image: NSImage
    var onUse: () -> Void
    var onRetry: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Full page caught")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // The tall result, scrollable so a very long page is fully checkable.
            ScrollView {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.05))
            )

            HStack(spacing: 10) {
                Button(action: onRetry) {
                    Label("Retry manually", systemImage: "hand.draw")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)

                Button(action: onUse) {
                    Text("Use This")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

/// The rescue card for pages auto-scroll can't handle: scroll the window
/// yourself, tap Snap at each stop, then Stitch when you reach the bottom.
struct ManualScrollView: View {
    @ObservedObject var model: ManualScrollModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Manual catch")
                    .font(.system(size: 13, weight: .semibold))
                Text("Scroll the window, tap Snap at each stop.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    model.onSnap?()
                } label: {
                    Label("Snap", systemImage: "camera")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)

                Text("\(model.count) caught")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            HStack(spacing: 8) {
                Button("Cancel") { model.onCancel?() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                Button("Stitch \(model.count)") { model.onFinish?() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(model.count < 1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}
