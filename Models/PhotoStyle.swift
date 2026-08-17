import Foundation

/// 二维调色盘坐标，抽象 iPhone 16「摄影风格 + 调色盘」的两个核心维度。
/// - tone:  色调  -1(冷) ... 0(中性) ... +1(暖)
/// - color: 色彩  -1(减淡/低饱和) ... 0(中性) ... +1(浓郁/高饱和)
/// - intensity: 整体强度 0...1，控制风格对原图的影响程度
struct StyleVector: Codable, Equatable {
    var tone: Double
    var color: Double
    var intensity: Double

    static let neutral = StyleVector(tone: 0, color: 0, intensity: 1)

    init(tone: Double = 0, color: Double = 0, intensity: Double = 1) {
        self.tone = min(max(tone, -1), 1)
        self.color = min(max(color, -1), 1)
        self.intensity = min(max(intensity, 0), 1)
    }
}

/// 预设风格（对标 iPhone 16 的「标准 / 丰富 / 活力 / 暖金…」）
struct StylePreset: Identifiable {
    let id: String
    let name: String
    let vector: StyleVector
}

extension StylePreset {
    static let presets: [StylePreset] = [
        StylePreset(id: "standard", name: "标准", vector: .neutral),
        StylePreset(id: "rich",    name: "丰富", vector: StyleVector(tone: 0.20, color: 0.50)),
        StylePreset(id: "vivid",   name: "活力", vector: StyleVector(tone: 0.15, color: 0.85)),
        StylePreset(id: "warm",    name: "暖金", vector: StyleVector(tone: 0.65, color: 0.30)),
        StylePreset(id: "cool",    name: "冷峻", vector: StyleVector(tone: -0.65, color: -0.15)),
        StylePreset(id: "quiet",   name: "宁静", vector: StyleVector(tone: -0.35, color: -0.55)),
        StylePreset(id: "mono",    name: "黑白", vector: StyleVector(tone: 0.0, color: -1.0)),
    ]
}
