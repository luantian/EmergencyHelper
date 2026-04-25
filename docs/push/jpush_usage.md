# EmergencyHelper 极光推送接入说明

## 1. 目标

实现以下效果：

1. App 在前台、后台、关闭状态都能收到系统通知。
2. 用户点击通知后，自动打开 App 并跳转到事件页面。
3. 后端同事可直接调用一个封装类完成推送。

---

## 2. 安卓端（Flutter）已完成内容

已在项目中完成以下接入：

1. 新增 `jpush_flutter` 依赖。
2. 新增 `PushService`，负责：
   - 初始化极光 SDK；
   - 请求通知权限（Android 13+）；
   - 登录后绑定别名（alias）；
   - 退出登录解绑别名；
   - 解析通知 payload 并路由到页面。
3. App 启动时自动初始化推送，并尝试用本地登录态恢复别名。
4. 登录成功后自动绑定别名，退出登录自动解绑。
5. 点击通知时自动按 `route/page/eventId` 跳转到事件详情/反馈/动态页面。

---

## 3. 你需要配置的参数

### 3.1 Flutter 运行参数（必须）

`PushService` 读取 Dart 环境变量：

- `JPUSH_APPKEY`
- `JPUSH_CHANNEL`（可选，默认 `developer-default`）
- `JPUSH_PRODUCTION`（可选，默认 `false`）

示例（开发环境）：

```bash
flutter run \
  --dart-define=JPUSH_APPKEY=你的极光AppKey \
  --dart-define=JPUSH_CHANNEL=developer-default \
  --dart-define=JPUSH_PRODUCTION=false
```

### 3.2 Android Gradle 参数（建议）

`android/app/build.gradle.kts` 已配置读取 `gradle.properties`：

- `JPUSH_APPKEY`
- `JPUSH_CHANNEL`

请在 `android/gradle.properties` 增加：

```properties
JPUSH_APPKEY=你的极光AppKey
JPUSH_CHANNEL=developer-default
```

> 建议同时配置 dart-define 与 gradle.properties，保证 Dart 层和 Android 层参数一致。

---

## 4. 别名约定（前后端统一）

客户端登录后绑定别名规则：

- `alias = u_{userId}`

例如用户 ID 是 `151`，则 alias 为 `u_151`。

后端推送时直接按 alias 推送即可，无需依赖 registrationId。

### 4.1 `userId` 的准确含义（重点）

这里的 `userId` 指的是“平台用户主键 ID”，不是账号名，也不是部门 ID。

推荐来源：

1. 登录后调用 `/admin-api/system/auth/get-permission-info`
2. 取返回中的 `data.user.id`
3. 用这个值拼 alias：`u_{data.user.id}`

示例：

1. 若 `data.user.id = 151`，则 alias 是 `u_151`
2. 后端调用推送时也必须使用同一个 `151`，否则会推不到

注意：

1. 不要用 `deptId`（部门 ID）
2. 不要用 `tenantId`
3. 不建议用 `username`（账号名可能变更）

---

## 5. 通知 payload 约定

后端推送 `extras` 字段建议至少包含：

```json
{
  "eventId": "evt-20260411-001",
  "page": "event_detail",
  "route": "/event-detail/evt-20260411-001",
  "type": "event_update"
}
```

说明：

1. `route` 优先级最高，App 直接按 route 跳转。
2. 若没有 `route`，客户端会按 `page + eventId` 自动推导路由。

---

## 6. 后端封装类

文件位置：

- `docs/push/backend/JPushEventNotifier.java`
- `docs/push/backend/spring/JPushProperties.java`
- `docs/push/backend/spring/JPushSpringConfiguration.java`
- `docs/push/backend/spring/JPushEventPushService.java`

功能：

1. 支持按 alias / registrationId 推送；
2. 自动构建极光 REST API 请求；
3. 内置事件页面模板（详情、反馈、动态）；
4. 返回统一 `PushResult`，便于记录日志和重试。

### 6.1 依赖

该类使用：

1. Java 17 `java.net.http.HttpClient`
2. Jackson `ObjectMapper`

Spring Boot 项目一般已包含 Jackson；如果没有，请加：

```xml
<dependency>
  <groupId>com.fasterxml.jackson.core</groupId>
  <artifactId>jackson-databind</artifactId>
</dependency>
```

### 6.2 使用示例

```java
JPushEventNotifier notifier = new JPushEventNotifier(
    "你的AppKey",
    "你的MasterSecret",
    true // 生产环境 true，测试环境 false
);

JPushEventNotifier.EventPush push = JPushEventNotifier.EventPush
    .toEventDetail("evt-20260411-001", "事件流转提醒", "事件已转派，请及时处理")
    .withExtras(Map.of("bizType", "assign"));

JPushEventNotifier.PushResult result = notifier.pushToAlias("u_151", push);

if (!result.success()) {
    // 记录失败日志并做重试
}
```

### 6.3 Spring Bean 版本（推荐）

Spring Bean 版本已经准备好，直接复制到你们后端工程即可。

`application.yml` 示例：

```yaml
jpush:
  app-key: 你的极光AppKey
  master-secret: 你的MasterSecret
  apns-production: true
  ttl-seconds: 86400
  api-url: https://api.jpush.cn/v3/push
```

业务层注入并调用示例：

```java
@Service
public class EventNotifyDomainService {
    private final JPushEventPushService pushService;

    public EventNotifyDomainService(JPushEventPushService pushService) {
        this.pushService = pushService;
    }

    public void notifyAssign(Long userId, String eventId) {
        pushService.pushEventDetailToUser(
                userId,
                eventId,
                "事件转派提醒",
                "您有新的事件待处理"
        );
    }
}
```

说明：

1. `JPushSpringConfiguration` 会自动创建 `JPushEventNotifier` Bean。
2. `JPushEventPushService` 已封装 alias 规则（`u_{userId}`）和异常转换。
3. 业务代码只需要传 `userId + eventId + 标题 + 内容`。

---

## 7. 联调步骤

1. 先在极光控制台确认应用、包名、厂商通道配置正确。
2. 安装最新 App，登录后确认已绑定 alias（看客户端日志）。
3. 用后端封装类按 alias 发送测试通知。
4. 验证：
   - App 前台可收到；
   - App 后台/关闭可从系统通知栏弹出；
   - 点击后可跳到对应事件页面。

---

## 8. 常见问题

1. 收不到通知：
   - 检查通知权限、自启动、电池优化白名单；
   - 检查极光 AppKey、包名、签名是否一致；
   - 检查 alias 是否按 `u_{userId}` 统一。
2. 点击后不跳转：
   - 检查 `extras.route` 是否有效；
   - 检查 `eventId` 是否存在；
   - 检查 App 内对应路由是否已注册。
3. 用户“强行停止”App 后收不到：
   - 这是 Android 系统限制，属于预期行为，需要用户侧允许自启动并解除省电限制。
