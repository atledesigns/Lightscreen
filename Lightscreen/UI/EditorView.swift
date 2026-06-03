import SwiftUI

/// The Beautify editor: a big live canvas on the left, a column of controls on
/// the right, and a slim top bar with the filename, a way back, and Save. Every
/// control change repaints the canvas instantly — there's no Apply button.
struct EditorView: View {
    @ObservedObject var model: EditorModel
    @State private var showingSave = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                canvas
                Divider()
                sidebar
                    .frame(width: 288)
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        // Repaint whenever any knob moves.
        .onChange(of: model.draft) { model.rerender() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                model.onClose?()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Back")

            TextField("Name", text: $model.name)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: 320)

            Spacer()

            Button {
                showingSave = true
            } label: {
                Text("Save")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
            .popover(isPresented: $showingSave, arrowEdge: .bottom) {
                SavePopoverView(
                    initialName: model.name,
                    recents: model.recents.recents(),
                    onSave: { name, tags, choice in
                        // On success the window closes itself; on a cancelled
                        // folder pick we keep the sheet open to try again.
                        if model.commit(name: name, tags: tags, choice: choice) {
                            showingSave = false
                        }
                    },
                    onCancel: { showingSave = false }
                )
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    // MARK: - Canvas

    private var canvas: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            Group {
                if let rendered = model.rendered {
                    ZStack {
                        // Behind a transparent backdrop, show a checkerboard so
                        // see-through areas are obvious.
                        if model.showsTransparencyCheckerboard {
                            Checkerboard()
                                .aspectRatio(rendered.size.width / rendered.size.height, contentMode: .fit)
                        }
                        Image(nsImage: rendered)
                            .resizable()
                            .scaledToFit()
                    }
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                    .padding(32)
                } else {
                    ProgressView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                backgroundSection
                imageSection
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var backgroundSection: some View {
        section("Background") {
            Picker("", selection: $model.draft.backgroundKind) {
                ForEach(BeautifyDraft.BackgroundKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch model.draft.backgroundKind {
            case .gradient:
                ColorPicker("First color", selection: $model.draft.color1, supportsOpacity: false)
                ColorPicker("Second color", selection: $model.draft.color2, supportsOpacity: false)
                slider("Angle", value: $model.draft.angle, range: 0...360, unit: "°")
            case .solid:
                ColorPicker("Color", selection: $model.draft.color1, supportsOpacity: false)
            case .transparent:
                Text("Saved as a transparent PNG.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var imageSection: some View {
        section("Image") {
            slider("Padding", value: $model.draft.paddingPercent, range: 0...25, unit: "%")

            Toggle("Shadow", isOn: $model.draft.shadowEnabled)
                .toggleStyle(.switch)
            if model.draft.shadowEnabled {
                slider("Softness", value: $model.draft.shadowBlur, range: 0...120, unit: "px")
                slider("Strength", value: $model.draft.shadowOpacity, range: 0...0.6, unit: "", scale: 100)
            }

            slider("Corners", value: $model.draft.cornerRadius, range: 0...32, unit: "px")
        }
    }

    // MARK: - Small building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    /// A labelled slider with its current value shown on the right. `scale`
    /// multiplies the number for display only (e.g. show 0–0.6 opacity as 0–60).
    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, scale: Double = 1) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 13))
                Spacer()
                Text("\(Int((value.wrappedValue * scale).rounded()))\(unit)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }
}

/// A simple grey/white checkerboard, the universal "this is transparent" cue.
private struct Checkerboard: View {
    var square: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let cols = Int((size.width / square).rounded(.up))
            let rows = Int((size.height / square).rounded(.up))
            for row in 0..<rows {
                for col in 0..<cols {
                    if (row + col).isMultiple(of: 2) { continue }
                    let rect = CGRect(x: CGFloat(col) * square, y: CGFloat(row) * square, width: square, height: square)
                    context.fill(Path(rect), with: .color(.gray.opacity(0.28)))
                }
            }
        }
        .background(Color.white.opacity(0.9))
    }
}
