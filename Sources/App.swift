import SwiftUI
import AVFoundation
import AppKit

#if !STILLSPACE_CHECK
@main struct StillspaceApp: App {
    @NSApplicationDelegateAdaptor(StillspaceDelegate.self) private var delegate
    @StateObject private var studio: Studio
    init() { _studio = StateObject(wrappedValue: Studio()) }

    var body: some Scene {
        Window("Stillspace", id: "library") {
            StudioView().environmentObject(studio)
                .onOpenURL { url in if url.pathExtension == "stillscene" { studio.importScenePack(at: url) } }
        }
        .defaultSize(width: 1140, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Show Quick Controls") { StillspaceLifecycle.showQuickControls?() }.keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Import Wallpaper…", action: studio.importMovie)
                    .keyboardShortcut("o")
                Button("Import Scene Pack…", action: studio.importScenePack)
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
        Window("Desktop Widget Editor", id: "widget-editor") {
            WidgetLayoutEditor().environmentObject(studio)
        }.defaultSize(width: 1100, height: 720)
        Settings {
            PreferencesView().environmentObject(studio)
                .frame(width: 480, height: 500)
        }
    }
}

#endif

struct MenuBarContent: View {
    @EnvironmentObject var studio: Studio
    @Environment(\.openWindow) private var openWindow
    var openLibrary: (() -> Void)? = nil
    var openSettings: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // A still preview avoids mounting a second desktop player layer in the popover.
            WallpaperThumbnail(scene: studio.current)
                .frame(width: 276, height: 156)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.10)))
            VStack(alignment: .leading, spacing: 4) {
                Text(studio.current.name).font(.headline).lineLimit(2).frame(height: 34, alignment: .topLeading)
                    .help(studio.current.name)
                Text(studio.running ? (studio.pauseReason.map { "Paused · " + $0 } ?? "Playing on your desktop") : "Wallpaper stopped")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 10) {
                Button { step(-1) } label: { Image(systemName: "backward.end.fill").frame(maxWidth: .infinity, minHeight: 28) }.help("Previous wallpaper")
                Button(action: studio.toggleDesktop) { Image(systemName: studio.running ? "pause.fill" : "play.fill").frame(maxWidth: .infinity, minHeight: 28) }.help(studio.running ? "Stop wallpaper" : "Play wallpaper")
                Button { step(1) } label: { Image(systemName: "forward.end.fill").frame(maxWidth: .infinity, minHeight: 28) }.help("Next wallpaper")
            }.buttonStyle(.plain).font(.system(size: 15, weight: .medium))
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Button { if let openLibrary { openLibrary() } else { openWindow(id: "library"); NSApp.activate(ignoringOtherApps: true) } } label: { menuRow("Open Stillspace", icon: "arrow.up.forward.app") }
                Button(action: studio.startScreenSaver) { menuRow("Start Screen Saver", icon: "moon") }
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                toggleRow("Follow time of day", icon: "sun.max", value: $studio.automatic)
                toggleRow("Desktop widgets", icon: "square.grid.2x2", value: $studio.widgets)
            }
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                if let openSettings { Button(action: openSettings) { menuRow("Settings", icon: "gearshape") } }
                else { SettingsLink { menuRow("Settings", icon: "gearshape") } }
                Button { NSApp.terminate(nil) } label: { menuRow("Quit Stillspace", icon: "power") }.keyboardShortcut("q")
            }.buttonStyle(.plain)
        }.padding(12).frame(width: 300)
            .modifier(MenuPanelSurface())
    }
    private func menuRow(_ title: String, icon: String) -> some View {
        Label { Text(title) } icon: { Image(systemName: icon).frame(width: 18) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7).contentShape(Rectangle())
    }
    private func toggleRow(_ title: String, icon: String, value: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 18)
            Text(title)
            Spacer(minLength: 8)
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }.frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    }
    private func step(_ offset: Int) {
        let index = studio.scenes.firstIndex { $0.id == studio.selected } ?? 0
        let next = (index + offset + studio.scenes.count) % studio.scenes.count
        studio.apply(studio.scenes[next])
    }

}

private struct MenuPanelSurface: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
                .clipShape(shape)
        } else if #available(macOS 15, *) {
            content.background(.regularMaterial, in: shape)
                .clipShape(shape)
        } else {
            content.background(.regularMaterial, in: shape).clipShape(shape)
        }
    }
}

