import SwiftUI

/// 二维调色盘：横轴 = 色调(tone)，纵轴 = 色彩(color)。
/// 拖拽中心圆点在单位圆内移动，实时更新风格向量。
struct ColorPaletteView: View {
    @Binding var vector: StyleVector

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                PaletteBackground()
                    .frame(width: size, height: size)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1.5))
                    .shadow(radius: 3)
                    .liquidGlass(in: Circle())
                    .position(handlePosition(in: geo, size: size))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                update(at: value.location, in: geo, size: size)
                            }
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func handlePosition(in geo: GeometryProxy, size: CGFloat) -> CGPoint {
        let cx = geo.size.width / 2
        let cy = geo.size.height / 2
        let r = size / 2
        return CGPoint(x: cx + CGFloat(vector.tone) * r,
                       y: cy - CGFloat(vector.color) * r)
    }

    private func update(at point: CGPoint, in geo: GeometryProxy, size: CGFloat) {
        let cx = geo.size.width / 2
        let cy = geo.size.height / 2
        let r = size / 2
        var x = (point.x - cx) / r
        var y = (cy - point.y) / r
        let len = sqrt(x * x + y * y)
        if len > 1 { x /= len; y /= len }   // 限制在单位圆内
        vector = StyleVector(tone: Double(x), color: Double(y), intensity: vector.intensity)
    }
}

/// 调色盘背景（示意性渐变：左上冷+淡、右上暖+淡、左下冷+浓、右下暖+浓）
private struct PaletteBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(
                LinearGradient(colors: [.blue.opacity(0.35), .clear, .orange.opacity(0.5)],
                               startPoint: .leading, endPoint: .trailing))
            Rectangle().fill(
                LinearGradient(colors: [.white.opacity(0.95), .clear, .black.opacity(0.2)],
                               startPoint: .bottom, endPoint: .top))
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
    }
}
