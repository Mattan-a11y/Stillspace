import Foundation
import SwiftUI
import AppKit

// Renders the real app views using synthetic demo data in a separate defaults domain.
// Never applies a desktop wallpaper or prepares the experimental screen saver.
@main struct RenderDocumentation {
    @MainActor static func main() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited); NSApp.appearance = NSAppearance(named: .darkAqua)
        let folder=URL(fileURLWithPath:(CommandLine.arguments.dropFirst().first ?? Bundle.main.object(forInfoDictionaryKey: "StillspaceDocsRoot") as? String ?? FileManager.default.currentDirectoryPath)).standardizedFileURL
        let media=folder.appendingPathComponent("Demo/Northern-Drift.mp4")
        let scene=Landscape(id:"northern-drift",name:"Northern Drift",subtitle:"Original demo · Silent aurora loop",palette:2,file:media.path)
        UserDefaults.standard.setVolatileDomain(["restorePlayback":false,"wasPlaying":false,"scene":"night","automatic":false,"widgets":false,"imports":try JSONEncoder().encode([scene]),"favorites":["night","northern-drift"]],forName:UserDefaults.argumentDomain)
        let studio=Studio(); studio.packs=[]; studio.appActive=false
        defer { studio.shutdown() }
        try await render(StudioView().environmentObject(studio).preferredColorScheme(.dark),size:NSSize(width:1140,height:760),to:folder.appendingPathComponent("Docs/Images/home.png"))
        studio.selected="northern-drift"
        try await render(MenuBarContent().environmentObject(studio).preferredColorScheme(.dark),size:NSSize(width:300,height:535),to:folder.appendingPathComponent("Docs/Images/quick-controls.png"))
        let widget=ZStack {
            LandscapeView(palette:2)
            WidgetCanvas(items:[DesktopWidget(kind:.text,text:"A little space to think.",size:44,position:WidgetPosition(x:0.5,y:0.55),font:.serif,tint:.cream),DesktopWidget(kind:.clock,size:56,position:WidgetPosition(x:0.5,y:0.39),font:.mono,tint:.white)],corner:"Top right",referenceWidth:1440)
        }.frame(width:1140,height:641)
        let renderer=ImageRenderer(content:widget); renderer.scale=1
        guard let image=renderer.cgImage,let png=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else {throw NSError(domain:"DocsWidget",code:1)}
        try png.write(to:folder.appendingPathComponent("Docs/Images/widgets.png"))
        print("Rendered actual Stillspace views with demo-only data.")
        if CommandLine.arguments.contains("--preview") || CommandLine.arguments.count == 1 {
            NSApp.setActivationPolicy(.regular)
            let content = StudioView().environmentObject(studio).preferredColorScheme(.dark)
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1140, height: 760), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Stillspace · Demo"; window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(rootView: content)
            NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
            runPreviewLoop()
            window.contentView = nil; window.close()
        }
    }
    @MainActor static func runPreviewLoop() { NSApp.run() }
    @MainActor static func render<V:View>(_ content:V,size:NSSize,to url:URL) async throws {
        let host=NSHostingView(rootView:content.environment(\.colorScheme, .dark).frame(width:size.width,height:size.height).background(Color(red:0.055,green:0.075,blue:0.09)))
        let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false; window.backgroundColor=NSColor(calibratedWhite:0.08,alpha:1)
        window.contentView=host; host.frame=NSRect(origin:.zero,size:size); host.layoutSubtreeIfNeeded()
        try await Task.sleep(for:.milliseconds(800))
        host.displayIfNeeded()
        guard let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else {throw NSError(domain:"DocsBitmap",code:1)}
        host.cacheDisplay(in:host.bounds,to:bitmap)
        guard let png=bitmap.representation(using:.png,properties:[:]) else {throw NSError(domain:"DocsPNG",code:1)}
        try png.write(to:url); window.contentView=nil; window.close()
    }
}