// A borderless AppKit panel owns the one glass surface. MenuBarExtra's system
// popover frame added a second outline that SwiftUI clipping could not remove.
@MainActor private final class QuickControlsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor final class QuickControlsController: NSObject {
    private let studio: Studio
    private let item: NSStatusItem
    private var panel: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    init(studio: Studio) {
        self.studio = studio
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.button?.image = NSImage(systemSymbolName: "mountain.2", accessibilityDescription: "Stillspace")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "Stillspace"
        item.button?.target = self; item.button?.action = #selector(toggle)
    }
    @objc private func toggle() { if panel?.isVisible == true { hide() } else { show() } }
    func show() {
        hide()
        let content = MenuBarContent(openLibrary: { [weak self] in self?.openLibrary() }, openSettings: { [weak self] in self?.openSettings() })
            .environmentObject(studio).preferredColorScheme(.dark)
        let host = NSHostingController(rootView: content)
        host.sizingOptions = [.preferredContentSize]
        host.view.layoutSubtreeIfNeeded()
        let fitting = host.view.fittingSize
        let size = NSSize(width: 300, height: max(400, fitting.height))
        let window = QuickControlsPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Stillspace Quick Controls"
        window.isReleasedWhenClosed = false; window.isOpaque = false; window.backgroundColor = .clear
        window.hasShadow = true; window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentViewController = host
        window.setContentSize(size)
        if let button = item.button, let bar = button.window {
            let anchor = bar.convertToScreen(button.convert(button.bounds, to: nil))
            let frame = bar.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchor
            window.setFrameOrigin(NSPoint(x: min(max(frame.minX + 8, anchor.midX - size.width / 2), frame.maxX - size.width - 8), y: max(frame.minY + 8, anchor.minY - size.height - 6)))
        }
        panel = window; NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in Task { @MainActor in self?.hide() } }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 { self.hide(); return nil }
            if event.type != .keyDown && event.window !== self.panel && event.window !== self.item.button?.window { self.hide() }
            return event
        }
    }
    func hide() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }; globalMonitor = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }; localMonitor = nil
        panel?.orderOut(nil); panel?.contentViewController = nil; panel?.close(); panel = nil
    }
    func shutdown() { hide(); NSStatusBar.system.removeStatusItem(item) }
    private func openLibrary() {
        hide()
        if let menu = NSApp.windowsMenu, let index = menu.items.firstIndex(where: { $0.title == "Stillspace" && $0.action != nil }) { menu.performActionForItem(at: index) }
        NSApp.activate(ignoringOtherApps: true)
    }
    private func openSettings() {
        hide()
        if let menu = NSApp.mainMenu?.items.first?.submenu,
           let index = menu.items.firstIndex(where: { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask.contains(.command) }) { menu.performActionForItem(at: index) }
        NSApp.activate(ignoringOtherApps: true)
    }
}

private enum LibraryPage: String, CaseIterable, Identifiable {
    case discover = "Discover"
    case all = "All Wallpapers", favorites = "Favorites", imported = "Imported"
    case morning = "Morning", afternoon = "Afternoon", evening = "Evening"
    case schedule = "Schedule"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .discover: "sparkles"
        case .all: "square.grid.2x2"
        case .favorites: "heart"
        case .imported: "square.and.arrow.down"
        case .morning: "sunrise"
        case .afternoon: "sun.max"
        case .evening: "moon.stars"
        case .schedule: "clock.arrow.2.circlepath"
        }
    }
    var isLibrary: Bool { self != .schedule && self != .discover }
}

// Part of the scrolling page, so the brand naturally leaves and returns with it.
private struct AppBrand: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mountain.2")
                .font(.system(size: 28, weight: .regular))
                .frame(width: 54, height: 54)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
            Text("Stillspace").font(.system(size: 26, weight: .semibold))
        }.foregroundStyle(.white).accessibilityElement(children: .combine)
    }
}

private enum MainTab: String, CaseIterable { case home = "Home", explore = "Explore", library = "Library" }

