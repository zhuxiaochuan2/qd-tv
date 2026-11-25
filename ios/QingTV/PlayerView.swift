import SwiftUI
import AVKit
import AVFoundation

struct PlayerView: View {
    let urlString: String
    let title: String

    @State private var real: String?
    @State private var headers: [String: String] = [:]
    @State private var err: String?
    @State private var hint: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let r = real, let u = URL(string: r) {
                VideoPlayer(url: u, headers: headers) {
                    hint = "这条线路没有音轨，返回换一条试试"
                }
                .ignoresSafeArea()
            } else if let e = err {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(e).font(.callout)
                }
                .foregroundColor(.secondary)
            } else {
                ProgressView("解析播放地址…").tint(.white)
            }

            if let h = hint {
                VStack {
                    Spacer()
                    Text(h)
                        .font(.caption)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.orange)
                        .cornerRadius(10)
                        .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await resolve() }
    }

    private func resolve() async {
        // 每次进播放页都重新激活音频会话，防止被别的 App 抢走
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetooth])
        try? s.setActive(true)

        let m = await Resolver.m3u8(from: urlString)
        let h = Resolver.headers(for: urlString)
        await MainActor.run {
            if let m = m { real = m; headers = h }
            else { err = "这条线路解析不出来，返回换一条" }
        }
    }
}

/// 带 Referer 的 AVPlayer：防盗链源也能播
struct VideoPlayer: UIViewControllerRepresentable {
    let url: URL
    let headers: [String: String]
    var onNoAudio: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        var options: [String: Any] = [:]
        if !headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = headers
        }
        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        player.isMuted = false          // 别让系统默认静音
        player.volume = 1.0

        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.entersFullScreenWhenPlaybackBegins = true
        player.play()

        // 探测音轨：有些线路本来就是纯视频（无音轨），给个提示而不是让你干着急
        asset.loadTracks(withMediaType: .audio) { tracks, _ in
            if (tracks?.isEmpty ?? true) {
                DispatchQueue.main.async { onNoAudio?() }
            }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
