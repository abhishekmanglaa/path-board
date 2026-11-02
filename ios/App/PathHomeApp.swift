import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Must exist on every launch, including background relaunches from a
        // location event, so the pending update gets delivered to a delegate.
        _ = LocationMonitor.shared
        return true
    }
}

@main
struct PathHomeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(monitor: .shared)
                .onOpenURL(perform: open)
                .onChange(of: scenePhase) { _, phase in
                    LocationMonitor.shared.setForeground(phase == .active)
                }
        }
    }

    /// pathhome://walk?station=33S → Google Maps walking directions to that station.
    private func open(_ url: URL) {
        guard url.host == "walk",
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "station" })?.value,
              let station = Station.byID[id] else { return }
        // The app scheme goes straight into Google Maps; if it isn't installed,
        // open() reports failure and the web link takes over.
        var components = URLComponents(string: "comgooglemaps://")!
        components.queryItems = [URLQueryItem(name: "daddr", value: station.mapsQuery),
                                 URLQueryItem(name: "directionsmode", value: "walking")]
        let app = components.url!
        UIApplication.shared.open(app) { opened in
            if !opened { UIApplication.shared.open(station.googleMapsWalkingURL) }
        }
    }
}
