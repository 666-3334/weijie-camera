# PhotoStyleCamera

在 iPhone 13 Pro（A15）上复刻「接近 iPhone 16 摄影风格 + 调色盘」的自定义相机 App。

核心思路：**人像语义分割 + 分区域色调映射（肤色保护）+ 可逆元数据**，用 iOS 公开 API 逼近 Apple 私有 ISP 管线达成的效果。

## 技术栈

| 模块 | 技术 |
|---|---|
| 相机取景/拍照 | AVFoundation（`AVCaptureVideoDataOutput` + `AVCapturePhotoOutput`） |
| 人像分割 | Vision（`VNGeneratePersonSegmentationRequest`） |
| 色调映射 | Core Image（`CIColorControls` + `CITemperatureAndTint` + 自定义 `CIColorKernel`） |
| 实时预览 | Metal（`MTKView` + `CIContext`） |
| UI | SwiftUI |

## 目录结构

```
PhotoStyleCamera/
├── PhotoStyleCameraApp.swift        # 入口
├── Models/PhotoStyle.swift          # StyleVector + 预设风格
├── Camera/CameraManager.swift       # 相机会话 + 预览帧 + 拍照 + 权限 + 方向
├── Camera/MetalPreviewView.swift    # Metal 实时预览（P3 色彩空间）
├── Segmentation/PersonSegmenter.swift  # Vision 人像分割
├── Rendering/StyleEngine.swift      # 分区域色调映射 + intensity 混合
├── ViewModel/CameraViewModel.swift  # 协调层（帧 → 分割 → 渲染 → 预览 + 权限）
├── Views/ColorPaletteView.swift     # 二维调色盘交互
├── Views/CameraView.swift           # 主界面（含权限提示 + 前后切换）
└── Photo/PhotoStore.swift           # 可逆编辑持久化 + 系统相册保存
```

## 如何在 Xcode 中运行

1. 新建 iOS App 工程，Product Name 用 `PhotoStyleCamera`，Interface 选 **SwiftUI**，Language **Swift**。
2. 删除模板自带的 `ContentView.swift`（或保留不用），把本目录所有 `.swift` 文件按目录结构拖入工程（勾选 Copy if needed）。
3. 部署目标设为 **iOS 26.0**。
4. 在 `Info.plist` 添加权限描述：
   - `NSCameraUsageDescription`（例如「用于拍摄并应用自定义摄影风格」）
   - `NSPhotoLibraryAddUsageDescription`（例如「用于将渲染后的照片保存到相册」）
5. 真机运行（相机功能模拟器不可用）。

## 关键设计说明

### 1. 肤色保护怎么实现的？
`StyleEngine` 对**人像区域**和**背景区域**应用两套不同的色调参数：
- 背景：饱和度/色温按风格向量正常变化
- 人像：变化幅度减半（`region == .person` 时缩放）
再用 `CIBlendWithMask` 按人像 mask 合成。这近似了 iPhone 16「调肤色时联动背景、避免突兀」的效果。

### 2. 可逆编辑
拍照时保存「原图 JPEG + 风格参数 JSON」到 `Documents/Edits/`。之后可重新加载原图，用同一套 `StyleVector` 重渲染——这才是真正可逆，而非把滤镜烘死成成品。

同时将渲染后的成品自动保存到系统相册，方便在系统「照片」App 中查看和分享。

### 3. 画面方向
`CameraManager` 监听 `UIDevice.orientationDidChangeNotification`，根据设备方向 + 前后置动态计算 `previewOrientation`，不再硬编码。前置摄像头自动启用镜像。

### 4. 相机权限
启动时自动检查权限状态：
- 未授权 → 弹出系统权限请求
- 已拒绝 → 显示引导页面，可跳转系统设置
- 已授权 → 直接启动相机

## 已知限制（与 Apple 版的硬差距）

- 拿不到智能 HDR / Deep Fusion 管线，只能处理融合后的帧
- 拿不到 Apple 私有肤色 ML 模型，场景感知需自行调参逼近
- A15 实时分割 + 多层色调映射有功耗/发热压力（但可实时运行）
- 可逆性仅限本 App 内，导出到系统相册即为成品

## 进一步优化方向

1. **肤色 mask 细化**：在 person mask 内再做一次肤色检测（YCbCr 肤色范围），让「只保护皮肤、衣服仍可调色」。
2. **性能**：改用 Metal compute shader 合并分割与调色到单 Pass，进一步降功耗。
3. **缩略图实时预览**：在调色盘背景上实时渲染当前色调的小缩略图（当前为示意渐变）。