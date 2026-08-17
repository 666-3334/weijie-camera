import CoreImage
import CoreImage.CIFilterBuiltins

/// 把 StyleVector 转成「人像 / 背景」两套色调参数。
/// 人像参数更保守，从而近似实现 iPhone 16 的「肤色保护」。
struct ToneParams {
    var saturation: Double = 1
    var contrast: Double = 1
    var brightness: Double = 0
    var temperature: Double = 6500   // 开尔文
}

enum StyleRegion {
    case person
    case background
}

/// 核心渲染引擎：原图 + 人像 mask + 风格向量 -> 结果图。
/// 全部在 GPU 上（Core Image 默认 Metal 后端）完成，可实时预览。
final class StyleEngine {

    private let context = CIContext(options: [.cacheIntermediates: false])

    /// 结果与原图的线性混合 kernel，用于实现 intensity（强度）
    private let mixKernel: CIColorKernel = {
        let src = """
        kernel vec4 mixKernel(__sample a, __sample b, float t) {
            return mix(a, b, t);
        }
        """
        guard let k = CIColorKernel(source: src) else {
            fatalError("mixKernel 编译失败")
        }
        return k
    }()

    /// 由风格向量生成某一区域的色调参数
    func toneParams(for vector: StyleVector, region: StyleRegion) -> ToneParams {
        // tone: -1(冷)→色温 8500K，+1(暖)→4500K
        let temperature = 6500 + vector.tone * -2000
        var p = ToneParams(
            saturation: 1 + vector.color * 0.6,
            contrast: 1 + vector.color * 0.15,
            temperature: temperature
        )
        if region == .person {
            // 肤色保护：人像区域的饱和度/色温变化幅度减半，让肤色更稳
            p.saturation = 1 + (p.saturation - 1) * 0.5
            p.temperature = 6500 + (p.temperature - 6500) * 0.5
        }
        return p
    }

    /// 对图像应用一套色调映射（饱和度/对比度 + 色温）
    private func apply(_ image: CIImage, params: ToneParams) -> CIImage {
        var out = image

        let saturation = CIFilter.colorControls()
        saturation.saturation = Float(params.saturation)
        saturation.contrast = Float(params.contrast)
        saturation.brightness = Float(params.brightness)
        saturation.inputImage = out
        out = saturation.outputImage ?? out

        let temp = CIFilter.temperatureAndTint()
        temp.neutral = CIVector(x: 6500, y: 0)
        temp.targetNeutral = CIVector(x: params.temperature, y: 0)
        temp.inputImage = out
        out = temp.outputImage ?? out

        return out
    }

    /// 核心处理。
    /// - Parameters:
    ///   - source: 方向已修正的原始帧（CIImage）
    ///   - mask: 人像灰度 mask（人像=白、背景=黑），与 source 同 extent；可为 nil
    ///   - style: 当前风格向量
    func render(source: CIImage, mask: CIImage?, style: StyleVector) -> CIImage {
        let styled: CIImage
        if let mask {
            // 人像、背景分开调色，再按 mask 合成 —— 这是「肤色保护」的关键
            let person = apply(source, params: toneParams(for: style, region: .person))
            let background = apply(source, params: toneParams(for: style, region: .background))
            let blend = CIFilter(name: "CIBlendWithMask")!
            blend.setValue(person, forKey: kCIInputImageKey)
            blend.setValue(background, forKey: kCIInputBackgroundImageKey)
            blend.setValue(mask, forKey: kCIInputMaskImageKey)
            styled = blend.outputImage ?? source
        } else {
            styled = apply(source, params: toneParams(for: style, region: .background))
        }

        // intensity 混合：result = mix(source, styled, t)
        if style.intensity >= 1 { return styled }
        let t = NSNumber(value: Float(style.intensity))
        return mixKernel.apply(extent: source.extent, arguments: [source, styled, t]) ?? styled
    }

    /// 渲染成 CGImage（用于保存成品）
    func renderToCGImage(_ image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent)
    }
}
