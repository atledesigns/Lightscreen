import SwiftUI
import UniformTypeIdentifiers

/// The Library window: every shot you've taken, laid out as a date-grouped grid
/// you can search, sort, hover for quick actions, and drag straight out into
/// other apps. The first place you *see* your whole library without opening
/// Finder. ⌘/⇧-click to multi-select; a bar slides up to move or release them
/// in a batch.
struct LibraryView: View {
    @ObservedObject var model: LibraryModel

    @State private var confirmingDelete = false

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.5)

            if model.showReviewBanner {
                reviewBanner
                Divider().opacity(0.5)
            }

            if model.isEmpty {
                emptyState
            } else {
                grid
            }

            Divider().opacity(0.5)
            statusBar
        }
        .frame(minWidth: 640, minHeight: 460)
        .background(.background)
        // The bulk action bar slides up from the bottom over everything.
        .overlay(alignment: .bottom) {
            if model.selectionActive {
                bulkActionBar
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.85), value: model.selectionActive)
        .animation(.spring(response: 0.34, dampingFraction: 0.85), value: model.showReviewBanner)
        // Keyboard: ⌘A selects all, Esc clears. Hidden buttons so the shortcuts
        // work window-wide without stealing layout.
        .background(keyboardShortcuts)
        .confirmationDialog(
            "Delete \(model.selectedCount) \(model.selectedCount == 1 ? "catch" : "catches")?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { model.deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes them from your library for good.")
        }
    }

    // MARK: - Keyboard shortcuts (invisible)

    private var keyboardShortcuts: some View {
        ZStack {
            Button("") { model.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
            Button("") { model.clearSelection() }
                .keyboardShortcut(.cancelAction)
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            searchField
            Spacer(minLength: 8)
            sortMenu
            viewModeMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.top, 4) // clear the transparent titlebar
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12, weight: .medium))
            TextField("Search by name", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 280)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $model.sort) {
                ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label(model.sort.rawValue, systemImage: "arrow.up.arrow.down")
                .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var viewModeMenu: some View {
        Menu {
            Picker("View", selection: $model.viewMode) {
                ForEach(LibraryViewMode.allCases) {
                    Label($0.rawValue, systemImage: $0.symbol).tag($0)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Image(systemName: model.viewMode.symbol)
                .font(.system(size: 13, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - 60-day review banner

    private var reviewBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            Text("You have a lot of catches. Want to release some?")
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 8)
            Button("Review") { model.enterReviewMode() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button {
                model.dismissReviewBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.tint.opacity(0.08))
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                ForEach(model.groups, id: \.group) { section in
                    Section {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(section.captures) { capture in
                                LibraryCell(capture: capture, model: model)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 2)
                    } header: {
                        sectionHeader(section.group, count: section.captures.count)
                    }
                }
            }
            .padding(.vertical, 16)
            // Room so the floating bar never covers the last row.
            .padding(.bottom, model.selectionActive ? 70 : 0)
        }
    }

    private func sectionHeader(_ group: DateGroup, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(group.rawValue)
                .font(.system(size: 13, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Bulk action bar

    private var bulkActionBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 14) {
                Text("\(model.selectedCount) \(model.selectedCount == 1 ? "catch" : "catches") selected")
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize()

                Divider().frame(height: 16)

                Menu {
                    ForEach(model.recents.recents(), id: \.self) { url in
                        Button(url.lastPathComponent) { model.moveSelected(to: .folder(url)) }
                    }
                    if !model.recents.recents().isEmpty { Divider() }
                    Button("Other…") { model.moveSelected(to: .other) }
                } label: {
                    Label("Move to…", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 12, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)

                Divider().frame(height: 16)

                Button("Deselect all") { model.clearSelection() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(model.emptyStateGreeting)
                .font(.system(size: 17, weight: .semibold))
            Text("No catches yet — try ⌘⇧7.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack {
            Text(model.isEmpty ? "Nothing here yet" : model.statusLine)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
    }
}

/// One shot in the grid: a thumbnail with its name underneath. Hovering lifts
/// the cell a touch and reveals four quick actions; right-click mirrors them;
/// dragging it out hands the image file to wherever you drop it. ⌘/⇧-click
/// selects it (a checkmark + accent ring appear) for batch move/delete.
private struct LibraryCell: View {
    let capture: Capture
    @ObservedObject var model: LibraryModel
    @Environment(\.appAccent) private var accent

    @State private var image: NSImage?
    @State private var hovering = false

    private let cellWidth: CGFloat = 200
    private let thumbHeight: CGFloat = 120

    private var selected: Bool { model.isSelected(capture) }

    var body: some View {
        VStack(spacing: 7) {
            thumbnail
            Text(capture.filename)
                .font(.system(size: 11))
                .foregroundStyle(selected ? accent : Color.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
        }
        .frame(width: cellWidth)
        .scaleEffect(hovering && !model.selectionActive ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.openInEditor(capture) }
        .onTapGesture { model.handleTap(on: capture) }
        .contextMenu { contextMenu }
        .onDrag {
            NSItemProvider(contentsOf: model.fileURL(for: capture)) ?? NSItemProvider()
        } preview: {
            dragPreview
        }
        .task(id: model.thumbnailKey(for: capture)) {
            image = await model.thumbnails.thumbnail(
                for: model.fileURL(for: capture),
                key: model.thumbnailKey(for: capture),
                maxPixel: 440
            )
        }
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.05))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
            } else {
                ProgressView().controlSize(.small)
            }

            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? accent : Color.white.opacity(0.10),
                              lineWidth: selected ? 2.5 : 1)

            // The quick-action bar only when hovering and not in select mode.
            if hovering && !model.selectionActive {
                actionBar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(8)
                    .transition(.opacity)
            }

            // Selection checkmark, top-left.
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white, accent)
                    .padding(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: cellWidth, height: thumbHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(hovering ? 0.28 : 0), radius: hovering ? 12 : 0, y: hovering ? 6 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selected)
    }

    private var actionBar: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 2) {
                actionButton("pencil", "Open in editor") { model.openInEditor(capture) }
                actionButton("folder", "Reveal in Finder") { model.revealInFinder(capture) }
                actionButton("rectangle.portrait.and.arrow.right", "Move to…") { model.moveToFolder(capture) }
                actionButton("trash", "Delete") { model.delete(capture) }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
        }
        .glassEffect(.regular, in: .capsule)
    }

    private func actionButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Open in Editor") { model.openInEditor(capture) }
        Button("Reveal in Finder") { model.revealInFinder(capture) }
        Button("Move to…") { model.moveToFolder(capture) }
        Divider()
        Button("Delete", role: .destructive) { model.delete(capture) }
    }

    private var dragPreview: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 160)
            } else {
                Image(systemName: "photo")
            }
        }
    }
}
