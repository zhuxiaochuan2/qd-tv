import SwiftUI
import AVKit
import AVFoundation

struct PlayerView: View {
    @EnvironmentObject var store: Store

    let urlString: String
    let title: String
    var pic: String = ""
    var site: String = ""
    var line: String = ""
    var epName: String = ""
    var resumeAt: Double = 0

    @State private var real: String?
    @State private var headers: [String: String] = [:]
    @State private var err: String?
    @State private var hint: String?
    @State private var rate: Float = 1.0
    @State private var seekRequest: Double = 0
    @State private var landscape: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let r = real, let u = URL(string: r) {
                VideoPlayer(url: u,
                            headers: headers,
                            resumeAt: resumeAt,
                            rate: rate,
                            seekTo: seekRequest,
                            onNoAudio: { hint = "这条线路可能真的没声音，试着换一条线路" },
                            onReady: nil,
                            onFail: nil,
                            onProgress: { pos, dur in
                                store.recordProgress(title: title, pic: pic, site: site, line: line,
                                                     epName: epName, epURL: urlString,
                                                     position: pos, duration: dur)
                            })
                    .ignoresSafeArea()
            } else if let e = err {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(e).font(.callout)
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("解析播放地址…").tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if real != nil {
                playbackTools
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

    private var playbackTools: some View {
        HStack(spacing: 8) {
            Button {
                landscape.toggle()
                if landscape { Orientation.landscape() } else { Orientation.portrait() }
            } label: {
                Image(systemName: landscape ? "rectangle.portrait.arrowtriangle.2.inward"
                                            : "rectangle.landscape.rotate")
                    .font(.caption.bold())
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(Color.black.opacity(0.55))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button { seekRequest += 60 } label: {
                Text("+60s")
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.black.opacity(0.55))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Menu {
                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                    Button("\(r, specifier: "%g")x") { rate = Float(r) }
                }
            } label: {
                Text(rate == 1.0 ? "1x" : String(format: "%gx", rate))
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.black.opacity(0.55))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 8)
        .padding(.trailing, 12)
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

/// 带 Referer 的 AVPlayer；离场彻底收摊。
/// onFail 会在「加载失败」或「12 秒还没 ready」时触发，交给上层自动换源。
struct VideoPlayer: UIViewControllerRepresentable {
    let url: URL
    let headers: [String: String]
    var resumeAt: Double = 0
    var rate: Float = 1.0
    var seekTo: Double = 0
    var onNoAudio: (() -> Void)? = nil
    var onReady: (() -> Void)? = nil
    var onFail: (() -> Void)? = nil
    var onProgress: ((Double, Double) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onNoAudio: onNoAudio, onReady: onReady, onFail: onFail, onProgress: onProgress)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        var options: [String: Any] = [:]
        if !headers.isEmpty { options["AVURLAssetHTTPHeaderFieldsKey"] = headers }
        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        player.isMuted = false
        player.volume = 1.0

        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true

        context.coordinator.attach(player: player, item: item, resumeAt: resumeAt, rate: rate)
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        context.coordinator.apply(rate: rate, seekTo: seekTo)
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        uiViewController.player?.pause()
        uiViewController.player?.replaceCurrentItem(with: nil)
        uiViewController.player = nil
        coordinator.stop()
    }

    final class Coordinator {
        private let onNoAudio: (() -> Void)?
        private let onReady: (() -> Void)?
        private let onFail: (() -> Void)?
        private let onProgress: ((Double, Double) -> Void)?

        private var obs: NSKeyValueObservation?
        private var timeObs: Any?
        private var watchdog: DispatchWorkItem?
        private var checked = false
        private var failed = false
        private var lastRate: Float = 1.0
        private var lastSeek: Double = 0
        private weak var player: AVPlayer?
        private var item: AVPlayerItem?

        init(onNoAudio: (() -> Void)?, onReady: (() -> Void)?,
             onFail: (() -> Void)?, onProgress: ((Double, Double) -> Void)?) {
            self.onNoAudio = onNoAudio
            self.onReady = onReady
            self.onFail = onFail
            self.onProgress = onProgress
        }

        deinit { stop() }

        func attach(player: AVPlayer, item: AVPlayerItem, resumeAt: Double, rate: Float) {
            self.player = player
            self.item = item
            self.lastRate = rate

            // 12 秒还没 ready 就认为这条线路不行
            let wd = DispatchWorkItem { [weak self] in
                guard let self = self, !self.failed else { return }
                if item.status != .readyToPlay {
                    self.fail()
                }
            }
            watchdog = wd
            DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: wd)

            obs = item.observe(\.status, options: [.new, .initial]) { [weak self] it, _ in
                guard let self = self else { return }
                if it.status == .failed {
                    self.fail()
                    return
                }
                guard it.status == .readyToPlay else { return }
                self.watchdog?.cancel()
                if resumeAt > 5 {
                    player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600),
                                toleranceBefore: .zero,
                                toleranceAfter: CMTime(seconds: 2, preferredTimescale: 600))
                }
                player.play()
                if rate != 1.0 { player.rate = rate }
                self.onReady?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    guard !self.checked else { return }
                    self.checked = true
                    guard !it.tracks.isEmpty else { return }
                    let audio = it.tracks.filter { $0.assetTrack?.mediaType == .audio }
                    if audio.isEmpty { self.onNoAudio?() }
                }
            }

            timeObs = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 5, preferredTimescale: 600), queue: .main
            ) { [weak self] t in
                guard let self = self, let it = self.item else { return }
                let dur = it.duration.seconds
                let pos = t.seconds
                if pos.isFinite, pos > 0 {
                    DispatchQueue.main.async { self.onProgress?(pos, dur.isFinite ? dur : 0) }
                }
            }
        }

        private func fail() {
            guard !failed else { return }
            failed = true
            watchdog?.cancel()
            DispatchQueue.main.async { self.onFail?() }
        }

        func apply(rate: Float, seekTo: Double) {
            guard let p = player else { return }
            if abs(rate - lastRate) > 0.001 {
                lastRate = rate
                if p.timeControlStatus == .playing { p.rate = rate }
            }
            if seekTo > lastSeek + 0.5 {
                lastSeek = seekTo
                let target = min(p.currentTime().seconds + 60, max(0, (item?.duration.seconds ?? 0) - 2))
                p.seek(to: CMTime(seconds: target, preferredTimescale: 600))
            }
        }

        func stop() {
            watchdog?.cancel()
            watchdog = nil
            if let t = timeObs, let p = player { p.removeTimeObserver(t) }
            timeObs = nil
            obs?.invalidate()
            obs = nil
            player?.pause()
            player = nil
            item = nil
        }
    }
}