struct StudioView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var studio: Studio
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var navigation
    @State private var featuredID = "night"
    @State private var tab: MainTab = .home
    @State private var collection: LibraryPage = .all
    @State private var search = ""
    @State private var searchPresented = false
    @State private var preview: Landscape?
    @State private var editWidgetsAfterPreview = false
    @State private var deletion: Landscape?
    @State private var savePackPresented = false
    @State private var packName = ""
    @State private var packToRemove: SavedScenePack?
    @State private var showSchedule = false
    private var featured: Landscape { studio.scenes.first { $0.id == featuredID } ?? studio.current }
    private var filtered: [Landscape] {
        studio.scenes.filter { scene in
            let matches: Bool
            switch collection {
            case .favorites: matches = studio.favorites.contains(scene.id)
            case .imported: matches = scene.file != nil
            case .morning: matches = scene.id == "dawn"
            case .afternoon: matches = scene.id == "day"
            case .evening: matches = scene.id == "night"
            default: matches = true
            }
            return matches && (search.isEmpty || (scene.name + " " + scene.subtitle).localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        ZStack(alignment: .top) {
            WallpaperThumbnail(scene: featured).blur(radius: 65).opacity(0.45).ignoresSafeArea().allowsHitTesting(false)
            Color(red: 0.09, green: 0.12, blue: 0.14).opacity(0.82).ignoresSafeArea()
            if tab == .home && search.isEmpty {
                DiscoverView(openScene: { preview = $0 }, openCollection: { collection = $0; tab = .explore }, featuredID: $featuredID, previewActive: preview == nil && !showSchedule && !searchPresented && studio.appActive)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if tab == .library && search.isEmpty { libraryHeader }
                        else {
                            ZStack {
                                WallpaperThumbnail(scene: featured).opacity(0.55)
                                LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                                VStack(spacing: 14) {
                                    Text(search.isEmpty ? "Explore" : "Search wallpapers").font(.system(size: 36, weight: .semibold))
                                    Text("Let your desktop tell a story.").foregroundStyle(.white.opacity(0.8))
                                    Button("Import your own MP4", action: studio.importMovie).buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                                }
                            }.frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                        filters
                        if !search.isEmpty {
                            HStack { Text("Results for “\(search)”"); Spacer(); Button("Clear") { search = "" } }.font(.callout)
                        }
                        HStack {
                            Text(collection == .all ? (tab == .library ? "Your wallpapers" : "All wallpapers") : collection.rawValue).font(.title2.weight(.semibold))
                            Spacer()
                            Text("\(filtered.count) \(filtered.count == 1 ? "wallpaper" : "wallpapers")").font(.caption).foregroundStyle(.secondary)
                        }
                        if filtered.isEmpty {
                            ContentUnavailableView("No wallpapers here", systemImage: "mountain.2", description: Text("Import an MP4 or save a favorite to build your collection."))
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 400), spacing: 22)], spacing: 28) {
                                ForEach(filtered) { scene in
                                    WallpaperCard(scene: scene, selected: false) { preview = scene }
                                        .contextMenu {
                                            Button("Set as Wallpaper") { studio.apply(scene) }
                                            Button(studio.favorites.contains(scene.id) ? "Remove from Favorites" : "Add to Favorites") { studio.toggleFavorite(scene.id) }
                                            if scene.file != nil { Button("Remove from Library…", role: .destructive) { deletion = scene } }
                                        }
                                }
                            }
                        }
                    }.padding(.horizontal, 48).padding(.top, 162).padding(.bottom, 48)
                        .overlay(alignment: .topLeading) { AppBrand().padding(.leading, 40).padding(.top, 62) }
                }
            }
            floatingNavigation.padding(.horizontal, 40).padding(.top, 62)
            if searchPresented {
                searchOverlay.transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .onChange(of: studio.packs.count) { _, _ in tab = .library }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: tab)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: searchPresented)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.55), value: featuredID)
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 860, minHeight: 590)
        .preferredColorScheme(.dark)
        .sheet(item: $preview, onDismiss: {
            if editWidgetsAfterPreview {
                editWidgetsAfterPreview = false
                openWindow(id: "widget-editor")
            }
        }) { scene in
            VStack(spacing: 0) {
                HStack { Text("Wallpaper").font(.headline); Spacer(); Button("Done") { preview = nil } }.padding(20)
                WallpaperInspector(scene: scene, editWidgets: {
                    editWidgetsAfterPreview = true
                    preview = nil
                })
            }.frame(width: 460, height: 630)
        }
        .alert("Save your desktop", isPresented: $savePackPresented) {
            TextField("Scene pack name", text: $packName)
            Button("Cancel", role: .cancel) { }
            Button("Save Pack") { studio.saveScenePack(named: packName) }
                .disabled(packName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || packName.count > 80)
        } message: { Text("Save your applied wallpaper, widgets, sound settings, and day/night preference. Videos and attached audio are included.") }
        .confirmationDialog("Remove saved scene pack?", isPresented: Binding(get: { packToRemove != nil }, set: { if !$0 { packToRemove = nil } })) {
            Button("Remove Pack", role: .destructive) { if let packToRemove { studio.removeScenePack(packToRemove) }; packToRemove = nil }
            Button("Cancel", role: .cancel) { packToRemove = nil }
        } message: { Text("This removes the saved setup. Applied wallpapers stay in your wallpaper library.") }
        .sheet(isPresented: $showSchedule) { VStack { HStack { Text("Daily schedule").font(.headline); Spacer(); Button("Done") { showSchedule = false } }.padding(); ScheduleView() }.frame(width: 540, height: 480) }
        .onChange(of: studio.scenes.count) { old, new in if new > old { tab = .library; collection = .imported; search = "" } }
        .confirmationDialog("Remove imported wallpaper?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
            Button("Remove from Library", role: .destructive) { if let scene = deletion { studio.remove(scene) }; deletion = nil }
        } message: { Text("The imported copy will be deleted. Your original MP4 stays where it is.") }
        .alert("Stillspace", isPresented: Binding(get: { studio.error != nil }, set: { if !$0 { studio.error = nil } })) {
            Button("OK") { studio.error = nil }
        } message: { Text(studio.error ?? "") }
    }
    private var searchOverlay: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 18) {
                HStack { Spacer(); Button { searchPresented = false } label: { Image(systemName: "xmark").frame(width: 40, height: 40) }.buttonStyle(.plain).modifier(PlaybackGlass()) }
                LibrarySearchPanel(search: $search, count: filtered.count) { searchPresented = false }
                HStack(spacing: 10) {
                    ForEach(["Morning", "Afternoon", "Evening"], id: \.self) { term in
                        Button(term) { search = term == "Evening" ? "Blue" : term; searchPresented = false }
                            .buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 9).modifier(CapsuleGlass())
                    }
                }
                Spacer()
            }.padding(40).padding(.top, 70)
        }.onExitCommand { searchPresented = false }
    }
    private var floatingNavigation: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 204, height: 56).allowsHitTesting(false)
            Spacer(minLength: 12)
            HStack(spacing: 4) {
                ForEach(MainTab.allCases, id: \.self) { item in
                    Button { withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.85)) { tab = item; search = ""; collection = .all } } label: {
                        Text(item.rawValue).font(.system(size: 13, weight: .medium))
                            .frame(width: 78, height: 34)
                            .foregroundStyle(tab == item ? Color.black : Color.white)
                            .background { if tab == item { Capsule().fill(.white).matchedGeometryEffect(id: "tab", in: navigation) } }
                    }.buttonStyle(.plain)
                }
            }.padding(5).modifier(CapsuleGlass())
            Button { searchPresented = true } label: { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }
                .buttonStyle(.plain).modifier(PlaybackGlass()).help("Search wallpapers").keyboardShortcut("f")
            Spacer(minLength: 12)
            Button(action: studio.importMovie) { Image(systemName: "plus").frame(width: 44, height: 44) }
                .buttonStyle(.plain).modifier(PlaybackGlass()).help("Import wallpaper")
            SettingsLink { Image(systemName: "gearshape").frame(width: 44, height: 44) }
                .buttonStyle(.plain).modifier(PlaybackGlass()).help("Settings")
        }
    }
    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach([LibraryPage.all, .favorites, .imported, .morning, .afternoon, .evening]) { item in
                    Button { collection = item } label: {
                        Label(item == .all ? "All" : item.rawValue, systemImage: item.icon)
                            .font(.system(size: 12, weight: .medium)).padding(.horizontal, 16).padding(.vertical, 10)
                            .background(collection == item ? Color.white.opacity(0.16) : .clear, in: Capsule())
                    }.buttonStyle(.plain).modifier(CapsuleGlass())
                }
            }.padding(.vertical, 3)
        }.scrollIndicators(.hidden)
    }
    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Your library").font(.system(size: 32, weight: .semibold))
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Day / Night wallpaper").font(.title2.weight(.semibold))
                        Text("Let the atmosphere change with your day.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Enable", isOn: $studio.automatic).toggleStyle(.switch).fixedSize()
                    Button { showSchedule = true } label: { Image(systemName: "slider.horizontal.3") }.buttonStyle(.bordered).help("Schedule details")
                }
                HStack(spacing: 18) {
                    ForEach(Array(Landscape.builtins.enumerated()), id: \.element.id) { index, scene in
                        Button { preview = scene } label: {
                            ZStack(alignment: .bottomLeading) {
                                WallpaperThumbnail(scene: scene)
                                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(["Morning", "Day", "Night"][index]).font(.headline)
                                    Text(["From 06:00", "From 12:00", "From 19:00"][index]).font(.caption).foregroundStyle(.white.opacity(0.7))
                                }.padding(14)
                            }.frame(height: 145).clipShape(RoundedRectangle(cornerRadius: 15))
                        }.buttonStyle(.plain)
                    }
                }
            }
            if studio.running {
                HStack { Label("Playing · \(studio.current.name)", systemImage: "play.fill"); Spacer(); Button("Stop wallpaper", action: studio.toggleDesktop) }.font(.callout)
            }
            scenePacks
        }
    }

    private var scenePacks: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Scene packs").font(.title2.weight(.semibold))
                    Text("Your wallpaper. Your widgets. One saved setup.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Edit Widgets") { openWindow(id: "widget-editor") }.buttonStyle(.bordered)
                Button("Import Pack…", action: studio.importScenePack).buttonStyle(.bordered)
                Button { packName = studio.current.name + " setup"; savePackPresented = true } label: { Label("Save Desktop", systemImage: "plus") }.buttonStyle(.borderedProminent)
            }
            if studio.packs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Make a desktop worth keeping", systemImage: "square.stack.3d.up").font(.headline)
                    Text("Set a wallpaper and arrange your widgets, then save the whole look. Packs include their media and can be shared locally.").font(.callout).foregroundStyle(.secondary)
                    Button("Create Blue hour + clock") { studio.saveScenePack(named: "Blue hour · Minimal", starter: true) }.buttonStyle(.bordered)
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.08)))
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(studio.packs) { item in
                            VStack(alignment: .leading, spacing: 10) {
                                ZStack(alignment: .bottomLeading) {
                                    WallpaperThumbnail(scene: item.preview)
                                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                                    Label("Scene pack", systemImage: "square.stack.3d.up").font(.caption).padding(12)
                                }.frame(width: 245, height: 145).clipShape(RoundedRectangle(cornerRadius: 16))
                                HStack {
                                    Text(item.pack.name).font(.headline).lineLimit(1)
                                    Spacer()
                                    Menu {
                                        Button("Export Pack…") { studio.exportScenePack(item) }
                                        Button("Remove Pack…", role: .destructive) { packToRemove = item }
                                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().help("Scene pack options")
                                }
                                Text(item.pack.automatic ? "Day / Night · \(item.pack.widgetsEnabled ? item.pack.widgets.count : 0) widgets" : "\(item.pack.widgetsEnabled ? item.pack.widgets.count : 0) widgets · Saved sound settings").font(.caption).foregroundStyle(.secondary)
                                Button("Apply Setup") { studio.applyScenePack(item) }.buttonStyle(.bordered)
                            }.frame(width: 245)
                        }
                    }.padding(.bottom, 4)
                }.scrollIndicators(.hidden)
            }
            if studio.packBusy { ProgressView("Preparing scene pack…").controlSize(.small) }
            if let message = studio.packMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.disabled(studio.packBusy)
    }

}

