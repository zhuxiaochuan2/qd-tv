import SwiftUI

struct DetailView: View {
    @EnvironmentObject var store: Store
    let title: String
    let pic: String
    let rate: String

    @State private var hits: [SearchHit] = []
    @State private var lines: [PlayLine] = []
    @State private var msg = "正在搜源…"
    @State private var sel = 0
    @State private var poster = ""
    @State private var matched = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                posterView
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.title3).bold().foregroundColor(.white)
                    if !rate.isEmpty {
                        Text("评分 \(rate)").font(.subheadline).foregroundColor(.orange)
                    }
                    if !matched.isEmpty {
                        Text("匹配：\(matched)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Text(msg).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(16)

            if !lines.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                            Button("\(l.site)·\(l.name)") { sel = i }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(i == sel ? Color.blue : Color.white.opacity(0.08))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .font(.footnote)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(lines[sel].eps) { e in
                            NavigationLink(destination: PlayerView(urlString: e.url, title: "\(title) \(e.name)")) {
                                Text(e.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(Color.white.opacity(0.08))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(16)
                }
            }

            Spacer(minLength: 0)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if poster.isEmpty { poster = pic } }
        .task { await search() }
    }

    /// 封面：先用豆瓣的；豆瓣没有就用搜到的第一条 cms 结果
    private var posterView: some View {
        NetImage(url: poster)
            .frame(width: 96, height: 136)
            .cornerRadius(8)
    }

    private func search() async {
        let kw = Douban.keyword(title)
        var accHits: [SearchHit] = []
        var accLines: [PlayLine] = []

        await withTaskGroup(of: [SearchHit].self) { group in
            for s in store.sites.prefix(10) {
                group.addTask { await Cms.search(s, kw: kw) }
            }
            for await siteHits in group {
                for h in siteHits {
                    // 去重：同站点同名的不重复加
                    if accHits.contains(where: { $0.site == h.site && $0.name == h.name }) { continue }
                    accHits.append(h)
                    accLines.append(contentsOf: h.plays)
                }
                let snapHits = accHits
                let snapLines = accLines
                await MainActor.run {
                    hits = snapHits
                    lines = snapLines
                    // 封面匹配：豆瓣没给图，就用命中的 cms 封面
                    if poster.isEmpty, let p = snapHits.first(where: { !$0.pic.isEmpty })?.pic {
                        poster = p
                    }
                    if matched.isEmpty, let first = snapHits.first {
                        matched = "\(first.name)（\(first.site)）"
                    }
                    msg = snapLines.isEmpty ? "搜索中…" : "找到 \(snapLines.count) 条线路"
                }
            }
        }

        if accLines.isEmpty {
            await MainActor.run { msg = "没搜到能播的，回首页换个片或直接搜索" }
        } else {
            // 优先选和片名最像的那条线路
            await MainActor.run {
                if let idx = bestLineIndex(target: title, lines: lines) { sel = idx }
                if let best = lines.first(where: { $0.site == hits.first?.site }) { _ = best }
            }
        }
    }

    /// 片名相似度：完全包含优先，其次按公共字数
    private func bestLineIndex(target: String, lines: [PlayLine]) -> Int? {
        guard !lines.isEmpty else { return nil }
        let t = target.lowercased()
        var best = 0
        var bestScore = -1
        for (i, l) in lines.enumerated() {
            let n = l.name.lowercased()
            var score = 0
            if n.contains(t) || t.contains(n) { score += 100 }
            score += n.filter { t.contains($0) }.count
            if score > bestScore { bestScore = score; best = i }
        }
        return best
    }
}
