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
                        .clipShape(RoundedRectangle(cornerRadius: 10))
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

/// 带 Referer 的 AVPlayer。
/// 返回上一页时要把 player 停掉、观察者释放，否则偶发闪退。
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

        context.coordinator.player = player
        context.coordinator.watch(item)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let p = vc.player, p.currentItem != nil { p.play() }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    /// 关键：离场时彻底收摊，避免 AVPlayer 在后台被释放导致的崩溃
    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        uiViewController.player?.pause()
        uiViewController.player?.replaceCurrentItem(with: nil)
        uiViewController.player = nil
        coordinator.stop()
    }

    final class Coordinator {
        private let onNoAudio: (() -> Void)?
        private var obs: NSKeyValueObservation?
        private var checked = false
        weak var player: AVPlayer?

        init(onNoAudio: (() -> Void)?) { self.onNoAudio = onNoAudio }

        func stop() {
            obs?.invalidate()
            obs = nil
            player?.pause()
            player = nil
        }

        deinit { obs?.invalidate() }

        /// HLS 的音轨要等播放真正起来才出现，早查一定是空的
        func watch(_ item: AVPlayerItem) {
            obs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
                guard let self = self, it.status == .readyToPlay else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    guard !self.checked else { return }
                    self.checked = true
                    guard !it.tracks.isEmpty else { return }
                    let audioTracks = it.tracks.filter { $0.assetTrack?.mediaType == .audio }
                    if audioTracks.isEmpty { self.onNoAudio?() }
                }
            }
        }
    }
}
