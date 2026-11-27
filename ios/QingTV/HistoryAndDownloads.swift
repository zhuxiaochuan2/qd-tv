import SwiftUI

/// 我的收藏 / 观看记录 / 我的下载 三个列表页

struct HistoryView: View {
    @EnvironmentObject var store: Store
    @State private var play: PlayVideo?

    var body: some View {
        ZStack {
            BrandBackground()
            if store.history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundColor(Theme.dim)
                    Text("还没有观看记录").font(.caption).foregroundColor(Theme.dim)
                }
            } else {
                List {
                    ForEach(store.history) { h in
                        Button {
                            play = PlayVideo(urlString: h.epURL, title: h.title, pic: h.pic,
                                             site: h.site, line: h.line, epName: h.epName,
                                             resumeAt: h.position)
                        } label: {
                            HStack(spacing: 10) {
                                NetImage(url: h.pic)
                                    .frame(width: 56, height: 78)
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(h.title).font(.footnote.bold()).foregroundColor(Theme.text).lineLimit(1)
                                    Text("\(h.epName) · \(h.site)").font(.caption2).foregroundColor(Theme.dim)
                                    HStack(spacing: 6) {
                                        ProgressView(value: min(1, max(0, h.progress)))
                                            .frame(width: 110).tint(Theme.warm)
                                        Text(timeText(h.position)).font(.system(size: 9).monospacedDigit())
                                            .foregroundColor(Theme.dim)
                                    }
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { idx in
                        for i in idx { store.removeHistory(title: store.history[i].title) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("观看记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("清空") { store.clearHistory() }
        }
        .fullScreenCover(item: $play) { v in
            PlayerView(urlString: v.urlString, title: v.title, pic: v.pic,
                       site: v.site, line: v.line, epName: v.epName, resumeAt: v.resumeAt)
                .environmentObject(store)
        }
    }
}

struct DownloadsView: View {
    @EnvironmentObject var store: Store
    @State private var playURL: URL?
    @State private var showPlay = false

    private let fm = FileManager.default

    var body: some View {
        ZStack {
            BrandBackground()
            if store.downloads.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle").font(.largeTitle).foregroundColor(Theme.dim)
                    Text("还没有下载，播放页点「下载」").font(.caption).foregroundColor(Theme.dim)
                }
            } else {
                List {
                    ForEach(store.downloads) { d in
                        Button {
                            let u = Downloader.shared.localURL(d.fileName)
                            if fm.fileExists(atPath: u.path) {
                                playURL = u
                                showPlay = true
                            } else {
                                store.removeDownload(d.id)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                NetImage(url: d.pic)
                                    .frame(width: 56, height: 78)
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(d.title).font(.footnote.bold()).foregroundColor(Theme.text).lineLimit(1)
                                    Text(byteText(d.size)).font(.caption2).foregroundColor(Theme.dim)
                                    Text(d.date, style: .date).font(.system(size: 9)).foregroundColor(Theme.dim)
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .font(.title3).foregroundColor(Theme.accent)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { idx in
                        for i in idx {
                            let d = store.downloads[i]
                            Downloader.shared.delete(d.fileName)
                            store.removeDownload(d.id)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("我的下载")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showPlay) {
            if let u = playURL {
                IQPlayer(url: u, headers: [:], title: "")
                    .environmentObject(store)
                    .ignoresSafeArea()
            }
        }
    }

    private func byteText(_ b: Int64) -> String {
        if b > 1024 * 1024 * 1024 { return String(format: "%.1f GB", Double(b) / 1073741824) }
        if b > 1024 * 1024 { return String(format: "%.1f MB", Double(b) / 1048576) }
        return String(format: "%.0f KB", Double(b) / 1024)
    }
}
