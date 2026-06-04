import SwiftUI
import AppKit

/// The Settings window: everything you can tune about how Lightscreen behaves,
/// laid out as tabs. Every control writes straight through to storage — there's
/// no Apply button, changes just take.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var outputMode: OutputModeStore
    @ObservedObject var vibes: VibeStore
    let store: LibraryStore
    var onReviewNow: () -> Void

    var body: some View {
        TabView {
            GeneralSettings(settings: settings, outputMode: outputMode)
                .tabItem { Label("General", systemImage: "gearshape") }

            LibrarySettings(settings: settings, store: store, onReviewNow: onReviewNow)
                .tabItem { Label("Library", systemImage: "photo.on.rectangle.angled") }

            BeautifySettings(settings: settings, vibes: vibes)
                .tabItem { Label("Beautify", systemImage: "wand.and.stars") }

            AppearanceSettings(settings: settings)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }

            PermissionsSettings()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 460, height: 430)
        .tint(settings.accentColor)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var outputMode: OutputModeStore

    var body: some View {
        Form {
            Section {
                LabeledContent("Shortcut") {
                    HotkeyRecorderField(combo: $settings.hotkey)
                }
                Picker("Default capture", selection: $settings.defaultCaptureMode) {
                    ForEach(CaptureMode.offered, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Picker("Default output", selection: $outputMode.mode) {
                    Text("Beautified").tag(OutputMode.beautified)
                    Text("Raw").tag(OutputMode.raw)
                }
                Picker("Default ratio", selection: $settings.defaultRatioRaw) {
                    ForEach(AspectRatioOption.allCases) { option in
                        Text(option.rawValue).tag(option.rawValue)
                    }
                }
            } header: {
                Text("How catching feels")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Library

private struct LibrarySettings: View {
    @ObservedObject var settings: SettingsStore
    let store: LibraryStore
    var onReviewNow: () -> Void

    @State private var stats: (count: Int, bytes: Int64) = (0, 0)

    var body: some View {
        Form {
            Section("Pinned destinations") {
                if settings.pinnedFolders.isEmpty {
                    Text("No pinned folders yet.")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                } else {
                    ForEach(settings.pinnedFolders, id: \.self) { folder in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(folder.lastPathComponent)
                            Spacer()
                            Button {
                                settings.unpin(folder)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button("Add folder…", action: addFolder)
            }

            Section("Storage") {
                LabeledContent("Catches", value: "\(stats.count)")
                LabeledContent("Total size",
                               value: ByteCountFormatter.string(fromByteCount: stats.bytes, countStyle: .file))
                Button("Review now…", action: onReviewNow)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshStats)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Pin"
        if panel.runModal() == .OK, let url = panel.url { settings.pin(url) }
    }

    private func refreshStats() {
        let all = store.fetchAll()
        stats = (all.count, all.reduce(Int64(0)) { $0 + $1.fileSizeBytes })
    }
}

// MARK: - Beautify

private struct BeautifySettings: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var vibes: VibeStore

    @State private var renaming: String?
    @State private var draftName = ""

    var body: some View {
        Form {
            Section("Defaults") {
                Picker("Default vibe", selection: $settings.defaultVibeID) {
                    Text("None").tag(String?.none)
                    ForEach(vibes.all) { vibe in
                        Text(vibe.name).tag(Optional(vibe.id))
                    }
                }
            }

            Section("Your vibes") {
                if vibes.custom.isEmpty {
                    Text("Save a backdrop in the editor to see it here.")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                } else {
                    ForEach(vibes.custom) { vibe in
                        HStack {
                            if renaming == vibe.id {
                                TextField("Name", text: $draftName)
                                    .onSubmit {
                                        vibes.rename(id: vibe.id, to: draftName); renaming = nil
                                    }
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Text(vibe.name)
                                Spacer()
                                Button("Rename") { draftName = vibe.name; renaming = vibe.id }
                                    .buttonStyle(.link)
                            }
                            Button(role: .destructive) {
                                vibes.delete(id: vibe.id)
                            } label: {
                                Image(systemName: "trash").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section("Feel") {
                Toggle("Capture sound", isOn: $settings.captureSound)
                Toggle("Sparkle on capture", isOn: $settings.sparkle)
                Toggle("Save delight", isOn: $settings.saveDelight)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Accent") {
                Picker("Accent colour", selection: $settings.accent) {
                    ForEach(AppAccent.allCases) { accent in
                        HStack {
                            Circle()
                                .fill(accent.color ?? Color.accentColor)
                                .frame(width: 12, height: 12)
                            Text(accent.label)
                        }
                        .tag(accent)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Permissions

private struct PermissionsSettings: View {
    @State private var screenOK = false
    @State private var axOK = false

    var body: some View {
        Form {
            Section("Permissions") {
                permissionRow(
                    title: "Screen Recording",
                    subtitle: "To catch what's on your screen.",
                    granted: screenOK,
                    open: Permissions.openScreenRecordingSettings
                )
                permissionRow(
                    title: "Accessibility",
                    subtitle: "To scroll a window for full-page catches.",
                    granted: axOK,
                    open: Permissions.openAccessibilitySettings
                )
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        // Re-check when the user comes back from System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func permissionRow(title: String, subtitle: String, granted: Bool, open: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open System Settings", action: open)
                .controlSize(.small)
        }
    }

    private func refresh() {
        screenOK = Permissions.screenRecordingGranted
        axOK = Permissions.accessibilityGranted
    }
}

// MARK: - Hotkey recorder

/// A small field that listens for the next shortcut you press and saves it.
/// Click to arm; press a modifier + key to set; Esc cancels.
private struct HotkeyRecorderField: View {
    @Binding var combo: HotKeyCombo
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Press shortcut…" : combo.display)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .frame(minWidth: 96)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(recording ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(recording ? Color.accentColor : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Esc cancels
            let mods = HotKeyCombo.carbonFlags(from: event.modifierFlags)
            // Require at least one modifier so we don't bind a bare key.
            guard mods != 0 else { return nil }
            combo = HotKeyCombo(keyCode: UInt32(event.keyCode), carbonModifiers: mods)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
}
