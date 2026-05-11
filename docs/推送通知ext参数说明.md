# 推送通知 ext 参数说明（全部场景）

## 通用字段（所有通知都必须传）

### page（页面类型）
- 类型：String
- 必填：是
- 含义：决定 App 跳转到哪个页面
- 可选值：见下方场景列表

### title（通知标题）
- 类型：String
- 必填：是
- 含义：系统通知栏显示的标题

### content（通知内容）
- 类型：String
- 必填：是
- 含义：系统通知栏显示的内容

---

## 场景 1：事件通知

**page**: `event_notification`

### eventId（事件 ID）
- 类型：String
- 必填：是
- 含义：事件的业务 ID

```json
{
  "page": "event_notification",
  "eventId": "EVT-12345",
  "title": "新事件上报",
  "content": "张三上报了一个新事件"
}
```

跳转目标：事件详情页

---

## 场景 2：气象预警

**page**: `weather_warning`

### eventId（预警 ID）
- 类型：String
- 必填：是
- 含义：预警记录的业务 ID

```json
{
  "page": "weather_warning",
  "eventId": "WARN-67890",
  "title": "气象预警",
  "content": "发布暴雨红色预警"
}
```

跳转目标：气象预警详情页

---

## 场景 3：视频通话邀请（被叫）

**page**: `incoming_call`

### callId（通话 ID）
- 类型：String
- 必填：是
- 来源：调 SDK 发起通话接口（calls()）时，返回结果里自带

### callerId（发起人用户 ID）
- 类型：String
- 必填：是
- 来源：当前调用通话接口的用户 ID

### callerName（发起人姓名）
- 类型：String
- 必填：是
- 来源：后台用户表查到的姓名

### mediaType（通话类型）
- 类型：String
- 必填：是
- 可选值：`video` = 视频通话，`audio` = 语音通话

```json
{
  "page": "incoming_call",
  "callId": "call-abc-123",
  "callerId": "user001",
  "callerName": "张三",
  "mediaType": "video",
  "title": "视频通话邀请",
  "content": "张三邀请你进行视频通话，点击立即接听"
}
```

跳转目标：来电页面

---

## 场景 4：语音通话邀请（被叫）

与场景 3 相同，仅 `mediaType` 不同：

```json
{
  "page": "incoming_call",
  "callId": "call-abc-456",
  "callerId": "user001",
  "callerName": "张三",
  "mediaType": "audio",
  "title": "语音通话邀请",
  "content": "张三邀请你进行语音通话，点击立即接听"
}
```

跳转目标：来电页面

---

## page 值完整对照表

| page 值 | 跳转目标 |
|---------|----------|
| `event_notification` | 事件详情 |
| `weather_warning` | 气象预警详情 |
| `incoming_call` | 来电页面 |
