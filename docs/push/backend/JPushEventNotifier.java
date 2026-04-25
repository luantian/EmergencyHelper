package com.tianyanzhiyun.push;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * 极光推送事件通知封装类（Java 17+）。
 * <p>
 * 约定：
 * 1) 客户端登录后绑定别名 alias = "u_{userId}"；
 * 2) 服务端按 alias 推送；
 * 3) extras 中包含 route/eventId/page，App 点击通知后自动路由到页面。
 */
public final class JPushEventNotifier {
    private static final URI DEFAULT_PUSH_URI = URI.create("https://api.jpush.cn/v3/push");

    private final HttpClient httpClient;
    private final ObjectMapper objectMapper;
    private final String authorizationHeader;
    private final boolean apnsProduction;
    private final int ttlSeconds;
    private final URI pushUri;

    public JPushEventNotifier(
            String appKey,
            String masterSecret,
            boolean apnsProduction
    ) {
        this(appKey, masterSecret, apnsProduction, 24 * 60 * 60, DEFAULT_PUSH_URI);
    }

    public JPushEventNotifier(
            String appKey,
            String masterSecret,
            boolean apnsProduction,
            int ttlSeconds,
            URI pushUri
    ) {
        if (isBlank(appKey) || isBlank(masterSecret)) {
            throw new IllegalArgumentException("appKey/masterSecret 不能为空");
        }
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .build();
        this.objectMapper = new ObjectMapper();
        this.authorizationHeader = "Basic " + java.util.Base64.getEncoder()
                .encodeToString((appKey + ":" + masterSecret).getBytes(StandardCharsets.UTF_8));
        this.apnsProduction = apnsProduction;
        this.ttlSeconds = Math.max(ttlSeconds, 60);
        this.pushUri = Objects.requireNonNull(pushUri, "pushUri");
    }

    public PushResult pushToAlias(String alias, EventPush eventPush) throws IOException, InterruptedException {
        if (isBlank(alias)) {
            throw new IllegalArgumentException("alias 不能为空");
        }
        return pushToAliases(Set.of(alias), eventPush);
    }

    public PushResult pushToAliases(Collection<String> aliases, EventPush eventPush)
            throws IOException, InterruptedException {
        final Set<String> normalized = normalizeAudience(aliases);
        if (normalized.isEmpty()) {
            throw new IllegalArgumentException("aliases 不能为空");
        }
        final Map<String, Object> audience = new LinkedHashMap<>();
        audience.put("alias", normalized);
        return doPush(audience, eventPush);
    }

    public PushResult pushToRegistrationIds(Collection<String> registrationIds, EventPush eventPush)
            throws IOException, InterruptedException {
        final Set<String> normalized = normalizeAudience(registrationIds);
        if (normalized.isEmpty()) {
            throw new IllegalArgumentException("registrationIds 不能为空");
        }
        final Map<String, Object> audience = new LinkedHashMap<>();
        audience.put("registration_id", normalized);
        return doPush(audience, eventPush);
    }

    private PushResult doPush(Map<String, Object> audience, EventPush eventPush)
            throws IOException, InterruptedException {
        Objects.requireNonNull(eventPush, "eventPush");

        final Map<String, Object> extras = eventPush.buildExtras();
        final Map<String, Object> androidNotification = new LinkedHashMap<>();
        androidNotification.put("alert", eventPush.alert());
        androidNotification.put("title", eventPush.title());
        androidNotification.put("extras", extras);

        final Map<String, Object> iosNotification = new LinkedHashMap<>();
        iosNotification.put("alert", eventPush.alert());
        iosNotification.put("sound", "default");
        iosNotification.put("extras", extras);

        final Map<String, Object> notification = new LinkedHashMap<>();
        notification.put("android", androidNotification);
        notification.put("ios", iosNotification);

        final Map<String, Object> options = new LinkedHashMap<>();
        options.put("time_to_live", ttlSeconds);
        options.put("apns_production", apnsProduction);

        final Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("platform", "all");
        payload.put("audience", audience);
        payload.put("notification", notification);
        payload.put("options", options);

        final String requestBody = objectMapper.writeValueAsString(payload);
        final HttpRequest request = HttpRequest.newBuilder(pushUri)
                .timeout(Duration.ofSeconds(10))
                .header("Content-Type", "application/json")
                .header("Authorization", authorizationHeader)
                .POST(HttpRequest.BodyPublishers.ofString(requestBody, StandardCharsets.UTF_8))
                .build();

        final HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        final int statusCode = response.statusCode();
        final String body = response.body();

        if (statusCode >= 200 && statusCode < 300) {
            final Map<String, Object> responseMap = parseJsonMap(body);
            final String msgId = Objects.toString(responseMap.get("msg_id"), "");
            return PushResult.success(msgId, statusCode, body);
        }
        return PushResult.failure(statusCode, body);
    }

