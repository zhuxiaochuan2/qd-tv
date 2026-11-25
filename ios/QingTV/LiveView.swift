import SwiftUI

struct LiveView: View {
    @EnvironmentObject var store: Store
    @State private var chs: [Channel] = []
    @State private var msg = "读取直播源…"
    @State private var playing: Channel?
    @State private var q = ""

    private var filtered: [Channel] {
        let k = q.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return chs }
        return chs.filter { $0.name.localizedCaseInsensitiveContains(k) }
    }

    var body: some View {
        NavigationView {
            ZStack {
                BrandBackground()

                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.accent).frame(width: 5, height: 5)
                        Text(msg.isEmpty ? "共 \(chs.count) 个频道" : msg)
                            .font(.caption2).foregroundColor(Theme.dim)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.top, 6)

                    if chs.isEmpty {
                        Spacer()
                        VStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("正在拉直播源…").font(.caption).foregroundColor(Theme.dim)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(filtered) { c in
                                Button {
                                    playing = c
                                } label: {
                                    HStack(spacing: 10) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Theme.accent.opacity(0.18))
                                                .frame(width: 34, height: 34)
                                            Image(systemName: "tv")
                                                .font(.caption)
                                                .foregroundColor(Theme.accent)
                                        }
                                        Text(c.name)
                                            .font(.subheadline)
                                            .foregroundColor(Theme.text)
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: "play.circle.fill")
                                            .foregroundColor(Theme.accent.opacity(0.8))
                                    }
                                    .padding(.vertical, 2)
                                }
                                .listRowBackground(Theme.card)
                                .listRowSeparator(.hidden)
                            }
                        }
                        .listStyle(.plain)
                        .searchable(text: $q, prompt: "搜频道，比如 CCTV5")
                    }
                }
            }
            .navigationTitle("直播")
            .toolbar {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.body.weight(.semibold))
                }
            }
            .onAppear { UITableView.appearance().backgroundColor = .clear }
            .task { if chs.isEmpty { await load() } }
            .sheet(item: $playing) { c in
                NavigationView {
                    PlayerView(urlString: c.url, title: c.name)
                }
            }
            .tint(Theme.accent)
        }
    }

    private func load() async {
        msg = "读取直播源…"
        let r = await Live.channels(from: store.lives)
        await MainActor.run {
            chs = r
            msg = r.isEmpty ? "直播源没拉到，稍后再试" : ""
        }
    }
}
