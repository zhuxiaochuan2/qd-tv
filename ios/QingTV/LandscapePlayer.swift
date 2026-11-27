import SwiftUI
import UIKit

/// 只允许横屏的宿主控制器：present 出来系统就必然转横屏
final class LandscapeHost: UIViewController {
    private let host: UIHostingController<AnyView>

    init(rootView: AnyView) {
        host = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
        addChild(host)
        host.view.backgroundColor = .black
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscapeRight }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var shouldAutorotate: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}

enum PlayerPresenter {
    private static func topMost() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                ?? scene.windows.first?.rootViewController else { return nil }
        var top = root
        while let p = top.presentedViewController { top = p }
        return top
    }

    /// 直接横屏打开播放器
    static func present<V: View>(_ view: V) {
        Orientation.mask = .landscapeRight
        guard let top = topMost() else { return }
        let host = LandscapeHost(rootView: AnyView(view))
        top.present(host, animated: true) {
            Orientation.landscape()
        }
    }

    /// 关掉并回到竖屏
    static func dismiss() {
        guard let top = topMost() else { return }
        top.dismiss(animated: true) {
            Orientation.unlock()
            Orientation.portrait()
        }
    }
}
