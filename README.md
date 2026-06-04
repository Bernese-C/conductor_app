# 指挥家 (Conductor) — Flutter 跨平台指挥模拟器

利用前置摄像头（iOS/Android）或鼠标（Windows）追踪手指/鼠标的上下运动，
模拟交响乐指挥。实时检测"拍点"计算 BPM，动态改变内置音乐的播放速度和音量。

## 功能

- 🎯 **手势追踪**：iOS/Android 使用前置摄像头 + Google ML Kit 手部关键点检测
- 🖱️ **鼠标模拟**：Windows 使用鼠标 Y 轴运动模拟拍点
- 🎵 **拍点检测**：实时识别手指向下挥动的最低点，计算瞬时 BPM
- 🎼 **内置音乐**：Twinkle Twinkle Little Star 旋律，自动循环播放
- ⚡ **动态变速**：播放速度 = 实时 BPM / 120（范围 0.5x ~ 2.0x）
- 📊 **力度映射**：挥动幅度越大，音量越大（0.2 ~ 1.0）
- 🎨 **Material Design 3**：深色主题，BPM 仪表盘，音量指示器

## 项目结构

```
conductor_app/
├── lib/
│   ├── main.dart                    # 应用入口 + UI + Provider 集成
│   ├── conductor_logic.dart         # 拍点检测算法 + BPM 计算
│   ├── hand_tracker.dart            # 手部追踪（ML Kit / 鼠标）
│   ├── midi_player.dart             # 音频播放 + WAV 合成
│   └── camera_preview_widget.dart   # 摄像头预览 / 鼠标追踪区域
├── ios/Runner/Info.plist            # iOS 摄像头权限
├── android/app/src/main/AndroidManifest.xml  # Android 权限
├── pubspec.yaml
└── README.md
```

## 环境要求

- Flutter SDK >= 3.1.0
- iOS 15.0+（ML Kit 要求）
- Android API 21+
- Windows 10+

## 快速开始

### 1. 创建 Flutter 平台脚手架

```bash
# 进入项目目录
cd conductor_app

# 生成平台特定文件（iOS Podfile、Android build.gradle 等）
flutter create --platforms=ios,android,windows .
```

### 2. 安装依赖

```bash
flutter pub get
```

### 3. iOS 额外配置

在 `ios/Podfile` 中确保最低 iOS 版本为 15.0：

```ruby
platform :ios, '15.0'
```

然后安装 CocoaPods：

```bash
cd ios && pod install && cd ..
```

### 4. 运行

```bash
# iOS 模拟器
flutter run -d ios

# Android
flutter run -d android

# Windows（鼠标模式）
flutter run -d windows
```

## 拍点检测算法

```
输入：归一化 Y 坐标 (0=顶部, 1=底部)

1. 反转 Y: y' = 1.0 - rawY
   → 手指高 = 大值, 手指低 = 小值
   
2. 维护 prevY, lastY 两个历史值

3. 当 (prevY > lastY) 且 (currentY > lastY):
   → lastY 是局部极小值 = 拍点!
   
4. 防抖：距上次拍点 > 300ms 才触发

5. instantBpm = 60000 / deltaMs
   avgBpm = avgBpm * 0.7 + instantBpm * 0.3
   
6. 力度 = |最高点Y - 拍点Y|, 映射到音量 0.2~1.0
```

## 依赖

| Package | 版本 | 用途 |
|---------|------|------|
| camera | ^0.10.5 | 摄像头帧获取 |
| google_mlkit_hand_landmark | ^0.9.0 | 手部关键点检测 |
| provider | ^6.1.1 | 状态管理 |
| audioplayers | ^5.2.1 | 音频播放 |
| path_provider | ^2.1.1 | 临时文件路径 |

## Windows 鼠标模式

在 Windows 上，Google ML Kit 不可用。应用会自动切换到鼠标追踪模式：
- 在黑色追踪区域内上下移动鼠标
- 鼠标快速下移后上移 = 一个拍点
- 鼠标移动幅度越大 = 音量越大

如需要真正的 Windows 摄像头手势识别，可集成 MediaPipe for Windows
（通过 `tflite_flutter` 或 Native C++ 插件），但不在当前实现范围内。

## 许可

MIT
