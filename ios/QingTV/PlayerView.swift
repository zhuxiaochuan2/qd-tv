import SwiftUI
import AVFoundation

/// 单集播放（从详情页/继续观看进来）：解析完直接交给爱奇艺风格播放器
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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let r = real, let u = URL(string: r) {
                IQPlayer(url: u,
                         headers: headers,
                         title: title,
                         resumeAt: resumeAt,
                         onProgress: { pos, dur in
                             store.recordProgress(title: title, pic: pic, site: site, line: line,
                                                  epName: epName, epURL: urlString,
                                                  position: pos, duration: dur)
                         },
                         onFail: nil,
                         onSource: nil,
                         onEpisodes: nil)
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
        }
        .navigationTitle("")
        .navigationBarHidden(true)
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
