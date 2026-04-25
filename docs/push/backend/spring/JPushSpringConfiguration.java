package com.tianyanzhiyun.push.spring;

import com.tianyanzhiyun.push.JPushEventNotifier;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.net.URI;

@Configuration
@EnableConfigurationProperties(JPushProperties.class)
public class JPushSpringConfiguration {

    @Bean
    public JPushEventNotifier jPushEventNotifier(JPushProperties properties) {
        if (isBlank(properties.getAppKey()) || isBlank(properties.getMasterSecret())) {
            throw new IllegalStateException("jpush.app-key / jpush.master-secret 未配置");
        }
        return new JPushEventNotifier(
                properties.getAppKey(),
                properties.getMasterSecret(),
                properties.isApnsProduction(),
                properties.getTtlSeconds(),
                URI.create(properties.getApiUrl())
        );
    }

    private static boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }
}
