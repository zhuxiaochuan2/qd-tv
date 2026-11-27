import SwiftUI
import AVFoundation
import UIKit
import MediaPlayer

/// 投屏按钮（系统 AirPlay 路由选择器）
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = .systemGreen
        v.prioritizesVideoDevices = true
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// 系统音量控制（MPVolumeView 里的 UISlider 是唯一公开途径）
final class VolumeControl {
    static let shared = VolumeControl()
    private let box = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 20, height: 20))

    var current: Float { AVAudioSession.sharedInstance().outputVolume }

    private var slider: UISlider? {
        box.subviews.compactMap { $0 as? UISlider }.first
    }

    func attach() {
        guard box.superview == nil, let w = UIApplication.shared.windows.first else { return }
        box.alpha = 0.01
        box.showsVolumeSlider = true
        w.addSubview(box)
    }

    func set(_ v: Float) {
        attach()
        guard let sl = slider else { return }
        DispatchQueue.main.async { sl.value = min(1, max(0, v)) }
    }
}

// 爱奇艺风格的绿
private let iqGreen = Color(red: 0.13, green: 0.78, blue: 0.28)

/// 纯 AVPlayerLayer 容器（不用 AVPlayerViewController，UI 才能自己做）
final class PlayerHostView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerHostView {
        let v = PlayerHostView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }
}

/// 仿爱奇艺播放器：顶栏返回+标题，底栏 时间/进度/总时长 + 播放暂停/+15/-15/倍速/线路/选集/全屏
struct IQPlayer: View {
    let url: URL
    let headers: [String: String]
    var title: String = ""
    var resumeAt: Double = 0
    var onProgress: ((Double, Double) -> Void)? = nil
    var onFail: (() -> Void)? = nil
    var onSource: (() -> Void)? = nil
    var onEpisodes: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil
    var compact: Bool = false          // 嵌在详情页顶部的小播放器
    var onFullscreen: (() -> Void)? = nil   // 点全屏时交给外层做"真全屏"

    @Environment(\.presentationMode) private var pm

    @State private var player: AVPlayer?
    @State private var timeObs: Any?
    @State private var statusObs: NSKeyValueObservation?
    @State private var isPlaying = false
    @State private var position: Double = 0
    @State private var duration: Double = 0
    @State private var showCtrl = true
    @State private var dragging = false
    @State private var dragValue: Double = 0
    @State private var rate: Float = 1.0
    @State private var hideTask: Task<Void, Never>?
    @State private var toast: String?
    @State private var hudText: String?
    @State private var hudIcon = "sun.max.fill"
    @State private var dragStartY: CGFloat?
    @State private var dragStartValue: CGFloat = 0
    @State private var dragIsBrightness = true
    @State private var hudTask: Task<Void, Never>?

