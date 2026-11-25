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
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<tabs.count, id: \.self) { i in
                            Button(tabs[i].2) {
                                tab = i; start = 0; isSearchResult = false; load()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(i == tab && !isSearchResult ? Color.blue : Color.white.opacity(0.08))
                            .foregroundColor(.white)
                            .cornerRadius(9)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }

                Text(msg)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)

                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 12) {
                        ForEach(items) { it in
                            NavigationLink(destination: DetailView(title: it.name, pic: it.pic, rate: it.rate)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    NetImage(url: it.pic)
                                        .frame(height: 158)
                                        .cornerRadius(8)
                                    Text(it.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                    }
                    .padding(12)

                    if !isSearchResult {
                        HStack(spacing: 14) {
                            Button("上一页") { start = max(0, start - 20); load() }
                                .disabled(start == 0)
                            Button("下一页") { start += 20; load() }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("轻电视")
            .toolbar {
                Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
            }
            .sheet(isPresented: $showSearch) { searchSheet }
            .task { if items.isEmpty { load() } }
        }
    }

    private var searchSheet: some View {
        VStack(spacing: 16) {
            TextField("输入片名", text: $query)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit { runSearch() }
            Button("搜索") { runSearch() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(20)
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
