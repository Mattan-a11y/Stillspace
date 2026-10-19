import SwiftUI
import AppKit

extension WidgetFont {
    var design: Font.Design { switch self { case .rounded: .rounded; case .system: .default; case .serif: .serif; case .mono: .monospaced } }
}
extension WidgetTint {
    var color: Color {
        switch self {
        case .white: .white
        case .cream: Color(red: 1, green: 0.91, blue: 0.73)
        case .mint: Color(red: 0.65, green: 0.95, blue: 0.82)
        case .sky: Color(red: 0.66, green: 0.85, blue: 1)
        case .lavender: Color(red: 0.83, green: 0.75, blue: 1)
        case .pink: Color(red: 1, green: 0.72, blue: 0.83)
        }
    }
}
enum WidgetLayout {
    static func initial(index: Int, corner: String) -> WidgetPosition {
        WidgetPosition(x: corner.contains("left") ? 0.15 : 0.85, y: corner.contains("Bottom") ? max(0.12, 0.9 - Double(index) * 0.11) : min(0.88, 0.1 + Double(index) * 0.11))
    }
    static func box(_ item: DesktopWidget, canvas: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: min(360 * scale, max(1, canvas.width - 24 * scale)), height: min(max(60, item.size * (item.kind == .text ? 3.6 : 1.7)) * scale, max(1, canvas.height - 24 * scale)))
    }
    static func center(_ position: WidgetPosition, box: CGSize, canvas: CGSize) -> CGPoint {
        CGPoint(x: min(max(position.x * canvas.width, box.width / 2), max(box.width / 2, canvas.width - box.width / 2)), y: min(max(position.y * canvas.height, box.height / 2), max(box.height / 2, canvas.height - box.height / 2)))
    }
    static func moved(_ position: WidgetPosition, translation: CGSize, box: CGSize, canvas: CGSize) -> WidgetPosition {
        guard canvas.width > 0, canvas.height > 0 else { return position }
        let origin = center(position, box: box, canvas: canvas)
        let next = center(WidgetPosition(x: (origin.x + translation.width) / canvas.width, y: (origin.y + translation.height) / canvas.height), box: box, canvas: canvas)
        return WidgetPosition(x: next.x / canvas.width, y: next.y / canvas.height)
    }
}
struct DesktopWidgetText: View {
    let item: DesktopWidget
    var scale: CGFloat = 1
    var body: some View {
        Group {
            switch item.kind {
            case .clock: TimelineView(.periodic(from: Calendar.current.dateInterval(of: .minute, for: Date())?.start ?? Date(), by: 60)) { ctx in Text(ctx.date, format: .dateTime.hour().minute()).monospacedDigit() }
            case .date: TimelineView(.periodic(from: .now, by: 60)) { ctx in Text(ctx.date, format: .dateTime.weekday(.wide).month().day()) }
            case .text: Text(item.text)
            case .system: Text("\(ProcessInfo.processInfo.activeProcessorCount) cores · \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB")
            }
        }.font(.system(size: item.size * scale, weight: .light, design: item.font.design))
            .foregroundStyle(item.tint.color.opacity(0.95)).multilineTextAlignment(.center).lineLimit(3)
            .shadow(color: .black.opacity(0.5), radius: 6 * scale)
    }
}
struct WidgetCanvas: View {
    var items: [DesktopWidget]
    var corner: String
    var referenceWidth: CGFloat? = nil
    var body: some View {
        GeometryReader { geometry in
            let scale = referenceWidth.map { geometry.size.width / max(1, $0) } ?? 1
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let box = WidgetLayout.box(item, canvas: geometry.size, scale: scale)
                DesktopWidgetText(item: item, scale: scale).frame(width: box.width, height: box.height)
                    .position(WidgetLayout.center(item.position ?? WidgetLayout.initial(index: index, corner: corner), box: box, canvas: geometry.size))
            }
        }.allowsHitTesting(false)
    }
}