    private var shownPos: Double { dragging ? dragValue : position }
    private var progress: Double { duration > 1 ? min(1, max(0, shownPos / duration)) : 0 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let p = player {
                PlayerLayerView(player: p).ignoresSafeArea()
            }

            // 手势层：左半屏上下滑=亮度，右半屏上下滑=音量；单击显隐控件，双击切全屏
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onChanged { v in
                                if dragStartY == nil {
                                    dragStartY = v.startLocation.y
                                    dragIsBrightness = v.startLocation.x < geo.size.width / 2
                                    dragStartValue = dragIsBrightness
                                        ? CGFloat(UIScreen.main.brightness)
                                        : CGFloat(VolumeControl.shared.current)
                                }
                                let span = max(120, geo.size.height * 0.7)
                                let dy = ((dragStartY ?? v.startLocation.y) - v.location.y) / span
                                let nv = min(1, max(0, dragStartValue + dy))
                                if dragIsBrightness {
                                    UIScreen.main.brightness = nv
                                    hudIcon = "sun.max.fill"
                                    hudText = "亮度 \(Int(nv * 100))%"
                                } else {
                                    VolumeControl.shared.set(Float(nv))
                                    hudIcon = "speaker.wave.2.fill"
                                    hudText = "音量 \(Int(nv * 100))%"
                                }
                                scheduleHudHide()
                            }
                            .onEnded { _ in dragStartY = nil }
                    )
                    .onTapGesture(count: 2) { toggleFullscreen() }
                    .onTapGesture { toggleControls() }
            }
            .ignoresSafeArea()

            if showCtrl {
                (compact ? AnyView(compactControls) : AnyView(controls)).transition(.opacity)
            }

            if let h = hudText {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: hudIcon).font(.system(size: 14, weight: .semibold))
                        Text(h).font(.system(size: 13, weight: .semibold).monospacedDigit())
                    }
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .padding(.bottom, 150)
                }
                .allowsHitTesting(false)
            }

            if let t = toast {
                VStack {
                    Spacer()
                    Text(t)
                        .font(.caption.bold())
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(.bottom, 130)
                }
                .allowsHitTesting(false)
            }
        }
        .statusBarHidden(showCtrl ? false : true)
        .onAppear {
            Orientation.unlock()          // 允许四方向，转设备就能全屏
            start()
        }
        .onDisappear {
            Orientation.portrait()        // 退出回竖屏
            stop()
        }
    }

    // MARK: - 控件层

    private var controls: some View {
        VStack(spacing: 0) {
            // 顶栏
            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                if onSource != nil {
                    Button { onSource?() } label: {
                        Text("换源").font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.white.opacity(0.16))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
                Button {
                    if let c = onClose { c() } else { pm.wrappedValue.dismiss() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 18)
            .background(
                LinearGradient(colors: [Color.black.opacity(0.75), .clear],
                               startPoint: .top, endPoint: .bottom)
            )

            Spacer()

            // 中间播放/暂停
            Button { togglePlay() } label: {
                ZStack {
                    Circle().fill(Color.black.opacity(0.35)).frame(width: 64, height: 64)
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            Spacer()

            // 底栏
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text(timeText(shownPos))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(.white)
                        .frame(width: 46, alignment: .leading)

                    seekBar

                    Text(timeText(duration))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(.white.opacity(0.75))
                        .frame(width: 56, alignment: .trailing)
                }

                HStack(spacing: 18) {
                    Button { togglePlay() } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Button { seek(by: 15) } label: {
                        Image(systemName: "goforward.15")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Button { seek(by: -15) } label: {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    Menu {
                        ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                            Button("\(r, specifier: "%g")x") { setRate(Float(r)) }
                        }
                    } label: {
                        Text(rate == 1.0 ? "倍速" : String(format: "%gx", rate))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    if onEpisodes != nil {
                        Button { onEpisodes?() } label: {
                            Text("选集").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                        }
                    }

                    Button { toggleFullscreen() } label: {
                        Image(systemName: Orientation.isLandscapeNow
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 10)
            .background(
                LinearGradient(colors: [.clear, Color.black.opacity(0.8)],
                               startPoint: .top, endPoint: .bottom)
            )
        }
        .padding(.bottom, 6)
    }

    // MARK: - 嵌入模式控件（详情页顶部）

    private var compactControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    if let c = onClose { c() } else { pm.wrappedValue.dismiss() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                AirPlayButton()
                    .frame(width: 34, height: 34)

                Button {
                    if let f = onFullscreen { f() } else { toggleFullscreen() }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            Spacer()

            HStack(spacing: 8) {
                Button { togglePlay() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(timeText(shownPos))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundColor(.white)
                seekBar
                Text(timeText(duration))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            .background(
                LinearGradient(colors: [.clear, Color.black.opacity(0.6)],
                               startPoint: .top, endPoint: .bottom)
            )
        }
    }

    private var seekBar: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                    .frame(height: 3)
                Capsule().fill(iqGreen)
                    .frame(width: max(0, g.size.width * progress), height: 3)
                Circle().fill(iqGreen)
                    .frame(width: dragging ? 14 : 10, height: dragging ? 14 : 10)
                    .offset(x: max(0, g.size.width * progress - (dragging ? 7 : 5)))
            }
            .frame(height: 26)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragging = true
                        let p = min(max(0, v.location.x / max(1, g.size.width)), 1)
                        dragValue = p * max(duration, 0)
                        scheduleHide()
                    }
                    .onEnded { _ in
                        let t = dragValue
                        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600),
                                     toleranceBefore: .zero,
                                     toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
                        position = t
                        dragging = false
                        scheduleHide()
                    }
            )
        }
        .frame(height: 26)
    }

    // MARK: - 播放器

    private func start() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetooth])
        try? s.setActive(true)

        var options: [String: Any] = [:]
        if !headers.isEmpty { options["AVURLAssetHTTPHeaderFieldsKey"] = headers }
        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        let p = AVPlayer(playerItem: item)
        p.isMuted = false
        p.volume = 1.0
        p.allowsExternalPlayback = true

        statusObs = item.observe(\.status, options: [.new, .initial]) { it, _ in
            if it.status == .failed { DispatchQueue.main.async { onFail?() } }
            if it.status == .readyToPlay {
                DispatchQueue.main.async {
                    if resumeAt > 5 {
                        p.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600),
                               toleranceBefore: .zero,
                               toleranceAfter: CMTime(seconds: 2, preferredTimescale: 600))
                        position = resumeAt
                    }
                    p.play()
                    isPlaying = true
                    duration = it.duration.seconds.isFinite ? it.duration.seconds : 0
                    scheduleHide()
                }
            }
        }

        timeObs = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { t in
            guard !dragging else { return }
            let pos = t.seconds
            if pos.isFinite { position = pos }
            let d = item.duration.seconds
            if d.isFinite, d > 0 { duration = d }
            if let cb = onProgress, pos.isFinite, pos > 0 { cb(pos, d.isFinite ? d : 0) }
        }

        player = p
        showCtrl = true
        scheduleHide()
    }

    private func stop() {
        hideTask?.cancel()
        if let o = timeObs { player?.removeTimeObserver(o) }
        timeObs = nil
        statusObs?.invalidate()
        statusObs = nil
        player?.pause()
        player = nil
    }

    private func toggleFullscreen() {
        if Orientation.isLandscapeNow {
            Orientation.portrait()
            flash("退出全屏")
        } else {
            Orientation.landscape()
            flash("全屏")
        }
        scheduleHide()
    }

    private func togglePlay() {
        guard let p = player else { return }
        if isPlaying {
            p.pause(); isPlaying = false; showCtrl = true; hideTask?.cancel()
        } else {
            p.play(); p.rate = rate; isPlaying = true; scheduleHide()
        }
    }

    private func setRate(_ r: Float) {
        rate = r
        if isPlaying { player?.rate = r }
        flash("倍速 \(String(format: "%g", r))x")
    }

    private func seek(by seconds: Double) {
        guard let p = player else { return }
        let target = min(max(0, position + seconds), max(0, duration - 1))
        p.seek(to: CMTime(seconds: target, preferredTimescale: 600),
               toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
        position = target
        flash(seconds > 0 ? "快进 \(Int(seconds)) 秒" : "快退 \(Int(-seconds)) 秒")
        scheduleHide()
    }

    private func toggleControls() {
        showCtrl.toggle()
        if showCtrl { scheduleHide() } else { hideTask?.cancel() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard isPlaying else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                await MainActor.run { withAnimation(.easeOut(duration: 0.2)) { showCtrl = false } }
            }
        }
    }

    private func scheduleHudHide() {
        hudTask?.cancel()
        hudTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            if !Task.isCancelled {
                await MainActor.run { hudText = nil }
            }
        }
    }

    private func flash(_ msg: String) {
        toast = msg
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run { if toast == msg { toast = nil } }
        }
    }
}
