# EmergencyHelper（应急事件管理）

Flutter Android 应用（`minSdk = 26`，即 Android 8.0+）。

本仓库已包含主要业务代码，可直接用于继续开发与联调。

## 1. 当前业务模块

- 登录与权限控制
- 工作台（天气、统计、快捷入口）
- 事件上报 / 事件列表 / 事件详情 / 动态 / 反馈 / 转派
- 衍生风险上报 / 风险列表 / 风险详情 / 动态 / 反馈 / 转派
- 重点点位（列表 + 地图）
- 通讯录（树结构）
- 消息中心（角标、已读/未读）
- 音视频通话（TRTC/TUICallKit 相关链路）
- 推送相关（TIMPush、厂商通道配置）

## 2. 主要技术栈

- Flutter 3.x（Dart `^3.11.4`）
- 路由：`go_router`
- 状态管理：`provider`
- 网络：`dio`
- UI 组件：`getwidget`
- 地图与定位：百度地图 Flutter SDK
- 音视频：Tencent TUICallKit / TRTC
- 推送：Tencent TIMPush（含华为/荣耀/小米/vivo/oppo 通道）

## 3. 目录结构（核心）

```text
lib/
  src/
    core/                  # 常量、路由、网络、主题、通用组件
    features/
      auth/                # 登录鉴权
      home/                # 工作台/消息/我的
      event/               # 事件模块
      risk/                # 衍生风险模块
      key_point/           # 重点点位
      push/                # 推送能力
      trtc/                # 音视频能力
      weather/             # 天气能力
android/                   # Android 原生配置
assets/                    # 图标与图片资源
third_party/               # 本地依赖覆盖（atomic_x_core）
```

## 4. 开发环境要求

- Flutter SDK（建议与当前项目保持同一主版本）
- Android Studio（或 VS Code + Android SDK）
- JDK 17
- Android SDK / platform-tools（可用 `adb`）

## 5. 首次启动（新同事必看）

1. 克隆仓库并进入项目目录。
2. 执行依赖安装：

```bash
flutter pub get
```

3. 连接设备并运行：

```bash
flutter run
```

4. 若使用无线调试，可先确保 `adb devices` 能看到设备，再执行 `flutter run -d <deviceId>`。

## 6. 关键配置文件说明

### 6.1 签名配置（Release 必需）

- 模板文件：`android/key.properties.example`
- 实际文件：`android/key.properties`（已被 `.gitignore` 忽略，不入库）
- `android/key.properties` 需要指向你的 `release.jks`

示例：

```properties
storePassword=xxxx
keyPassword=xxxx
keyAlias=xxxx
storeFile=../keystore/release.jks
```

### 6.2 华为配置

- 文件：`android/app/agconnect-services.json`
- 用于 HMS / 厂商推送相关能力。

### 6.3 TIMPush 厂商配置

- 文件：`android/app/src/main/assets/timpush-configs.json`
- 需要与腾讯云 IM 控制台中的应用配置一致（包名、签名、厂商参数）。

### 6.4 地图 Key

- 文件：`android/app/src/main/AndroidManifest.xml`
- `com.baidu.lbsapi.API_KEY` 已在 Manifest 中配置，可按项目需要替换。

### 6.5 服务端地址与接口常量

- 文件：`lib/src/core/constants/app_constants.dart`
- 包含 API Base URL、鉴权接口、字典接口、TRTC 相关接口路径等。

## 7. 常用命令

```bash
# 获取依赖
flutter pub get

# 本地运行
flutter run

# 静态检查
flutter analyze --no-pub

# 打 debug 包
flutter build apk --debug --split-per-abi
```

## 8. 交接建议（给下一位开发）

1. 先跑通登录、消息、事件上报、事件详情、通话发起这 5 条主链路。
2. 再检查推送离线链路（需要后端 + 厂商通道 + 真机联调）。
3. 若要发版，优先确认：
   - 签名文件是否正确
   - 包名、SHA1、厂商推送配置是否一致
   - 关键权限（通知、相机、麦克风、存储、定位）是否可申请

## 9. 开发约定

- 新增/修改源码统一使用 UTF-8 编码。
- 业务代码放在 `lib/src/features/<module>` 内，公共能力放在 `lib/src/core`。
- 非必要的本机缓存、大文件、构建产物不要入库（已通过 `.gitignore` 约束）。

