import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var sub = ""
    @State private var msg = ""
    @State private var repos: [Repo] = []
    @State private var busy = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("我的内容")) {
                    NavigationLink(destination: FavoritesView()) {
                        row("heart.fill", Theme.warm, "我的收藏", "\(store.favorites.count)")
                    }
                    NavigationLink(destination: HistoryView()) {
                        row("clock.arrow.circlepath", Theme.accent, "观看记录", "\(store.history.count)")
                    }
                    NavigationLink(destination: DownloadsView()) {
                        row("arrow.down.circle.fill", Theme.accent, "我的下载", "\(store.downloads.count)")
                    }
                }

                Section(header: Text("TVBox 订阅（多仓 / 单仓）")) {
                    TextField("订阅地址", text: $sub)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    Button(busy ? "解析中…" : "导入订阅") {
                        Task { await importSub() }
                    }
                    .disabled(busy)

                    if !repos.isEmpty {
                        ForEach(repos) { r in
                            Button("选这个仓：\(r.name)") {
                                Task { await loadRepo(r) }
                            }
                        }
                    }
                    if !msg.isEmpty {
                        Text(msg).font(.caption).foregroundColor(.secondary)
                    }
                }

                Section(header: Text("站源（\(store.sites.count) 个）")) {
                    ForEach(store.sites) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.name).foregroundColor(.white)
                            Text(s.api).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                    .onDelete { idx in
                        store.sites.remove(atOffsets: idx)
                        store.save()
                    }
                    Button("恢复默认 8 个源") { store.apply(Defaults.sites) }
                }

                Section(header: Text("直播源")) {
                    ForEach(store.lives, id: \.self) { l in
                        Text(l).font(.caption).lineLimit(1)
                    }
                    .onDelete { idx in
                        store.lives.remove(atOffsets: idx)
                        store.save()
                    }
                    Button("恢复默认直播源") {
                        store.lives = Defaults.lives
                        store.save()
                    }
                }

                Section(header: Text("清理")) {
                    Button("清空观看记录") {
                        store.clearHistory()
                        msg = "已清空观看记录"
                    }
                    .foregroundColor(.orange)
                    Button("清空搜索历史") {
                        store.clearSearches()
                        msg = "已清空搜索历史"
                    }
                    .foregroundColor(.orange)
                }

                Section(header: Text("关于")) {
                    Text("影匣 2.6.0 · 纯客户端壳，不含任何内容").font(.caption)
                    Text("发现用豆瓣，播放靠 cms 搜索匹配。无广告、无登录、无推送。").font(.caption2).foregroundColor(.secondary)
                }
            }
            .navigationTitle("我的")
            .onAppear { if sub.isEmpty { sub = store.subscription } }
        }
    }

    private func row(_ icon: String, _ color: Color, _ title: String, _ badge: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(color)
            Text(title)
            Spacer()
            Text(badge).foregroundColor(Theme.dim)
        }
    }

    private func importSub() async {
        let url = sub.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        busy = true
        msg = "解析中…"
        store.subscription = url
        store.save()
        let r = await TVBox.load(url)
        await MainActor.run {
            busy = false
            if !r.repos.isEmpty {
                repos = r.repos
                msg = "多仓订阅，共 \(r.repos.count) 个仓，点一个导入"
            } else if !r.sites.isEmpty {
                repos = []
                store.apply(r.sites)
                msg = "单仓导入成功，\(r.sites.count) 个可直连源"
            } else {
                msg = r.error ?? "解析失败"
            }
        }
    }

    private func loadRepo(_ repo: Repo) async {
        busy = true
        msg = "读取「\(repo.name)」…"
        let r = await TVBox.load(repo.url)
        await MainActor.run {
            busy = false
            if !r.sites.isEmpty {
                store.apply(r.sites)
                msg = "「\(repo.name)」导入成功：\(r.sites.count) 个可直连源"
            } else {
                msg = r.error ?? "这个仓没有可直连的源（可能全是 spider 源）"
            }
        }
    }
}