private struct WallpaperCard: View {
    @EnvironmentObject var studio: Studio
    let scene: Landscape
    let selected: Bool
    let select: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button(action: select) {
                ZStack {
                    WallpaperThumbnail(scene: scene)
                    if hovering && !reduceMotion && scene.file == nil { ScenePreview(scene: scene, playing: true).transition(.opacity) }
                }
                    .aspectRatio(1.77, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12), lineWidth: 1))
                    .padding(3)
                    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                    .overlay(alignment: .bottomLeading) {
                        if studio.running && studio.selected == scene.id {
                            Label("On desktop", systemImage: "play.fill").font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 8).padding(.vertical, 5).background(.regularMaterial, in: Capsule()).padding(11)
                        }
                    }
            }.buttonStyle(.plain).accessibilityLabel("Preview \(scene.name)")
            HStack(alignment: .top, spacing: 4) {
                Button(action: select) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scene.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
                        Text(scene.file == nil ? scene.subtitle : "Imported video").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button { studio.toggleFavorite(scene.id) } label: {
                    Image(systemName: studio.favorites.contains(scene.id) ? "heart.fill" : "heart")
                        .foregroundStyle(studio.favorites.contains(scene.id) ? Color.accentColor : Color.secondary)
                }.buttonStyle(.borderless).help(studio.favorites.contains(scene.id) ? "Remove from favorites" : "Add to favorites")
            }.padding(.horizontal, 4)
        }
        .scaleEffect(hovering && !reduceMotion ? 1.025 : 1)
        .shadow(color: .black.opacity(hovering ? 0.22 : 0), radius: 14, y: 8)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: hovering)
        .onHover { hovering = $0 }
    }
}

