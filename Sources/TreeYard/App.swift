import AppKit
import SwiftUI

@main
enum Main {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
            AppIcon.render(to: args[i + 1])
            return
        }
        TreeYardApp.main()
    }
}

struct TreeYardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store()

    init() {
        Fonts.register()
    }

    var body: some Scene {
        Window("Worktrees", id: "main") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 460, minHeight: 420)
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 1160, height: 780)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Directory…") { store.pickRoot() }.keyboardShortcut("o")
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh") { store.refreshNow() }.keyboardShortcut("r")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
            snapshotIfAsked()
        #endif
    }

    #if DEBUG
    /// Development aid: `TREEYARD_SNAPSHOT=/path.png` writes a picture of the window every few seconds,
    /// for checking the layout without screen-recording permission.
    private func snapshotIfAsked() {
        guard let path = ProcessInfo.processInfo.environment["TREEYARD_SNAPSHOT"] else { return }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                let view = window.contentView?.superview,
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
    #endif
}

/// The Dock icon, drawn from the same mark as the header. `--render-icon <png>` writes it out for the build.
enum AppIcon {
    struct Art: View {
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 185, style: .continuous)
                    .fill(LinearGradient(colors: [T.raised, T.chrome], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 185, style: .continuous).strokeBorder(T.line, lineWidth: 4))
                    .frame(width: 824, height: 824)
                SVGShape("M0 14.6 Q4.5 14.1 9 14.5 T18 14.3 V18 H0Z").fill(T.bark.opacity(0.14))
                    .frame(width: 824, height: 824)
                    .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
                SVGShape("M9 2.5 4.5 9h2.25L4 13h10l-2.75-4h2.25Z").fill(T.leaf.opacity(0.55))
                    .frame(width: 720, height: 720)
                SVGShape("M9 2.5 4.5 9h2.25L4 13h10l-2.75-4h2.25ZM9 13v2.5")
                    .stroke(T.matrix, style: StrokeStyle(lineWidth: 34, lineCap: .round, lineJoin: .round))
                    .frame(width: 720, height: 720)
            }
            .frame(width: 1024, height: 1024)
        }
    }

    @MainActor static func render(to path: String) {
        let renderer = ImageRenderer(content: Art())
        renderer.scale = 1
        guard let image = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
