import SwiftUI
import AVFoundation

@main
struct QingTVApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = Store()

    init() {
        // 音频会话：抬起播放级别，静音键不影响
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetooth])
        try? s.setActive(true)

        // 图片缓存调大，翻页不重复下
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024,
                                   diskCapacity: 256 * 1024 * 1024,
                                   diskPath: "qd_image_cache")
    }

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        TabView {
            DiscoverView()
                .tabItem { Label("发现", systemImage: "sparkles.tv") }
            LiveView()
                .tabItem { Label("直播", systemImage: "dot.radiowaves.left.and.right") }
            SettingsView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}