@MainActor private enum ThumbnailCache { static let images: NSCache<NSString, NSImage> = { let cache = NSCache<NSString, NSImage>(); cache.totalCostLimit = 32 * 1024 * 1024; return cache }() }

private struct WallpaperThumbnail: View {
    let scene: Landscape
    @State private var thumbnail: NSImage?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if scene.file == nil { LandscapeView(palette: scene.palette) }
                else if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFill() }
                else { Rectangle().fill(.quaternary); Image(systemName: "film").font(.title).foregroundStyle(.secondary) }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.task(id: scene.id) {
            thumbnail = nil
            guard let file = scene.file else { return }
            if let cached = ThumbnailCache.images.object(forKey: file as NSString) { thumbnail = cached; return }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: file)))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 400)
            if let result = try? await generator.image(at: .zero), !Task.isCancelled {
                let value = NSImage(cgImage: result.image, size: .zero)
                ThumbnailCache.images.setObject(value, forKey: file as NSString, cost: result.image.width * result.image.height * 4)
                thumbnail = value
            }
        }
    }
}

private struct WallpaperInspector: View {
    @EnvironmentObject var studio: Studio
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let scene: Landscape
    let editWidgets: () -> Void
    @State private var previewPlaying = true
    @State private var details: VideoDetails?
    @State private var renamePresented = false
    @State private var newName = ""
    @State private var displaysPresented = false
    private var active: Bool { studio.running && studio.selected == scene.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZStack(alignment: .bottomTrailing) {
                    ScenePreview(scene: scene, playing: previewPlaying && !reduceMotion)
                        .frame(height: 165)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    Button { previewPlaying.toggle() } label: {
                        Image(systemName: previewPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .semibold)).frame(width: 30, height: 30)
                    }.buttonStyle(.plain).modifier(PlaybackGlass()).padding(9)
                        .help(previewPlaying ? "Pause preview" : "Play preview")
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(studio.scenes.first { $0.id == scene.id }?.name ?? scene.name).font(.title2.weight(.semibold)).textSelection(.enabled)
                        Spacer(minLength: 4)
                        Button { studio.toggleFavorite(scene.id) } label: { Image(systemName: studio.favorites.contains(scene.id) ? "heart.fill" : "heart") }
                            .buttonStyle(.borderless).help("Favorite wallpaper")
                    }
                    Text(scene.subtitle).font(.callout).foregroundStyle(.secondary)
                    if scene.file != nil { Button("Rename…") { newName = studio.scenes.first { $0.id == scene.id }?.name ?? scene.name; renamePresented = true } }
                }
                Button { if active { studio.toggleDesktop() } else { studio.apply(scene) } } label: {
                    Label(active ? "Stop Wallpaper" : "Set as Wallpaper", systemImage: active ? "stop.fill" : "desktopcomputer")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                Divider()
                VStack(spacing: 12) {
                    detail("Type", scene.file == nil ? "Animated landscape" : "MP4 video")
                    detail("Location", "On this Mac")
                    Button("Choose displays…") { displaysPresented = true }
                    if let details {
                        detail("Resolution", details.resolution)
                        detail("File size", details.size)
                        detail("Video", String(format: "%.0f fps · %.0f seconds", details.fps, details.duration))
                    }
                    detail("Sound", studio.sound(for: scene.id).file == nil ? (scene.file == nil ? "None" : "MP4 audio") : "Attached audio")
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Lock screen · experimental").font(.headline)
                    Button("Prepare this scene for Screen Saver…") { studio.prepareLockScreen(scene) }.disabled(studio.lockBusy)
                    if studio.lockBusy { ProgressView("Preparing video…").controlSize(.small) }
                    if let message = studio.lockMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                    Text("After preparation, choose this scene under Stillspace in macOS Wallpaper → Screen Saver → Custom. The video starts with the screen saver; locking alone may show a still image. Your desktop selection is separate.").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 13) {
                    Text("Desktop").font(.headline)
                    Toggle("Show widgets", isOn: $studio.widgets)
                    Button(action: editWidgets) { Label("Edit Widgets", systemImage: "square.grid.2x2") }
                    Divider()
                    Text("Wallpaper sound").font(.headline)
                    Toggle("Play sound", isOn: Binding(get: { studio.sound(for: scene.id).enabled }, set: { value in studio.updateSound(scene.id) { $0.enabled = value } }))
                    Slider(value: Binding(get: { studio.sound(for: scene.id).volume }, set: { value in studio.updateSound(scene.id) { $0.volume = value } }), in: 0...1) { Text("Volume") }
                    Button("Add audio file…") { studio.attachSound(to: scene.id) }
                    if studio.sound(for: scene.id).file != nil { Button("Use original sound") { studio.useOriginalSound(scene.id) } }
                    Text("Audio plays only on the desktop. An attached file replaces the MP4’s sound.").font(.caption).foregroundStyle(.secondary)
                }.toggleStyle(.switch).controlSize(.small)
                Text(active ? (studio.pauseReason.map { "Playback paused · " + $0 } ?? "This wallpaper is playing behind your desktop icons.") : "Previewing only. Apply this wallpaper when you’re ready.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(20)
        }
        .onChange(of: scene.id) { previewPlaying = true }
        .task(id: scene.id) { details = nil; if let file = scene.file { details = try? await VideoDetails.load(file) } }
        .alert("Rename wallpaper", isPresented: $renamePresented) { TextField("Name", text: $newName); Button("Save") { studio.rename(scene.id, to: newName) }; Button("Cancel", role: .cancel) {} }
        .sheet(isPresented: $displaysPresented) { DisplaySettingsView().environmentObject(studio) }
    }
    private func detail(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value) }.font(.caption)
    }
}

