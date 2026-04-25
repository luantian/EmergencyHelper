# Emergency Helper

面向 Android 8.0+（`minSdk = 26`）的应急业务 App。

## UI 方案

- 主 UI 库：`GetWidget`
- 选择原因：组件覆盖高、政务风格容易落地、多人接手学习成本低
- 主题基色：`#0B4F9E`（政务蓝）

## 当前页面骨架

1. 首页：天气信息、通知、业务办理/信息查询/公众服务分区
2. 消息：消息列表占位页
3. 我的：个人信息 + 功能入口列表
4. 底部导航：首页 / 消息 / 我的

## 目录结构

```text
lib/
  main.dart
  src/
    app.dart
    core/
      constants/
      di/
      errors/
      logging/
      network/
      routing/
      theme/
    features/
      home/
        presentation/
          home_page.dart
          tabs/
            home_tab_page.dart
            message_tab_page.dart
            mine_tab_page.dart
      about/
        presentation/
          about_page.dart
```

## 运行

```bash
flutter pub get
flutter run
```

## 协作约定

1. 新业务必须按 `features/<module>/presentation|data|domain` 分层。
2. 页面仅做展示和交互，业务逻辑放 `data/domain` 与状态层。
3. 公共能力统一放 `core`，避免在页面里直接写网络代码。
4. 每个新模块至少补一个测试（widget 或 unit）。

