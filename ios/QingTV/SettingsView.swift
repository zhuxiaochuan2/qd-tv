import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var sub = ""
    @State private var msg = ""
    @State private var repos: [Repo] = []
    @State private var busy = false

    // 儿童模式
    @State private var showKidsSheet = false
    @State private var kidsSheetMode = 0        // 0=设密码并开启  1=输密码关闭  2=改密码
    @State private var pwd1 = ""
    @State private var pwd2 = ""
    @State private var pwdMsg = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("儿童模式"),
                        footer: Text("开启后 App 只显示动画片，退出要输密码。孩子拿手机也跑不出去。")) {
                    if store.kidsMode {
                        HStack {
                            Text("正在儿童模式")
                            Spacer()
                            Text("🔒").font(.title3)
                        }
                        Button("退出儿童模式（要密码）") {
                            kidsSheetMode = 1; pwd1 = ""; pwd2 = ""; pwdMsg = ""; showKidsSheet = true
                        }
                        .foregroundColor(.orange)
                    } else {
                        Button("开启儿童模式") {
                            kidsSheetMode = 0; pwd1 = ""; pwd2 = ""; pwdMsg = ""; showKidsSheet = true
                        }
                        .foregroundColor(.green)
                    }
                    Button("修改密码") {
                        kidsSheetMode = 2; pwd1 = ""; pwd2 = ""; pwdMsg = ""; showKidsSheet = true
                    }
                }

                Section(header: Text("我的内容")) {
                    NavigationLink(destination: FavoritesView()) {
                        HStack {
                            Image(systemName: "heart.fill").foregroundColor(Theme.warm)
                            Text("我的收藏")
                            Spacer()
                            Text("\(store.favorites.count)").foregroundColor(Theme.dim)
                        }
                    }
                    HStack {
                        Image(systemName: "clock.arrow.circlepath").foregroundColor(Theme.accent)
                        Text("观看记录")
                        Spacer()
                        Text("\(store.history.count)").foregroundColor(Theme.dim)
                    }
                    Button("清空观看记录") {
                        store.clearHistory()
                        msg = "已清空观看记录"
                    }
                    .foregroundColor(.orange)
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

                Section(header: Text("关于")) {
                    Text("影匣 1.8.0 · 纯客户端壳，不含任何内容").font(.caption)
                    Text("发现用豆瓣，播放靠 cms 搜索匹配。无广告、无登录、无推送。").font(.caption2).foregroundColor(.secondary)
                }
            }
            .navigationTitle("设置")
            .onAppear { if sub.isEmpty { sub = store.subscription } }
            .sheet(isPresented: $showKidsSheet) { kidsSheet }
        }
    }

    private var kidsSheet: some View {
        VStack(spacing: 14) {
            Text(kidsSheetMode == 0 ? "设置儿童模式密码"
                 : (kidsSheetMode == 1 ? "退出儿童模式" : "修改密码"))
                .font(.headline)

            SecureField(kidsSheetMode == 2 ? "原密码" : "密码（建议 4 位数字）", text: $pwd1)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)

            if kidsSheetMode != 1 {
                SecureField("再输一次", text: $pwd2)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
            }

            if !pwdMsg.isEmpty {
                Text(pwdMsg).font(.caption).foregroundColor(.red)
            }

            HStack(spacing: 12) {
                Button("取消") { showKidsSheet = false }
                    .buttonStyle(.bordered)
                Button("确定") { doKids() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }

    private func doKids() {
        switch kidsSheetMode {
        case 0:   // 开启：设密码
            guard pwd1.count >= 4 else { pwdMsg = "至少 4 位"; return }
            guard pwd1 == pwd2 else { pwdMsg = "两次不一样"; return }
            store.setKidsPwd(pwd1)
            store.enterKidsMode()
            showKidsSheet = false
        case 1:   // 关闭：验密码
            if store.exitKidsMode(pwd: pwd1) {
                showKidsSheet = false
            } else {
                pwdMsg = "密码不对"
            }
        default:  // 改密码：先验旧的
            guard pwd1 == store.kidsPwd else { pwdMsg = "原密码不对"; return }
            guard pwd2.count >= 4 else { pwdMsg = "新密码至少 4 位"; return }
            store.setKidsPwd(pwd2)
            showKidsSheet = false
            msg = "密码已改"
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