private struct PlaybackGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) { content.glassEffect(.regular.interactive(), in: Circle()) }
        else { content.background(.regularMaterial, in: Circle()) }
    }
}

@MainActor private final class PreviewPlayback: ObservableObject {
    @Published var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    func load(_ scene: Landscape) async {
        stop()
        guard let file = scene.file else { return }
        let asset = AVURLAsset(url: URL(fileURLWithPath: file))
        guard (try? await asset.load(.isPlayable)) == true, !Task.isCancelled else { return }
        let player = AVQueuePlayer(); player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
        self.player = player; player.play()
    }
    func stop() { player?.pause(); looper?.disableLooping(); looper = nil; player?.removeAllItems(); player = nil }
}

struct ScenePreview: View {
    @EnvironmentObject var studio: Studio
    let scene: Landscape
    let playing: Bool
    @StateObject private var playback = PreviewPlayback()
    private var shared: AVPlayer? { studio.running && studio.selected == scene.id ? studio.desktop.previewPlayer : nil }
    private var effectivePlaying: Bool { playing && studio.previewsAllowed }
    private var ownPlayback: Bool { scene.file != nil && effectivePlaying && shared == nil }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if scene.file == nil { EfficientLandscape(palette: scene.palette, animated: effectivePlaying) }
                else if effectivePlaying, let shared { MovieView(player: shared) }
                else if ownPlayback, let player = playback.player { MovieView(player: player) }
                else { WallpaperThumbnail(scene: scene) }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .task(id: scene.id + (ownPlayback ? "-playing" : "-still")) {
            if ownPlayback { await playback.load(scene) } else { playback.stop() }
        }
        .onDisappear { playback.stop() }
    }
}

private struct ScheduleView: View {
    @EnvironmentObject var studio: Studio
    var body: some View {
        Form {
            Section {
                Toggle("Follow time of day", isOn: $studio.automatic)
                Text("Change the wallpaper automatically using your Mac’s local time.").font(.callout).foregroundStyle(.secondary)
            }
            Section("Daily schedule") {
                ForEach(Array(Landscape.builtins.enumerated()), id: \.element.id) { index, scene in
                    HStack(spacing: 14) {
                        LandscapeView(palette: scene.palette).frame(width: 78, height: 48).clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(scene.name).fontWeight(.medium)
                            Text(["06:00 – 12:00", "12:00 – 19:00", "19:00 – 06:00"][index]).foregroundStyle(.secondary).font(.caption)
                        }
                        Spacer()
                        if studio.automatic && studio.selected == scene.id { Text("Now").font(.caption).foregroundStyle(Color.accentColor) }
                    }.padding(.vertical, 6)
                }
            }
            Section { Text("Applying a wallpaper manually turns off the schedule. Wallpaper playback starts when you choose Set as Wallpaper.").font(.caption).foregroundStyle(.secondary) }
        }.formStyle(.grouped)
    }
}

