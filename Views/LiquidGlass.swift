import SwiftUI

extension View {
    /// 液态玻璃背景：iOS 26+ 使用原生 `glassEffect`，低版本降级为超薄材质毛玻璃。
    ///
    /// 遵循官方建议的「先形状/材质，后 glassEffect」顺序：
    /// - 材质背景提供形状与基础毛玻璃（全版本生效）
    /// - `glassEffect()` 在 iOS 26+ 叠加原生液态玻璃效果
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self.background(.ultraThinMaterial, in: shape)
                .glassEffect()
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
