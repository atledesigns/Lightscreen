import SwiftUI
import UniformTypeIdentifiers

/// The Library window: every shot you've taken, laid out as a date-grouped grid
/// you can search, sort, hover for quick actions, and drag straight out into
/// other apps. The first place you *see* your whole library without opening
/// Finder.
struct LibraryView: View {
    @ObservedObject var model: LibraryModel

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.5)

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
/// dragging it out hands the image file to wherever you drop it.
private struct LibraryCell: View {
    let capture: Capture
    @ObservedObject var model: LibraryModel

    @State private var image: NSImage?
    @State private var hovering = false

    private let cellWidth: CGFloat = 200
    private let thumbHeight: CGFloat = 120

    var body: some View {
        VStack(spacing: 7) {
            thumbnail
            Text(capture.filename)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
        }
        .frame(width: cellWidth)
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.openInEditor(capture) }
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
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)

            if hovering {
                actionBar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .frame(width: cellWidth, height: thumbHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(hovering ? 0.28 : 0), radius: hovering ? 12 : 0, y: hovering ? 6 : 0)
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