struct PreferencesView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var studio: Studio
    @State private var displaysPresented = false
    @State private var storagePresented = false
    @State private var screenSaverScene = ""
    private var chosenScreenSaver: Landscape { studio.scenes.first { $0.id == screenSaverScene } ?? studio.current }
    var body: some View {
        Form {
            Section("Wallpaper") {
                Toggle("Follow time of day", isOn: $studio.automatic)
                Button("Choose wallpapers for each display…") { displaysPresented = true }
                Button("Manage wallpaper storage…") { storagePresented = true }
                Text("Morning at 06:00, afternoon at 12:00, and evening at 19:00.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Personal app") {
                Toggle("Restore wallpaper when opening", isOn: $studio.restorePlayback)
                Toggle("Open at login", isOn: Binding(get: { studio.loginEnabled }, set: studio.setLogin))
            }
            Section("Energy") {
                Toggle("Pause wallpaper on battery", isOn: $studio.pauseOnBattery)
                Toggle("Pause in Low Power Mode", isOn: $studio.pauseInLowPowerMode)
                Text("Playback pauses while locked, when displays sleep, or when your Mac gets too hot. Your ordinary desktop appears while paused.").font(.caption).foregroundStyle(.secondary)
                if let reason = studio.pauseReason { LabeledContent("Playback paused", value: reason) }
            }
            Section("Screen-saver video · experimental") {
                Text("This optional integration uses an undocumented macOS screen-saver catalog and may break after system updates. It runs only when you choose Prepare. Prepare a silent video, then select it only in System Settings → Wallpaper → Screen Saver → Custom. Keep your desktop wallpaper selected separately. Lock Screen initially shows that image; the video plays when the screen saver starts. macOS may stop motion after two minutes.").font(.callout).foregroundStyle(.secondary)
                Picker("Screen-saver scene", selection: Binding(get: { chosenScreenSaver.id }, set: { screenSaverScene = $0 })) {
                    ForEach(studio.scenes) { Text($0.name).tag($0.id) }
                }
                Button("Prepare \(chosenScreenSaver.name) for Screen Saver") { studio.prepareLockScreen(chosenScreenSaver) }.disabled(studio.lockBusy)
                if studio.lockBusy { ProgressView().controlSize(.small) }
                if let message = studio.lockMessage { Text(message).font(.caption).foregroundStyle(.secondary) }

                Button("Start Screen Saver", action: studio.startScreenSaver)
                Text("Set the screen saver to start before the display sleeps in macOS Lock Screen settings. Password protection follows your existing settings.").font(.caption).foregroundStyle(.secondary)
                Button("Remove Stillspace lock-screen entries", action: studio.removeLockScreenLibrary).disabled(studio.lockBusy)
            }
            Section("Desktop widgets") {
                Toggle("Show desktop widgets", isOn: $studio.widgets)
                Button("Edit widget layout…") { openWindow(id: "widget-editor") }
                Text("Start with a blank desktop. Add only the widgets you want.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Wallpaper audio") {
                Text("Use the sound in your MP4, or attach an audio file from the wallpaper’s preview. Sound and volume are saved per wallpaper.").font(.callout).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Stillspace", value: "1.3.4 · Personal edition")
                Text("Everything stays on this Mac. Playback pauses when displays sleep.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
        .sheet(isPresented: $displaysPresented) { DisplaySettingsView().environmentObject(studio) }
        .sheet(isPresented: $storagePresented) { StorageSettingsView().environmentObject(studio) }
        .alert("Stillspace", isPresented: Binding(get: { studio.error != nil }, set: { if !$0 { studio.error = nil } })) { Button("OK") { studio.error = nil } } message: { Text(studio.error ?? "") }
    }
}

private struct LibrarySearchPanel: View {
    @Binding var search: String
    let count: Int
    let dismiss: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search wallpapers", text: $search)
                    .textFieldStyle(.plain).focused($focused).onSubmit(dismiss)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Clear search")
                }
            }.padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
            Text(search.isEmpty ? "Find a title or time of day in this collection." : "\(count) \(count == 1 ? "wallpaper" : "wallpapers") found")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(width: 480)
            .onAppear { focused = true }
            .onExitCommand(perform: dismiss)
    }
}

private struct DiscoverView: View {
    @EnvironmentObject var studio: Studio
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let openScene: (Landscape) -> Void
    let openCollection: (LibraryPage) -> Void
    @Binding var featuredID: String
    var previewActive: Bool
    @State private var playing = true
    private var featured: Landscape { studio.scenes.first { $0.id == featuredID } ?? Landscape.builtins[0] }
    private var favorites: [Landscape] { studio.scenes.filter { studio.favorites.contains($0.id) } }
    private var imports: [Landscape] { studio.scenes.filter { $0.file != nil } }

    var body: some View {
        GeometryReader { viewport in
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ZStack(alignment: .bottomLeading) {
                    ZStack {
                        ScenePreview(scene: featured, playing: playing && !reduceMotion && previewActive)
                            .id(featured.id).transition(.opacity)
                    }.animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: featuredID)
                    LinearGradient(colors: [.clear, Color(red: 0.09, green: 0.12, blue: 0.14)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("FEATURED WALLPAPER").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.white.opacity(0.75))
                        Text(featured.name).font(.system(size: 30, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                        Text(featured.subtitle).font(.callout).foregroundStyle(.white.opacity(0.8))
                        HStack(spacing: 10) {
                            Button { openScene(featured) } label: {
                                Label("View Wallpaper", systemImage: "play.fill").font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 10)
                            }.buttonStyle(.plain).modifier(CapsuleGlass())
                            Button { studio.toggleFavorite(featured.id) } label: {
                                Image(systemName: studio.favorites.contains(featured.id) ? "heart.fill" : "heart").frame(width: 34, height: 34)
                            }.buttonStyle(.plain).modifier(PlaybackGlass()).help("Favorite wallpaper")
                            Spacer()
                            Button { playing.toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 34, height: 34) }
                                .buttonStyle(.plain).modifier(PlaybackGlass()).help("Pause or play featured preview")
                        }.padding(.top, 6)
                    }.padding(.horizontal, 48).padding(.bottom, 135)
                }.frame(width: viewport.size.width, height: 550).clipped().padding(.horizontal, -36).padding(.top, -24)
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        ForEach(studio.scenes) { scene in
                            Button { featuredID = scene.id } label: {
                                WallpaperThumbnail(scene: scene).frame(width: 160, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(featuredID == scene.id ? .white.opacity(0.9) : .white.opacity(0.15), lineWidth: featuredID == scene.id ? 2.5 : 1))
                                    .scaleEffect(featuredID == scene.id ? 1 : 0.96)
                            }.buttonStyle(.plain).accessibilityLabel("Feature " + scene.name)
                        }
                    }.padding(.vertical, 5)
                }.scrollIndicators(.hidden).padding(.top, -135)

                VStack(alignment: .leading, spacing: 13) {
                    Text("Browse by time of day").font(.headline)
                    HStack(spacing: 10) {
                        category(.morning)
                        category(.afternoon)
                        category(.evening)
                    }
                }
                shelf("Stillspace’s Pick", subtitle: "A little atmosphere for every hour.", scenes: Landscape.builtins)
                if !favorites.isEmpty { shelf("Your favorites", subtitle: "The wallpapers you’ve saved.", scenes: favorites) }
                if !imports.isEmpty { shelf("Recently imported", subtitle: "Your own videos, on your desktop.", scenes: Array(imports.reversed())) }
                else {
                    HStack(spacing: 14) {
                        Image(systemName: "film").font(.title2).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Make room for your favorites").font(.headline)
                            Text("Import an MP4 to add it to your library.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Import MP4…", action: studio.importMovie).buttonStyle(.bordered)
                    }.padding(18).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(.horizontal, 36).padding(.top, 24).padding(.bottom, 36)
                .overlay(alignment: .topLeading) { AppBrand().padding(.leading, 40).padding(.top, 62) }
        }.frame(width: viewport.size.width, height: viewport.size.height).background(.clear)
        }
    }
    private func category(_ item: LibraryPage) -> some View {
        Button { openCollection(item) } label: {
            Label(item.rawValue, systemImage: item.icon).font(.callout).padding(.horizontal, 14).padding(.vertical, 9)
        }.buttonStyle(.plain).modifier(CapsuleGlass())
    }
    private func shelf(_ title: String, subtitle: String, scenes: [Landscape]) -> some View {
        WallpaperShelf(title: title, subtitle: subtitle, scenes: scenes, openScene: openScene)
    }

}

private struct CapsuleGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) { content.glassEffect(.regular.interactive(), in: Capsule()) }
        else { content.background(.regularMaterial, in: Capsule()) }
    }
}

private struct WallpaperShelf: View {
    let title: String
    let subtitle: String
    let scenes: [Landscape]
    let openScene: (Landscape) -> Void
    @State private var position = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 23, weight: .semibold)); Text(subtitle).foregroundStyle(.secondary) }
                    Spacer()
                    Button { move(-1, proxy: proxy) } label: { Image(systemName: "chevron.left") }.disabled(position == 0)
                    Button { move(1, proxy: proxy) } label: { Image(systemName: "chevron.right") }.disabled(position >= scenes.count - 1)
                }.buttonStyle(.plain)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(scenes) { scene in WallpaperCard(scene: scene, selected: false) { openScene(scene) }.frame(width: 320).id(scene.id) }
                    }.padding(.vertical, 8)
                }.scrollIndicators(.hidden)
            }
        }
    }
    private func move(_ direction: Int, proxy: ScrollViewProxy) {
        guard !scenes.isEmpty else { return }
        position = min(max(0, position + direction), scenes.count - 1)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { proxy.scrollTo(scenes[position].id, anchor: .leading) }
    }
}

