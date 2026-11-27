import SwiftUI
import AVFoundation

/// 点封面进来的页面：上面小播放器（可全屏/投屏），下面片名、评分、简介、动作栏、播放源、选集
struct MovieView: View {
    @EnvironmentObject var store: Store
    @Environment(\.presentationMode) private var pm

    let title: String
    var pic: String = ""
    var rate: String = ""
    var doubanID: String = ""
    var kind: String = "movie"

    // 播放
    @State private var lines: [PlayLine] = []
    @State private var li = 0
    @State private var ei = 0
    @State private var real: String?
    @State private var headers: [String: String] = [:]
    @State private var status = "正在找片源…"
    @State private var exhausted = false
    @State private var started = false
    @State private var failCount = 0
    @State private var showAllEps = false

    // 信息
    @State private var poster = ""
    @State private var desc = ""
    @State private var score = ""
    @State private var tags = ""
    @State private var year = ""
    @State private var descOpen = false
    @State private var toast: String?

    private var curLine: PlayLine? {
        guard !lines.isEmpty, li < lines.count else { return nil }
        return lines[li]
    }
    private var curEp: Ep? {
        guard let l = curLine, ei < l.eps.count else { return nil }
        return l.eps[ei]
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bgTop.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    playerBox
                        .padding(.top, 6)
                    titleBlock
                    if !desc.isEmpty { descBlock }
                    actionRow
                    sourceBlock
                    if let l = curLine { epsBlock(l) }
                }
                .padding(.bottom, 40)
            }

            if let t = toast {
                VStack {
                    Spacer()
                    Text(t)
                        .font(.caption.bold())
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Color.black.opacity(0.8))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(.bottom, 90)
                }
                .allowsHitTesting(false)
            }
        }
        .task {
            if poster.isEmpty { poster = pic }
            if score.isEmpty { score = rate }
            if !started {
                started = true
                await loadInfo()
                await loadSources()
            }
        }
    }

    // MARK: - 播放器区

    private var playerBox: some View {
        ZStack {
            Color.black
            if let r = real, let u = URL(string: r) {
                IQPlayer(url: u,
                         headers: headers,
                         title: title,
                         resumeAt: resumePosition(),
                         onProgress: { pos, dur in
                             guard let ep = curEp, let l = curLine else { return }
                             store.recordProgress(title: title, pic: poster, site: l.site, line: l.name,
                                                  epName: ep.name, epURL: ep.url,
                                                  position: pos, duration: dur)
                         },
                         onFail: { skipToNext() },
                         onSource: { skipToNext() },
                         onEpisodes: { showAllEps = true },
                         onClose: { pm.wrappedValue.dismiss() },
                         compact: true,
                         onFullscreen: { openLandscape() })
                    .id("\(li)-\(ei)-\(r)")
            } else {
                // 还没开播：海报 + 播放键
                ZStack {
                    NetImage(url: poster.isEmpty ? pic : poster)
                        .aspectRatio(16.0 / 9.0, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .opacity(0.55)
                    VStack(spacing: 8) {
                        if lines.isEmpty {
                            ProgressView().tint(.white)
                            Text(status).font(.caption).foregroundColor(.white.opacity(0.85))
                            if exhausted {
                                Text("没搜到能播的源").font(.caption2).foregroundColor(.orange)
                            }
                        } else {
                            Button { playCurrent() } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 52))
                                    .foregroundColor(.white.opacity(0.92))
                            }
                            .buttonStyle(.plain)
                            Text("点这里开始播").font(.caption2).foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)

                // 左上返回
                VStack {
                    HStack {
                        Button { pm.wrappedValue.dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.black.opacity(0.35))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        AirPlayButton().frame(width: 34, height: 34)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipped()
    }

    // MARK: - 标题 / 评分 / 简介

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                Spacer()
                if !score.isEmpty && score != "0" {
                    Text("\(score)分")
                        .font(.footnote.bold())
                        .foregroundColor(Theme.warm)
                }
            }

            HStack(spacing: 6) {
                if !tags.isEmpty {
                    Text(tags)
                        .font(.caption)
                        .foregroundColor(Theme.dim)
                        .lineLimit(1)
                } else if !year.isEmpty {
                    Text(year).font(.caption).foregroundColor(Theme.dim)
                }
                Spacer()
                if !desc.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { descOpen.toggle() }
                    } label: {
                        HStack(spacing: 2) {
                            Text("简介").font(.caption2)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .rotationEffect(.degrees(descOpen ? 90 : 0))
                        }
                        .foregroundColor(Theme.dim)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private var descBlock: some View {
        Text(desc)
            .font(.caption)
            .foregroundColor(Theme.dim)
            .lineLimit(descOpen ? nil : 3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
    }

    // MARK: - 动作栏

    private var actionRow: some View {
        HStack(spacing: 10) {
            actionButton(store.isFav(title) ? "star.fill" : "star",
                         store.isFav(title) ? "已收藏" : "收藏",
                         tint: store.isFav(title) ? Theme.warm : Theme.text) {
                store.toggleFav(title: title, pic: poster.isEmpty ? pic : poster, rate: score)
                flash(store.isFav(title) ? "已收藏" : "已取消收藏")
            }
            actionButton("arrow.down.circle", "下载", tint: Theme.text) { flash("下载功能还没做") }
            actionButton("square.and.arrow.up", "分享", tint: Theme.text) { share() }
            actionButton("arrow.triangle.2.circlepath", "换源", tint: Theme.text) { skipToNext() }
        }
        .padding(.horizontal, 14)
    }

    private func actionButton(_ icon: String, _ label: String, tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(label).font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Theme.card)
            .foregroundColor(tint)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 播放源

    private var sourceBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("播放源").font(.footnote.bold()).foregroundColor(Theme.text)
                Text("\(lines.count) 条").font(.caption2).foregroundColor(Theme.dim)
                Spacer()
                if let l = curLine, let e = curEp {
                    Text("\(l.site) · \(l.name) · \(e.name)")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.dim)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)

            if lines.isEmpty {
                Text(status).font(.caption2).foregroundColor(Theme.dim).padding(.horizontal, 14)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                            Button {
                                li = i
                                ei = 0
                                playCurrent()
                            } label: {
                                VStack(spacing: 1) {
                                    Text(l.site).font(.system(size: 9)).opacity(0.8)
                                    Text(l.name).font(.caption.bold())
                                }
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(i == li ? Theme.accent : Theme.card)
                                .foregroundColor(i == li ? .white : Theme.text)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
    }

    private func epsBlock(_ l: PlayLine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("选集（\(l.eps.count)）").font(.footnote.bold()).foregroundColor(Theme.text)
                Spacer()
                if l.eps.count > 20 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAllEps.toggle() }
                    } label: {
                        Text(showAllEps ? "收起" : "全部 \(l.eps.count) 集")
                            .font(.caption2).foregroundColor(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(Array(l.eps.enumerated().prefix(showAllEps ? l.eps.count : 20)), id: \.element.id) { k, e in
                    Button {
                        ei = k
                        playCurrent()
                    } label: {
                        Text(e.name)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(k == ei ? Theme.accent : Theme.card)
                            .foregroundColor(k == ei ? .white : Theme.text)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    // MARK: - 真全屏（直接横屏）

    private func openLandscape() {
        guard let r = real, let u = URL(string: r) else {
            flash("还没开播")
            return
        }
        let view = IQPlayer(url: u,
                            headers: headers,
                            title: title,
                            resumeAt: resumePosition(),
                            onProgress: { pos, dur in
                                guard let ep = curEp, let l = curLine else { return }
                                store.recordProgress(title: title, pic: poster, site: l.site, line: l.name,
                                                     epName: ep.name, epURL: ep.url,
                                                     position: pos, duration: dur)
                            },
                            onFail: { skipToNext() },
                            onSource: { skipToNext() },
                            onEpisodes: { showAllEps = true },
                            onClose: { PlayerPresenter.dismiss() })
            .environmentObject(store)
        PlayerPresenter.present(view)
    }

    // MARK: - 数据

    private func resumePosition() -> Double {
        guard let ep = curEp, let h = store.historyItem(for: title), h.epURL == ep.url else { return 0 }
        return h.position
    }

    private func loadInfo() async {
        if let info = await Douban.subject(doubanID, kind: kind) {
            await MainActor.run {
                if !info.intro.isEmpty { desc = info.intro }
                if !info.rate.isEmpty { score = info.rate }
                if !info.year.isEmpty { year = info.year }
                var arr: [String] = []
                if !info.genres.isEmpty { arr.append(info.genres) }
                if !info.year.isEmpty { arr.append(info.year) }
                tags = arr.joined(separator: " · ")
            }
        }
    }

    private func loadSources() async {
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
                let snap = (accHits, accLines)
                await MainActor.run {
                    lines = snap.1
                    if poster.isEmpty, let p = accHits.first(where: { !$0.pic.isEmpty })?.pic { poster = p }
                    if desc.isEmpty, let d = accHits.first(where: { !$0.content.isEmpty })?.content { desc = d }
                    if real == nil && !lines.isEmpty && status != "已开播" { playCurrent() }
                }
            }
        }
        await MainActor.run {
            if lines.isEmpty { status = "没搜到能播的片源"; exhausted = true }
        }
    }

    private func playCurrent() {
        guard let ep = curEp else { return }
        status = "已开播"
        let target = ep.url
        Task {
            let m = await Resolver.m3u8(from: target)
            let h = Resolver.headers(for: target)
            await MainActor.run {
                if let m = m {
                    headers = h
                    real = m
                } else {
                    skipToNext()
                }
            }
        }
    }

    private func skipToNext() {
        guard !lines.isEmpty else { return }
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

    private func share() {
        let text = "\(title) \(score.isEmpty ? "" : score + "分")"
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
           let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            root.present(av, animated: true)
        }
    }

    private func flash(_ msg: String) {
        toast = msg
        Task {
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            await MainActor.run { if toast == msg { toast = nil } }
        }
    }
}
