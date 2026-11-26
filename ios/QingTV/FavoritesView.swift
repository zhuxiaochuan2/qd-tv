import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var store: Store

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
        ZStack {
            BrandBackground()

            if store.favorites.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "heart").font(.largeTitle).foregroundColor(Theme.dim)
                    Text("还没有收藏，进详情页点右上角的心").font(.caption).foregroundColor(Theme.dim)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(store.favorites) { f in
                            NavigationLink(destination: DetailView(title: f.title, pic: f.pic, rate: f.rate)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    NetImage(url: f.pic)
                                        .frame(width: cellW, height: cellH)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.white.opacity(0.07), lineWidth: 1))
                                    Text(f.title)
                                        .font(.caption).foregroundColor(Theme.text)
                                        .lineLimit(1).truncationMode(.tail)
                                        .frame(width: cellW, alignment: .leading)
                                }
                                .frame(width: cellW)
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
        .navigationTitle("我的收藏")
        .navigationBarTitleDisplayMode(.inline)
    }
}
