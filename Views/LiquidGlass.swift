import SwiftUI

extension View {
    /// 液态玻璃背景：部署目标为 iOS 26+，直接使用原生 `glassEffect`。
    ///
    /// 遵循官方建议的「先形状/材质，后 glassEffect」顺序：
    /// - 材质背景提供形状与基础毛玻璃
    /// - `glassEffect()` 叠加原生液态玻璃效果
    func liquidGlass<S: InsettableShape>(in shape: S) -> some View {
        self.background(.ultraThinMaterial, in: shape)
            .glassEffect()
    }
}
