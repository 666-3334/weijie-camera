import SwiftUI

/// 主界面：全屏预览 + 底部控制区（预设 / 调色盘 / 强度 / 快门）。
struct CameraView: View {
    @StateObject private var vm = CameraViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            MetalPreviewRepresentable(vm: vm)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                presetBar
                HStack(spacing: 24) {
                    shutterButton
                    ColorPaletteView(vector: $vm.style)
                        .frame(width: 160, height: 160)
                    intensitySlider
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.6)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    // 预设横向选择
    private var presetBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(StylePreset.presets) { preset in
                    Button {
                        vm.style = preset.vector
                    } label: {
                        Text(preset.name)
                            .font(.footnote).fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(
                                Capsule().fill(
                                    vm.style == preset.vector
                                        ? Color.white.opacity(0.35)
                                        : Color.white.opacity(0.15))
                            )
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var shutterButton: some View {
        Button {
            vm.capture()
        } label: {
            ZStack {
                Circle().stroke(Color.white, lineWidth: 3).frame(width: 70, height: 70)
                Circle().fill(Color.white).frame(width: 56, height: 56)
            }
        }
    }

    // 强度滑块
    private var intensitySlider: some View {
        VStack(spacing: 6) {
            Text("强度")
                .font(.caption2).foregroundColor(.white.opacity(0.8))
            Slider(value: $vm.style.intensity, in: 0...1)
                .frame(width: 60)
                .rotationEffect(.degrees(-90))
                .frame(height: 100)
        }
    }
}

/// 把 MetalPreviewView 包进 SwiftUI，并在创建后回传给 VM
private struct MetalPreviewRepresentable: UIViewRepresentable {
    let vm: CameraViewModel

    func makeUIView(context: Context) -> MetalPreviewView {
        let view = MetalPreviewView(frame: .zero, device: nil)
        view.contentMode = .scaleAspectFill
        vm.attach(preview: view)
        return view
    }

    func updateUIView(_ uiView: MetalPreviewView, context: Context) {}
}
