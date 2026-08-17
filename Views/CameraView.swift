import SwiftUI

/// 主界面：全屏预览 + 底部控制区（预设 / 调色盘 / 强度 / 快门）。
struct CameraView: View {
    @StateObject private var vm = CameraViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            if vm.permissionDenied {
                permissionDeniedView
            } else {
                MetalPreviewRepresentable(vm: vm)
                    .ignoresSafeArea()
            }

            VStack(spacing: 16) {
                presetBar
                HStack(spacing: 24) {
                    shutterButton
                    ColorPaletteView(vector: $vm.style)
                        .frame(width: 160, height: 160)
                    intensitySlider
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 22)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            // 切换摄像头按钮（右上角）
            VStack {
                HStack {
                    Spacer()
                    switchCameraButton
                        .padding(.trailing, 16)
                        .padding(.top, 56)
                }
                Spacer()
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    // MARK: - 权限被拒提示

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.6))
            Text("需要相机权限")
                .font(.title3)
                .foregroundColor(.white)
            Text("请在「设置 > 隐私与安全性 > 相机」中\n允许 PhotoStyleCamera 访问相机")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("前往设置")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.black)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Capsule().fill(Color.white))
            }
        }
        .padding()
    }

    // MARK: - 切换摄像头

    private var switchCameraButton: some View {
        Button {
            vm.switchCamera()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .padding(10)
                .liquidGlass(in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
        }
    }

    // MARK: - 预设横向选择

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
                            .liquidGlass(in: Capsule())
                            .overlay(
                                Capsule().fill(
                                    vm.style == preset.vector
                                        ? Color.white.opacity(0.2)
                                        : .clear)
                            )
                            .overlay(
                                Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - 快门按钮

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

    // MARK: - 强度滑块

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