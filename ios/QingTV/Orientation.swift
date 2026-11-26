import SwiftUI
import UIKit

/// 强制横/竖屏。用户开了竖屏锁定也能转 —— 用的是「改 mask + 两个 API 一起上」的土办法。
enum Orientation {
    /// AppDelegate 读这个值
    static var mask: UIInterfaceOrientationMask = .allButUpsideDown

    static var keyScene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    static var keyWindow: UIWindow? {
        guard let s = keyScene else { return nil }
        return s.windows.first(where: { $0.isKeyWindow }) ?? s.windows.first
    }

    static var isLandscapeNow: Bool {
        if let s = keyScene, s.interfaceOrientation.isLandscape { return true }
        return UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }

    static func landscape() { force(.landscapeRight) }
    static func portrait() { force(.portrait) }
    static func unlock() { force(.allButUpsideDown) }

    /// 点一下必定生效：三层一起上
    static func force(_ m: UIInterfaceOrientationMask) {
        mask = m

        // 1) 先把整棵 VC 树标记成"方向变了"，否则系统按旧 mask 拒绝
        if let root = keyWindow?.rootViewController {
            markNeedsUpdate(root)
        }

        // 2) iOS 16+ 正路
        if #available(iOS 16.0, *) {
            keyScene?.requestGeometryUpdate(.iOS(interfaceOrientations: m))
        }

        // 3) 经典 hack：iOS 15 全靠它；16/17 上当兜底
        let v: Int
        switch m {
        case .portrait: v = UIInterfaceOrientation.portrait.rawValue
        case .landscapeLeft: v = UIInterfaceOrientation.landscapeLeft.rawValue
        default: v = UIInterfaceOrientation.landscapeRight.rawValue
        }
        if m != .allButUpsideDown {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            UIDevice.current.setValue(v, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }

    private static func markNeedsUpdate(_ vc: UIViewController) {
        vc.setNeedsUpdateOfSupportedInterfaceOrientations()
        for child in vc.children { markNeedsUpdate(child) }
        if let presented = vc.presentedViewController { markNeedsUpdate(presented) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Orientation.mask
    }
}
