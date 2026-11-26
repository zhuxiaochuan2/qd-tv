import SwiftUI

/// 全局配色与常用样式
enum Theme {
    static let bgTop = Color(red: 0.05, green: 0.07, blue: 0.12)
    static let bgBottom = Color(red: 0.02, green: 0.03, blue: 0.06)
    static let card = Color.white.opacity(0.06)
    static let cardHi = Color.white.opacity(0.12)
    static let accent = Color(red: 0.20, green: 0.52, blue: 1.0)
    static let warm = Color(red: 1.0, green: 0.62, blue: 0.26)
    static let text = Color.white
    static let dim = Color.white.opacity(0.55)
}

/// 深色渐变背景
struct BrandBackground: View {
    var warm: Bool = false
    var body: some View {
        ZStack {
            LinearGradient(colors: warm
                           ? [Color(red: 0.16, green: 0.09, blue: 0.05), Theme.bgBottom]
                           : [Theme.bgTop, Theme.bgBottom],
                           startPoint: .top, endPoint: .bottom)
            Circle()
                .fill((warm ? Theme.warm : Theme.accent).opacity(0.20))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(x: 150, y: -260)
        }
        .ignoresSafeArea()
    }
}

/// 圆角药丸按钮
struct Pill: View {
    let text: String
    let selected: Bool
    var color: Color = Theme.accent
    var body: some View {
        Text(text)
            .font(.footnote.bold())
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(selected ? color : Theme.card)
            .foregroundColor(selected ? .white : Theme.dim)
            .clipShape(Capsule())
    }
}

/// 骨架屏占位
struct Skeleton: View {
    @State private var on = false
    var height: CGFloat = 158
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(on ? 0.10 : 0.05))
            .frame(height: height)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// 卡片风格修饰
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}
