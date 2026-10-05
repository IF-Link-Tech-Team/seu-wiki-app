import SwiftUI

/// 品牌色的可读前景色。
///
/// 深色模式下 accent 是亮绿 `#34D6AB`，白字压上去的对比度只有 **1.83:1**
/// （实测计算，WCAG AA 要求 4.5:1），胶囊选中态、chip、按钮上的白字全部看不清。
/// 深绿 `#00382B` 压在同一底色上是 **7.08:1**，所以这里按外观切换前景色。
///
/// ⚠️ **凡是「accent 色作底 + 文字盖在上面」的地方都要用 `Color.accentInk`**，
/// 不要直接写 `.white`。`AccentInk.colorset` 的符号由 Xcode 自动生成。
extension Color {
    /// WCAG 相对亮度与对比度，供设计 token 自查与单元测试使用。
    enum WCAG {
        /// sRGB 相对亮度。
        static func luminance(red: Double, green: Double, blue: Double) -> Double {
            func channel(_ c: Double) -> Double {
                c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
        }

        /// 对比度，(lighter + 0.05) / (darker + 0.05)。
        static func ratio(red1: Double, green1: Double, blue1: Double,
                          red2: Double, green2: Double, blue2: Double) -> Double {
            let a = luminance(red: red1, green: green1, blue: blue1)
            let b = luminance(red: red2, green: green2, blue: blue2)
            let lighter = max(a, b), darker = min(a, b)
            return (lighter + 0.05) / (darker + 0.05)
        }
    }
}
