import SwiftUI
import UIKit

/// 强制横/竖屏：用户没开自动旋转也能横过来
enum Orientation {
    /// AppDelegate 会读这个值决定支持哪些方向
    static var mask: UIInterfaceOrientationMask = .allButUpsideDown

    static func set(_ m: UIInterfaceOrientationMask) {
        mask = m
        if #available(iOS 16.0, *) {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first else { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: m))
            scene.keyWindow?.rootViewController?
                .setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            let v: Int
            switch m {
            case .landscapeRight: v = UIInterfaceOrientation.landscapeRight.rawValue
            case .landscapeLeft: v = UIInterfaceOrientation.landscapeLeft.rawValue
            default: v = UIInterfaceOrientation.portrait.rawValue
            }
            UIDevice.current.setValue(v, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    static func landscape() { set(.landscapeRight) }
    static func portrait() { set(.portrait) }
    static func unlock() { set(.allButUpsideDown) }

    static var isLandscape: Bool {
        UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Orientation.mask
    }
}
