package com.tianyanzhiyun.push.spring;

import com.tianyanzhiyun.push.JPushEventNotifier;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.Collection;
import java.util.Map;
import java.util.stream.Collectors;

@Service
public class JPushEventPushService {
    private final JPushEventNotifier notifier;

    public JPushEventPushService(JPushEventNotifier notifier) {
        this.notifier = notifier;
    }

    /**
     * @param userId 平台用户主键ID（推荐取 /admin-api/system/auth/get-permission-info 的 data.user.id）
     */
    public JPushEventNotifier.PushResult pushEventDetailToUser(
            Object userId,
            String eventId,
            String title,
            String content
    ) {
        final String alias = aliasOf(userId);
        final JPushEventNotifier.EventPush push = JPushEventNotifier.EventPush
                .toEventDetail(eventId, title, content);
        return pushToAlias(alias, push);
    }

    /**
     * @param userId 平台用户主键ID（推荐取 /admin-api/system/auth/get-permission-info 的 data.user.id）
     */
    public JPushEventNotifier.PushResult pushEventFeedbackToUser(
            Object userId,
            String eventId,
            String title,
            String content
    ) {
        final String alias = aliasOf(userId);
        final JPushEventNotifier.EventPush push = JPushEventNotifier.EventPush
                .toEventFeedback(eventId, title, content);
        return pushToAlias(alias, push);
    }

    /**
     * @param userId 平台用户主键ID（推荐取 /admin-api/system/auth/get-permission-info 的 data.user.id）
     */
    public JPushEventNotifier.PushResult pushEventTimelineToUser(
            Object userId,
            String eventId,
            String title,
            String content
    ) {
        final String alias = aliasOf(userId);
        final JPushEventNotifier.EventPush push = JPushEventNotifier.EventPush
                .toEventTimeline(eventId, title, content);
        return pushToAlias(alias, push);
    }

    public JPushEventNotifier.PushResult pushEventToUsers(
            Collection<?> userIds,
            JPushEventNotifier.EventPush push
    ) {
        if (userIds == null || userIds.isEmpty()) {
            throw new IllegalArgumentException("userIds 不能为空");
        }
        final Collection<String> aliases = userIds.stream()
                .map(this::aliasOf)
                .collect(Collectors.toSet());
        try {
            return notifier.pushToAliases(aliases, push);
        } catch (IOException exception) {
            throw new UncheckedIOException("极光推送失败", exception);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("极光推送被中断", exception);
        }
    }

    public JPushEventNotifier.PushResult pushToAlias(
            String alias,
            JPushEventNotifier.EventPush push
    ) {
        try {
            return notifier.pushToAlias(alias, push);
        } catch (IOException exception) {
            throw new UncheckedIOException("极光推送失败", exception);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("极光推送被中断", exception);
        }
    }

    public JPushEventNotifier.PushResult pushToAliasWithExtras(
            String alias,
            String eventId,
            String title,
            String content,
            Map<String, Object> extras
    ) {
        final JPushEventNotifier.EventPush push = JPushEventNotifier.EventPush
                .toEventDetail(eventId, title, content)
                .withExtras(extras);
        return pushToAlias(alias, push);
    }

    /**
     * alias 规则：u_{平台用户主键ID}
     */
    public String aliasOf(Object userId) {
        if (userId == null) {
            throw new IllegalArgumentException("userId 不能为空");
        }
        final String normalized = userId.toString().trim();
        if (normalized.isEmpty()) {
            throw new IllegalArgumentException("userId 不能为空");
        }
        return "u_" + normalized;
    }
}