    private Map<String, Object> parseJsonMap(String body) {
        if (isBlank(body)) {
            return Map.of();
        }
        try {
            return objectMapper.readValue(body, new TypeReference<Map<String, Object>>() {
            });
        } catch (Exception ignored) {
            return Map.of();
        }
    }

    private static Set<String> normalizeAudience(Collection<String> values) {
        if (values == null || values.isEmpty()) {
            return Set.of();
        }
        return values.stream()
                .filter(v -> !isBlank(v))
                .map(String::trim)
                .collect(Collectors.toSet());
    }

    private static boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }

    public static final class EventPush {
        private final String title;
        private final String alert;
        private final String page;
        private final String route;
        private final String eventId;
        private final String type;
        private final Map<String, Object> extras;

        private EventPush(
                String title,
                String alert,
                String page,
                String route,
                String eventId,
                String type,
                Map<String, Object> extras
        ) {
            this.title = Objects.requireNonNull(title, "title");
            this.alert = Objects.requireNonNull(alert, "alert");
            this.page = Objects.requireNonNull(page, "page");
            this.route = Objects.requireNonNull(route, "route");
            this.eventId = eventId;
            this.type = Objects.requireNonNull(type, "type");
            this.extras = extras == null ? Map.of() : new LinkedHashMap<>(extras);
        }

        public static EventPush toEventDetail(String eventId, String title, String alert) {
            return new EventPush(
                    title,
                    alert,
                    "event_detail",
                    "/event-detail/" + encodePath(eventId),
                    eventId,
                    "event_update",
                    Map.of()
            );
        }

        public static EventPush toEventFeedback(String eventId, String title, String alert) {
            return new EventPush(
                    title,
                    alert,
                    "event_feedback",
                    "/event-feedback/" + encodePath(eventId),
                    eventId,
                    "event_feedback",
                    Map.of()
            );
        }

        public static EventPush toEventTimeline(String eventId, String title, String alert) {
            return new EventPush(
                    title,
                    alert,
                    "event_timeline",
                    "/event-timeline/" + encodePath(eventId),
                    eventId,
                    "event_timeline",
                    Map.of()
            );
        }

        public EventPush withExtras(Map<String, Object> extraData) {
            final Map<String, Object> merged = new LinkedHashMap<>(this.extras);
            if (extraData != null && !extraData.isEmpty()) {
                merged.putAll(extraData);
            }
            return new EventPush(title, alert, page, route, eventId, type, merged);
        }

        private Map<String, Object> buildExtras() {
            final Map<String, Object> merged = new LinkedHashMap<>();
            merged.put("page", page);
            merged.put("route", route);
            merged.put("type", type);
            if (!isBlank(eventId)) {
                merged.put("eventId", eventId);
            }
            if (!extras.isEmpty()) {
                merged.putAll(extras);
            }
            return merged;
        }

        public String title() {
            return title;
        }

        public String alert() {
            return alert;
        }
    }

    public record PushResult(boolean success, String msgId, int statusCode, String responseBody) {
        public static PushResult success(String msgId, int statusCode, String responseBody) {
            return new PushResult(true, msgId, statusCode, responseBody);
        }

        public static PushResult failure(int statusCode, String responseBody) {
            return new PushResult(false, "", statusCode, responseBody);
        }
    }

    private static String encodePath(String value) {
        if (isBlank(value)) {
            return "";
        }
        return URLEncoder.encode(value, StandardCharsets.UTF_8).replace("+", "%20");
    }
}