struct WidgetLayoutEditor: View {
    @EnvironmentObject var studio: Studio
    @Environment(\.dismiss) private var dismiss
    @State private var draft: [DesktopWidget] = []
    @State private var enabled = false
    @State private var selected: String?
    @State private var dragOrigin: WidgetPosition?
    @State private var resizingFrom: Double?
    @State private var previewDisplay = 0
    private var reference: CGSize { NSScreen.screens.indices.contains(previewDisplay) ? NSScreen.screens[previewDisplay].frame.size : CGSize(width: 1440, height: 900) }
    private var selectedItem: DesktopWidget? { draft.first { $0.id == selected } }
    private func update(_ action: (inout DesktopWidget) -> Void) { if let index = draft.firstIndex(where: { $0.id == selected }) { action(&draft[index]) } }
    private func binding<T>(_ key: WritableKeyPath<DesktopWidget, T>, fallback: T) -> Binding<T> {
        Binding(get: { selectedItem?[keyPath: key] ?? fallback }, set: { value in update { $0[keyPath: key] = value } })
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Make it yours").font(.title2.weight(.semibold))
                    Text("Drag a widget to place it. Pull its corner to resize.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply to Desktop") { studio.applyWidgetLayout(draft, enabled: enabled); dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.padding(24)
            Divider()
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(studio.current.name).font(.headline)
                        Spacer()
                        Picker("Preview display", selection: $previewDisplay) {
                            ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in Text(screen.localizedName).tag(index) }
                        }.labelsHidden().frame(maxWidth: 220)
                    }
                    GeometryReader { geometry in
                        let scale = geometry.size.width / reference.width
                        ZStack {
                            ScenePreview(scene: studio.current, playing: studio.appActive)
                            if enabled {
                                ForEach(Array(draft.enumerated()), id: \.element.id) { index, item in
                                    let box = WidgetLayout.box(item, canvas: geometry.size, scale: scale)
                                    DesktopWidgetText(item: item, scale: scale)
                                        .frame(width: box.width, height: box.height)
                                        .contentShape(Rectangle())
                                        .background(selected == item.id ? .white.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected == item.id ? .white.opacity(0.8) : .clear))
                                        .overlay(alignment: .bottomTrailing) {
                                            if selected == item.id {
                                                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10)).padding(5).background(.regularMaterial, in: Circle())
                                                    .highPriorityGesture(DragGesture().onChanged { value in
                                                        if resizingFrom == nil { resizingFrom = item.size }
                                                        update { $0.size = min(96, max(12, (resizingFrom ?? item.size) + value.translation.width / max(scale, 0.01) * 0.25)) }
                                                    }.onEnded { _ in resizingFrom = nil })
                                            }
                                        }
                                        .position(WidgetLayout.center(item.position ?? WidgetLayout.initial(index: index, corner: studio.widgetCorner), box: box, canvas: geometry.size))
                                        .onTapGesture { selected = item.id }
                                        .gesture(DragGesture().onChanged { value in
                                            if dragOrigin == nil { dragOrigin = item.position ?? WidgetLayout.initial(index: index, corner: studio.widgetCorner) }
                                            selected = item.id
                                            update { $0.position = WidgetLayout.moved(dragOrigin!, translation: value.translation, box: box, canvas: geometry.size) }
                                        }.onEnded { _ in dragOrigin = nil })
                                }
                            }
                        }.clipShape(RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12)))
                    }.aspectRatio(reference.width / reference.height, contentMode: .fit)
                    Text("Preview changes stay here until you apply. Placement is relative to each screen; all displays share this layout.").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity)
                inspector.frame(width: 230)
            }.padding(24)
        }.frame(minWidth: 900, minHeight: 620).preferredColorScheme(.dark)
            .onAppear {
                draft = studio.widgetItems; enabled = studio.widgets
                for index in draft.indices where draft[index].position == nil { draft[index].position = WidgetLayout.initial(index: index, corner: studio.widgetCorner) }
                selected = draft.first?.id
            }
    }
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Show widgets", isOn: $enabled)
                Menu("Add widget", systemImage: "plus") {
                    ForEach(WidgetKind.allCases) { kind in
                        Button(kind.rawValue) {
                            let widget = DesktopWidget(kind: kind, size: kind == .clock ? 48 : 24, position: WidgetPosition(x: 0.5, y: 0.5))
                            draft.append(widget); selected = widget.id; enabled = true
                        }
                    }
                }.disabled(draft.count >= 16)
                ForEach(draft) { item in
                    Button { selected = item.id } label: {
                        HStack { Text(item.kind.rawValue); Spacer(); if selected == item.id { Image(systemName: "checkmark") } }.frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
                Divider()
                if let item = selectedItem {
                    Text(item.kind.rawValue).font(.headline)
                    if item.kind == .text { TextField("Your text", text: binding(\.text, fallback: ""), axis: .vertical).lineLimit(3...5).onChange(of: draft) { _, _ in if let text = selectedItem?.text, text.count > 1000 { update { $0.text = String(text.prefix(1000)) } } } }
                    Picker("Font", selection: binding(\.font, fallback: .rounded)) { ForEach(WidgetFont.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Color", selection: binding(\.tint, fallback: .white)) { ForEach(WidgetTint.allCases) { Label($0.rawValue, systemImage: "circle.fill").foregroundStyle($0.color).tag($0) } }
                    Text("Size · \(Int(item.size)) pt").font(.caption).foregroundStyle(.secondary)
                    Slider(value: binding(\.size, fallback: 28), in: 12...96, step: 1)
                    Button("Center widget") { update { $0.position = WidgetPosition(x: 0.5, y: 0.5) } }
                    Button("Remove widget", role: .destructive) { draft.removeAll { $0.id == item.id }; selected = draft.first?.id; if draft.isEmpty { enabled = false } }
                } else { Text("Add a widget to begin. Your desktop can stay completely blank.").font(.callout).foregroundStyle(.secondary) }
            }
        }
    }
}
