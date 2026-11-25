import SwiftUI

/// 儿童模式：只有动画片，退出要密码
struct KidsView: View {
    @EnvironmentObject var store: Store
    @State private var tab = 0
    @State private var items: [DoubanItem] = []
    @State private var start = 0
    @State private var loading = false
    @State private var msg = "加载中…"
    @State private var showPwd = false
    @State private var pwd = ""
    @State private var pwdErr = ""

    /// 只放动画类目
    private let tabs: [(String, String, String)] = [
        ("movie", "动画", "动画电影"),
        ("movie", "国产动画", "国产动画"),
        ("movie", "日本动画", "日本动画"),
        ("tv", "日本动画", "动画番剧"),
    ]

    /// 幼儿向、源里基本都有的片单，点进去直接走 cms 搜索
    private let hot: [String] = [
        "小猪佩奇", "汪汪队立大功", "超级飞侠", "熊出没", "哆啦A梦",
        "奥特曼", "海底小纵队", "布鲁伊", "萌鸡小队", "贝乐虎",
        "米奇妙妙屋", "汪汪队", "小马宝莉", "巴巴爸爸", "小羊肖恩",
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<tabs.count, id: \.self) { i in
                            Button(tabs[i].2) {
                                tab = i; start = 0; load()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(i == tab ? Color.orange : Color.white.opacity(0.08))
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
                    // 幼儿热门片单
                    VStack(alignment: .leading, spacing: 8) {
                        Text("小朋友最爱")
                            .font(.subheadline).bold()
                            .foregroundColor(.orange)
                            .padding(.horizontal, 14)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(hot, id: \.self) { t in
                                    NavigationLink(destination: DetailView(title: t, pic: "", rate: "")) {
                                        Text(t)
                                            .font(.footnote)
                                            .padding(.horizontal, 12).padding(.vertical, 8)
                                            .background(Color.orange.opacity(0.22))
                                            .foregroundColor(.white)
                                            .cornerRadius(9)
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                    .padding(.top, 4)

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

                    HStack(spacing: 14) {
                        Button("上一页") { start = max(0, start - 20); load() }
                            .disabled(start == 0)
                        Button("下一页") { start += 20; load() }
                    }
                    .padding(.bottom, 24)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("儿童模式")
            .toolbar {
                Button {
                    pwd = ""; pwdErr = ""; showPwd = true
                } label: {
                    Image(systemName: "lock.fill")
                }
            }
            .sheet(isPresented: $showPwd) { pwdSheet }
            .task { if items.isEmpty { load() } }
        }
    }

    private var pwdSheet: some View {
        VStack(spacing: 16) {
            Text("退出儿童模式").font(.headline)
            SecureField("输入密码", text: $pwd)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
            if !pwdErr.isEmpty {
                Text(pwdErr).font(.caption).foregroundColor(.red)
            }
            HStack(spacing: 12) {
                Button("取消") { showPwd = false }
                    .buttonStyle(.bordered)
                Button("确定") {
                    if store.exitKidsMode(pwd: pwd) {
                        showPwd = false
                    } else {
                        pwdErr = "密码不对"
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
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
                msg = r.isEmpty ? "没拉到，等等再试" : "第 \(st / 20 + 1) 页 · \(r.count) 部"
                loading = false
            }
        }
    }
}
