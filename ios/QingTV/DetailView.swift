import SwiftUI

struct DetailView: View {
    @EnvironmentObject var store: Store
    let title: String
    let pic: String
    let rate: String

    @State private var lines: [PlayLine] = []
    @State private var msg = "正在搜源…"
    @State private var sel = 0
    @State private var poster = ""
    @State private var matched = ""
    @State private var desc = ""
    @State private var done = false

    private var eps: [Ep] {
        guard !lines.isEmpty else { return [] }
        let i = min(max(sel, 0), lines.count - 1)
        return lines[i].eps
    }

    private var history: HistoryItem? { store.historyItem(for: title) }

    var body: some View {
        ZStack {
            BrandBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 13) {
                    header
                    if !desc.isEmpty { descBlock }
                    if let h = history, h.position > 5 { resumeBanner(h) }

                    if lines.isEmpty {
                        VStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text(done ? "没搜到能播的线路" : "正在并发搜源…")
                                .font(.caption2).foregroundColor(Theme.dim)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        linesRow
                        epsGrid
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                store.toggleFav(title: title, pic: poster.isEmpty ? pic : poster, rate: rate)
            } label: {
                Image(systemName: store.isFav(title) ? "heart.fill" : "heart")
                    .foregroundColor(store.isFav(title) ? Theme.warm : Theme.text)
            }
        }
        .onAppear {
            if poster.isEmpty { poster = pic }
            if !lines.isEmpty && sel >= lines.count { sel = 0 }
        }
        .task { await search() }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            NetImage(url: poster)
                .frame(width: 100, height: 142)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if !rate.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill").font(.caption2)
                            Text(rate).font(.footnote.bold())
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.warm)
                        .foregroundColor(.black)
                        .clipShape(Capsule())
                    }
                    if !matched.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill").font(.caption2)
                            Text(matched).font(.caption2).lineLimit(1)
                        }
                        .foregroundColor(Theme.accent)
                    }
                }

                HStack(spacing: 5) {
                    Circle().fill(Theme.warm).frame(width: 5, height: 5)
                    Text(msg).font(.caption2).foregroundColor(Theme.dim).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var descBlock: some View {
        Text(desc)
            .font(.caption2)
            .foregroundColor(Theme.dim)
            .lineLimit(5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
    }

    private func resumeBanner(_ h: HistoryItem) -> some View {
        NavigationLink(destination: PlayerView(urlString: h.epURL, title: title, pic: poster,
                                               site: h.site, line: h.line,
                                               epName: h.epName, resumeAt: h.position)) {
            HStack(spacing: 10) {
                Image(systemName: "play.circle.fill").font(.title3).foregroundColor(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("继续观看 \(h.epName)").font(.footnote.bold()).foregroundColor(Theme.text)
                    Text("从 \(timeText(h.position)) 开始 · \(h.site)").font(.caption2).foregroundColor(Theme.dim)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(Theme.dim)
            }
            .padding(12)
            .background(Theme.accent.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }


    private var linesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                    Button { sel = i } label: {
                        VStack(spacing: 2) {
                            Text(l.site).font(.caption2).opacity(0.7)
                            Text("\(l.name) · \(l.eps.count)集").font(.footnote.bold())
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(i == sel ? Theme.accent : Theme.card)
                        .foregroundColor(i == sel ? .white : Theme.text)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 54)
    }

    // MARK: - 集数

    private var epsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选集（\(eps.count)）")
                .font(.footnote.bold())
                .foregroundColor(Theme.dim)
                .padding(.horizontal, 16)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(eps) { e in
                    NavigationLink(destination: player(for: e)) {
                        epCell(e)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func epCell(_ e: Ep) -> some View {
        let watched = history?.epURL == e.url
        return Text(e.name)
            .font(.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(watched ? Theme.accent.opacity(0.25) : Theme.card)
            .foregroundColor(Theme.text)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .stroke(watched ? Theme.accent.opacity(0.6) : Color.white.opacity(0.06), lineWidth: 1))
    }

    private func player(for e: Ep) -> PlayerView {
        let resume = (history?.epURL == e.url) ? (history?.position ?? 0) : 0
        let siteName = lines.isEmpty ? "" : lines[min(max(sel, 0), lines.count - 1)].site
        let lineName = lines.isEmpty ? "" : lines[min(max(sel, 0), lines.count - 1)].name
        return PlayerView(urlString: e.url, title: title, pic: poster,
                          site: siteName, line: lineName, epName: e.name, resumeAt: resume)
    }

    // MARK: - 搜源

    private func search() async {
        let kw = Douban.keyword(title)
        var accLines: [PlayLine] = []
        var accHits: [SearchHit] = []

        await withTaskGroup(of: [SearchHit].self) { group in
            for s in store.sites.prefix(10) {
                group.addTask { await Cms.search(s, kw: kw) }
            }
            for await siteHits in group {
                for h in siteHits {
                    if accHits.contains(where: { $0.site == h.site && $0.name == h.name }) { continue }
                    accHits.append(h)
                    accLines.append(contentsOf: h.plays)
                }
                let snapHits = accHits
                let snapLines = accLines
                await MainActor.run {
                    lines = snapLines
                    if poster.isEmpty, let p = snapHits.first(where: { !$0.pic.isEmpty })?.pic { poster = p }
                    if matched.isEmpty, let first = snapHits.first {
                        matched = "\(first.name)（\(first.site)）"
                    }
                    if desc.isEmpty, let d = snapHits.first(where: { !$0.content.isEmpty })?.content {
                        desc = d
                    }
                    if sel >= snapLines.count { sel = 0 }
                    msg = snapLines.isEmpty ? "搜索中…" : "找到 \(snapLines.count) 条线路"
                }
            }
        }

        await MainActor.run {
            done = true
            if accLines.isEmpty {
                msg = "没搜到能播的，换个片试试"
            } else if let idx = bestLineIndex(target: title, lines: lines) {
                sel = idx
            }
        }
    }

    private func bestLineIndex(target: String, lines: [PlayLine]) -> Int? {
        guard !lines.isEmpty else { return nil }
        let t = target.lowercased()
        var best = 0, bestScore = -1
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

func timeText(_ s: Double) -> String {
    guard s.isFinite, s > 0 else { return "00:00" }
    let t = Int(s)
    let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
}
