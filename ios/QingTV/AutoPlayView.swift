import SwiftUI
import AVFoundation

/// 点开电影直接播：自动挑源、自动换源、自动选集
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
    @State private var rateValue: Float = 1.0
    @State private var seekRequest: Double = 0
    @State private var failCount = 0

    private var curLine: PlayLine? {
        guard !lines.isEmpty, li < lines.count else { return nil }
        return lines[li]
    }
    private var curEp: Ep? {
        guard let l = curLine, ei < l.eps.count else { return nil }
        return l.eps[ei]
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let r = real, let u = URL(string: r) {
                VideoPlayer(url: u,
                            headers: headers,
                            resumeAt: resumePosition(),
                            rate: rateValue,
                            seekTo: seekRequest,
                            onNoAudio: nil,
                            onReady: { status = "" },
                            onFail: { skipToNext() },
                            onProgress: { pos, dur in
                                guard let ep = curEp, let l = curLine else { return }
                                store.recordProgress(title: title, pic: poster.isEmpty ? pic : poster,
                                                     site: l.site, line: l.name,
                                                     epName: ep.name, epURL: ep.url,
                                                     position: pos, duration: dur)
                            })
                    .id("\(li)-\(ei)-\(r)")     // 换源/换集必须重建播放器
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text(status).font(.caption).foregroundColor(.secondary)
                    if exhausted { Text("所有线路都播不了，回上一页换一部").font(.caption2).foregroundColor(.orange) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if real != nil { tools }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) { picker }
        .task { if !started { await prepare() } }
    }

    // MARK: - 工具栏

    private var tools: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let l = curLine, let e = curEp {
                Text("\(li + 1)/\(lines.count) 条 · \(l.site) \(l.name) · \(e.name)")
                    .font(.system(size: 10))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.black.opacity(0.55))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            HStack(spacing: 8) {
                Button { skipToNext() } label: {
                    Text("换源").font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.black.opacity(0.55))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button { showPicker = true } label: {
                    Text("选集").font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.black.opacity(0.55))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button { seekRequest += 60 } label: {
                    Text("+60s").font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.black.opacity(0.55))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                        Button("\(r, specifier: "%g")x") { rateValue = Float(r) }
                    }
                } label: {
                    Text(rateValue == 1.0 ? "1x" : String(format: "%gx", rateValue))
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.black.opacity(0.55))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }

                Button {
                    if Orientation.isLandscapeNow {
                        Orientation.portrait()
                    } else {
                        Orientation.landscape()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: Orientation.isLandscapeNow
                              ? "rectangle.portrait.arrowtriangle.2.inward"
                              : "rectangle.landscape.rotate")
                        Text(Orientation.isLandscapeNow ? "竖屏" : "横屏")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.trailing, 12)
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
            .toolbar {
                Button("关闭") { showPicker = false }
            }
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
                    if real == nil && !snapLines.isEmpty && real == nil {
                        playCurrent()
                    } else if snapLines.isEmpty {
                        status = "正在找片源…"
                    }
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
                    // 解析不出来也算这条线路失败
                    skipToNext()
                }
            }
        }
    }

    /// 当前线路播不了 → 自动换下一条（第一条不行换第二条，以此类推）
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
