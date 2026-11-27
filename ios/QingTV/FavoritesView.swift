import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var store: Store
    @State private var playTarget: PlayTarget?

    private let hPad: CGFloat = 12
    private let gap: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let cw = max(80, floor((geo.size.width - hPad * 2 - gap * 2) / 3))
            let ch = floor(cw * 1.48)
            let cols = [GridItem(.fixed(cw), spacing: gap),
                        GridItem(.fixed(cw), spacing: gap),
                        GridItem(.fixed(cw), spacing: gap)]

            ZStack {
                BrandBackground()

                if store.favorites.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "heart").font(.largeTitle).foregroundColor(Theme.dim)
                        Text("还没有收藏，进详情页点右上角的心").font(.caption).foregroundColor(Theme.dim)
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: cols, spacing: 14) {
                            ForEach(store.favorites) { f in
                                Button { playTarget = PlayTarget(title: f.title, pic: f.pic, rate: f.rate) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        NetImage(url: f.pic)
                                            .frame(width: cw, height: ch)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .overlay(RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.white.opacity(0.07), lineWidth: 1))
                                        Text(f.title)
                                            .font(.caption).foregroundColor(Theme.text)
                                            .lineLimit(1).truncationMode(.tail)
                                            .minimumScaleFactor(0.85)
                                            .frame(width: cw, alignment: .leading)
                                    }
                                    .frame(width: cw)
                                    .contextMenu {
                                        Button("取消收藏", role: .destructive) {
                                            store.toggleFav(title: f.title, pic: f.pic, rate: f.rate)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, hPad)
                        .padding(.top, 12)
                    }
                }
            }
        }
        .fullScreenCover(item: $playTarget) { t in
            MovieView(title: t.title, pic: t.pic, rate: t.rate,
                      doubanID: t.doubanID, kind: t.kind)
                .environmentObject(store)
        }
        .navigationTitle("我的收藏")
        .navigationBarTitleDisplayMode(.inline)
    }
}
