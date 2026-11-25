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

    private let tabs: [(String, String, String)] = [
        ("movie", "动画", "动画电影"),
        ("movie", "国产动画", "国产动画"),
        ("movie", "日本动画", "日本动画"),
        ("tv", "日本动画", "动画番剧"),
    ]

    private let hot: [String] = [
        "小猪佩奇", "汪汪队立大功", "超级飞侠", "熊出没", "哆啦A梦",
        "奥特曼", "海底小纵队", "布鲁伊", "萌鸡小队", "贝乐虎",
        "米奇妙妙屋", "小马宝莉", "巴巴爸爸", "小羊肖恩",
    ]

    var body: some View {
        NavigationView {
            ZStack {
                BrandBackground(warm: true)

                VStack(spacing: 0) {
                    // 顶部问候
                    HStack(spacing: 8) {
                        Text("🧸").font(.title2)
                        Text("小朋友，今天看点什么？")
                            .font(.subheadline).bold()
                            .foregroundColor(Theme.text)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.top, 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(0..<tabs.count, id: \.self) { i in
                                Button {
                                    tab = i; start = 0; load()
                                } label: {
                                    Pill(text: tabs[i].2, selected: i == tab, color: Theme.warm)
                                }
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    }

                    HStack(spacing: 6) {
                        Circle().fill(Theme.warm).frame(width: 5, height: 5)
                        Text(msg).font(.caption2).foregroundColor(Theme.dim)
                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    ScrollView {
                        // 快捷片单
                        VStack(alignment: .leading, spacing: 8) {
                            Text("小朋友最爱")
                                .font(.footnote).bold()
                                .foregroundColor(Theme.warm)
                                .padding(.horizontal, 16)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(hot, id: \.self) { t in
                                        NavigationLink(destination: DetailView(title: t, pic: "", rate: "")) {
                                            Text(t)
                                                .font(.footnote).bold()
                                                .padding(.horizontal, 14).padding(.vertical, 10)
                                                .background(Theme.warm.opacity(0.22))
                                                .foregroundColor(Theme.text)
                                                .clipShape(Capsule())
                                                .overlay(Capsule().stroke(Theme.warm.opacity(0.5), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        if loading && items.isEmpty {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
                                ForEach(0..<6, id: \.self) { _ in
                                    VStack(spacing: 6) {
                                        Skeleton(height: 168)
                                        Skeleton(height: 10)
                                    }
                                }
                            }
                            .padding(14)
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
                                ForEach(items) { it in
                                    NavigationLink(destination: DetailView(title: it.name, pic: it.pic, rate: it.rate)) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            NetImage(url: it.pic)
                                                .frame(height: 168)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                                .overlay(RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Theme.warm.opacity(0.35), lineWidth: 1))
                                            Text(it.name)
                                                .font(.caption)
                                                .foregroundColor(Theme.text)
                                                .lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(14)

                            HStack(spacing: 16) {
                                Button { start = max(0, start - 20); load() } label: {
                                    Label("上一页", systemImage: "chevron.left").font(.footnote)
                                }
                                .disabled(start == 0)
                                .opacity(start == 0 ? 0.35 : 1)

                                Button { start += 20; load() } label: {
                                    Label("下一页", systemImage: "chevron.right").font(.footnote)
                                }
                            }
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
            .navigationTitle("儿童模式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button {
                    pwd = ""; pwdErr = ""; showPwd = true
                } label: {
                    Image(systemName: "lock.fill").font(.body.weight(.semibold))
                }
            }
            .sheet(isPresented: $showPwd) { pwdSheet }
            .task { if items.isEmpty { load() } }
            .tint(Theme.warm)
        }
    }

    private var pwdSheet: some View {
        VStack(spacing: 16) {
            Capsule().fill(Color.white.opacity(0.2)).frame(width: 40, height: 5).padding(.top, 10)
            Text("退出儿童模式").font(.headline)
            Text("请家长输入密码").font(.caption).foregroundColor(Theme.dim)

            SecureField("密码", text: $pwd)
                .keyboardType(.numberPad)
                .padding(12)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if !pwdErr.isEmpty {
                Text(pwdErr).font(.caption).foregroundColor(.red)
            }

            HStack(spacing: 12) {
                Button("取消") { showPwd = false }
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Button("确定") {
                    if store.exitKidsMode(pwd: pwd) {
                        showPwd = false
                    } else {
                        pwdErr = "密码不对"
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(Theme.warm)
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Spacer()
        }
        .padding(20)
        .background(Theme.bgTop.ignoresSafeArea())
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
