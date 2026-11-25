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
                    // 只有在「播放起来 3 秒后仍然一条音轨都没有」时才提示
                    hint = "这条线路可能真的没声音，试着换一条线路"
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
                        .background(Color.black.opacity(0.75))
                        .foregroundColor(.orange)
                        .cornerRadius(10)
                        .padding(.bottom, 60)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await resolve() }
    }

    private func resolve() async {
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

    func makeCoordinator() -> Coordinator { Coordinator(onNoAudio: onNoAudio) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        var options: [String: Any] = [:]
        if !headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = headers
        }
        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        player.isMuted = false
        player.volume = 1.0

        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.entersFullScreenWhenPlaybackBegins = true
        player.play()

        context.coordinator.watch(item)
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    final class Coordinator {
        private let onNoAudio: (() -> Void)?
        private var obs: NSKeyValueObservation?
        private var checked = false

        init(onNoAudio: (() -> Void)?) { self.onNoAudio = onNoAudio }

        /// HLS 的音轨要等播放真正起来才出现，早查一定是空的
        /// （之前那版就是查早了，导致每条线路都误报"没有音轨"）
        func watch(_ item: AVPlayerItem) {
            obs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
                guard let self = self, it.status == .readyToPlay else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    guard !self.checked else { return }
                    self.checked = true
                    let audioTracks = it.tracks.filter { t in
                        t.assetTrack?.mediaType == .audio
                    }
                    // tracks 为空多半是还没解析完，别急着下结论
                    guard !it.tracks.isEmpty else { return }
                    if audioTracks.isEmpty {
                        self.onNoAudio?()
                    }
                }
            }
        }
    }
}
