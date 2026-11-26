import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var store: Store
    @State private var tab = 0
    @State private var items: [DoubanItem] = []
    @State private var start = 0
    @State private var loading = false
    @State private var msg = "加载中…"
    @State private var showSearch = false
    @State private var query = ""
    @State private var isSearchResult = false

    private let tabs: [(String, String, String)] = [
        ("movie", "热门", "热门电影"),
        ("tv", "热门", "热门剧集"),
        ("tv", "综艺", "综艺"),
        ("movie", "豆瓣高分", "高分电影"),
        ("tv", "豆瓣高分", "高分剧集"),
        ("movie", "动画", "动画片"),
        ("tv", "日本动画", "动画番剧"),
    ]

    /// 固定格子宽度：不依赖 flexible 列，彻底避免被父容器撑宽导致左右裁切
    private let hPad: CGFloat = 12
    private let gap: CGFloat = 10
    private var cellW: CGFloat {
        let sw = UIScreen.main.bounds.width
        return floor((sw - hPad * 2 - gap * 2) / 3)
    }
    private var cellH: CGFloat { floor(cellW * 1.48) }
    private var columns: [GridItem] {
        [GridItem(.fixed(cellW), spacing: gap),
         GridItem(.fixed(cellW), spacing: gap),
         GridItem(.fixed(cellW), spacing: gap)]
    }

    var body: some View {
        NavigationView {
            ZStack {
                BrandBackground()

                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(0..<tabs.count, id: \.self) { i in
                                Button {
                                    tab = i; start = 0; isSearchResult = false; load()
                                } label: {
                                    Pill(text: tabs[i].2, selected: i == tab && !isSearchResult)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, hPad)
                    }
                    .frame(height: 46)

                    HStack(spacing: 6) {
                        Circle().fill(Theme.accent).frame(width: 5, height: 5)
                        Text(msg).font(.caption2).foregroundColor(Theme.dim).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            if loading && items.isEmpty { skeletonGrid } else { grid }
                            if !isSearchResult && !items.isEmpty { pager }
                        }
                    }
                }
            }
            .navigationTitle("影匣")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                Button { showSearch = true } label: {
                    Image(systemName: "magnifyingglass").font(.body.weight(.semibold))
                }
            }
            .sheet(isPresented: $showSearch) { searchSheet }
            .task { if items.isEmpty { load() } }
            .tint(Theme.accent)
        }
        .navigationViewStyle(.stack)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(items) { it in
                NavigationLink(destination: DetailView(title: it.name, pic: it.pic, rate: it.rate)) {
                    card(it)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, hPad)
        .padding(.top, 10)
    }

    private func card(_ it: DoubanItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                NetImage(url: it.pic)
                    .frame(width: cellW, height: cellH)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1))

                if !it.rate.isEmpty && it.rate != "0" {
                    Text(it.rate)
                        .font(.caption2).bold()
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.warm)
                        .foregroundColor(.black)
                        .clipShape(Capsule())
                        .padding(5)
                }
            }
            Text(it.name)
                .font(.caption)
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.85)
                .frame(width: cellW, alignment: .leading)
        }
        .frame(width: cellW)
    }

    private var skeletonGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(0..<9, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    Skeleton(height: cellH).frame(width: cellW)
                    Skeleton(height: 10).frame(width: cellW)
                }
            }
        }
        .padding(.horizontal, hPad).padding(.top, 10)
    }

    private var pager: some View {
        HStack(spacing: 16) {
            Button { start = max(0, start - 20); load() } label: {
                Label("上一页", systemImage: "chevron.left").font(.footnote)
            }
            .buttonStyle(.plain)
            .disabled(start == 0)
            .opacity(start == 0 ? 0.35 : 1)

            Text("第 \(start / 20 + 1) 页").font(.caption2).foregroundColor(Theme.dim)

            Button { start += 20; load() } label: {
                Label("下一页", systemImage: "chevron.right").font(.footnote)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 22)
    }

    private var searchSheet: some View {
        VStack(spacing: 18) {
            Capsule().fill(Color.white.opacity(0.2)).frame(width: 40, height: 5).padding(.top, 8)
            Text("搜索片名").font(.headline)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundColor(Theme.dim)
                TextField("输入片名", text: $query)
                    .submitLabel(.search)
                    .onSubmit { runSearch() }
            }
            .padding(12)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button { runSearch() } label: {
                Text("搜索").bold().frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .background(Theme.accent)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(20)
        .background(Theme.bgTop.ignoresSafeArea())
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        showSearch = false
        loading = true
        msg = "搜索中…"
        Task {
            let r = await Douban.search(q)
            await MainActor.run {
                items = r
                isSearchResult = true
                msg = r.isEmpty ? "没搜到，换个词" : "搜到 \(r.count) 个结果"
                loading = false
            }
        }
    }

    private func load() {
        guard !loading else { return }
        loading = true
        msg = "加载中…"
        let t = tabs[tab]
        let st = start
        Task {
            let r = await Douban.list(type: t.0, tag: t.1, start: st)
            await MainActor.run {
                items = r
                msg = r.isEmpty ? "没拉到数据，稍后再试" : "第 \(st / 20 + 1) 页 · \(r.count) 部"
                loading = false
            }
        }
    }
}
