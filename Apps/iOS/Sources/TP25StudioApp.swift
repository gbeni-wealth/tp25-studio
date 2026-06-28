import SwiftUI
import SwiftData
import DeviceManager
import ThemeEngine
import CloudSync
import SharedUI

@main
struct TP25StudioApp: App {
    @State private var fleet = FleetController()
    @State private var player = ThemePlayer()

    let container = CloudSync.makeContainerWithFallback()

    var body: some Scene {
        WindowGroup {
            RootView(fleet: fleet, player: player)
                .preferredColorScheme(.dark)   // cinema console: dark-first
                .tint(ConsolePalette.accent)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Bindable var fleet: FleetController
    let player: ThemePlayer

    var body: some View {
        TabView {
            HomeView(fleet: fleet)
                .tabItem { Label("Lights", systemImage: "lightbulb.2.fill") }

            ThemesGalleryView(fleet: fleet, player: player)
                .tabItem { Label("Themes", systemImage: "paintpalette.fill") }

            RandomEngineView(fleet: fleet, player: player)
                .tabItem { Label("Random", systemImage: "dice.fill") }

            PresetsView(fleet: fleet)
                .tabItem { Label("Presets", systemImage: "square.stack.3d.up.fill") }

            MusicReactiveView(fleet: fleet)
                .tabItem { Label("Music", systemImage: "music.note") }

            ReverseEngineeringView(fleet: fleet)
                .tabItem { Label("Discover", systemImage: "wrench.and.screwdriver.fill") }
        }
    }
}
