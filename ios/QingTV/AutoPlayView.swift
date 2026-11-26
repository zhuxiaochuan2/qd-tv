import SwiftUI
import AVFoundation

/// 点开电影直接播：自动挑源、自动换源、自动选集（界面用爱奇艺风格播放器）
struct AutoPlayView: View {
    @EnvironmentObject var store: Store

    let title: String
    var pic: String = ""
    var rate: String = ""

    @State private var lines: [PlayLine] = []
    @State private var hits: [SearchHit] = []
    @State private var li = 0
    @State private var ei = 0
    @State private var real: String?
    @State private var headers: [String: String] = [:]
    @State private var status = "正在找片源…"
    @State private var poster = ""
    @State private var desc = ""
    @State private var started = false
    @State private var exhausted = false
    @State private var showPicker = false
    @State private var failCount = 0

    @Environment(\.presentationMode) private var pm

    private var curLine: PlayLine? {
        guard !lines.isEmpty, li < lines.count else { return nil }
        return lines[li]
    }
    private var curEp: Ep? {
        guard let l = curLine, ei < l.eps.count else { return nil }
        return l.eps[ei]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let r = real, let u = URL(string: r) {
                IQPlayer(url: u,
                         headers: headers,
                         title: title,
                         resumeAt: resumePosition(),
                         onProgress: { pos, dur in
                             guard let ep = curEp, let l = curLine else { return }
                             store.recordProgress(title: title,
                                                  pic: poster.isEmpty ? pic : poster,
                                                  site: l.site, line: l.name,
                                                  epName: ep.name, epURL: ep.url,
                                                  position: pos, duration: dur)
                         },
                         onFail: { skipToNext() },
                         onSource: { skipToNext() },
                         onEpisodes: { showPicker = true },
                         onClose: { pm.wrappedValue.dismiss() })
                    .id("\(li)-\(ei)-\(r)")
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    Button { pm.wrappedValue.dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    ProgressView().tint(.white)
                    Text(status).font(.caption).foregroundColor(.secondary)
                    if exhausted {
                        Text("所有线路都播不了，回上一页换一部")
                            .font(.caption2).foregroundColor(.orange)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("")
        .sheet(isPresented: $showPicker) { picker }
        .task { if !started { await prepare() } }
    }

    // MARK: - 选集面板

    private var picker: some View {
        NavigationView {
            ZStack {
                Theme.bgTop.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("线路（点一下换源）")
                            .font(.footnote).bold().foregroundColor(Theme.dim)
                            .padding(.horizontal, 16)

                        ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                            Button {
                                li = i
                                ei = 0
                                playCurrent()
                                showPicker = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(l.site).font(.caption2).foregroundColor(Theme.dim)
                                        Text("\(l.name) · \(l.eps.count)集")
                                            .font(.footnote).bold().foregroundColor(Theme.text)
                                    }
                                    Spacer()
                                    if i == li {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Theme.accent)
                                    }
                                }
                                .padding(12)
                                .background(i == li ? Theme.accent.opacity(0.18) : Theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .padding(.horizontal, 16)
                            }
                            .buttonStyle(.plain)
                        }

                        if let l = curLine {
                            Text("\(l.site) · \(l.name) 的选集")
                                .font(.footnote).bold().foregroundColor(Theme.dim)
                                .padding(.horizontal, 16)
                                .padding(.top, 6)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                                ForEach(Array(l.eps.enumerated()), id: \.element.id) { k, e in
                                    Button {
                                        ei = k
                                        playCurrent()
                                        showPicker = false
                                    } label: {
                                        Text(e.name)
                                            .font(.caption).lineLimit(1)
                                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                                            .background(k == ei ? Theme.accent : Theme.card)
                                            .foregroundColor(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 9))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("选集 / 换源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("关闭") { showPicker = false } }
        }
    }

    // MARK: - 搜索 + 播放

    private func prepare() async {
        started = true
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
                    hits = snapHits
                    lines = snapLines
                    if poster.isEmpty, let p = snapHits.first(where: { !$0.pic.isEmpty })?.pic { poster = p }
                    if desc.isEmpty, let d = snapHits.first(where: { !$0.content.isEmpty })?.content { desc = d }
                    if real == nil && !snapLines.isEmpty { playCurrent() }
                }
            }
        }

        await MainActor.run {
            if lines.isEmpty {
                status = "没搜到能播的片源"
                exhausted = true
            }
        }
    }

    private func resumePosition() -> Double {
        guard let ep = curEp, let h = store.historyItem(for: title), h.epURL == ep.url else { return 0 }
        return h.position
    }

    private func playCurrent() {
        guard let ep = curEp else { return }
        real = nil
        status = "解析 \(li + 1)/\(lines.count) 条线路…"
        let target = ep.url
        Task {
            let m = await Resolver.m3u8(from: target)
            let h = Resolver.headers(for: target)
            await MainActor.run {
                if let m = m {
                    headers = h
                    real = m
                    status = ""
                } else {
                    skipToNext()
                }
            }
        }
    }

    private func skipToNext() {
        guard !lines.isEmpty else {
            status = "没搜到能播的片源"
            exhausted = true
            return
        }
        failCount += 1
        if failCount > lines.count + 2 {
            status = "所有线路都播不了"
            exhausted = true
            real = nil
            return
        }
        if li + 1 < lines.count {
            li += 1
            ei = 0
            real = nil
            playCurrent()
        } else {
            status = "所有线路都播不了"
            exhausted = true
            real = nil
        }
    }
}
