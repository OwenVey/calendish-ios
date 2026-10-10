import SwiftUI

/// Popovers dim the app's tint behind them, which would gray out the selected tab. The tab bar keeps its color.
enum TabBarTint {
    static func keepsColor(_ keeps: Bool) {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        for tabBar in windows.flatMap({ tabBars(in: $0) }) { tabBar.tintAdjustmentMode = keeps ? .normal : .automatic }
    }

    private static func tabBars(in view: UIView) -> [UITabBar] {
        if let tabBar = view as? UITabBar { return [tabBar] }
        return view.subviews.flatMap { tabBars(in: $0) }
    }
}
