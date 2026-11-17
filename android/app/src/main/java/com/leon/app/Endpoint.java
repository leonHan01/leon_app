package com.leon.app;

import java.net.URI;
import java.util.Locale;
import java.util.Arrays;

final class Endpoint {
    static String normalize(String value) {
        try {
            URI uri = new URI(value.trim());
            String host = uri.getHost();
            String scheme = uri.getScheme() == null ? "" : uri.getScheme().toLowerCase(Locale.ROOT);
            if (host == null || uri.getUserInfo() != null || uri.getRawQuery() != null || uri.getRawFragment() != null
                    || !(uri.getPath().isEmpty() || uri.getPath().equals("/"))
                    || !(scheme.equals("https") || scheme.equals("http") && Arrays.asList("localhost", "127.0.0.1", "10.0.2.2").contains(host))
                    || uri.getPort() > 65535 || uri.getPort() == 0) throw new Exception();
            return new URI(scheme, null, host.toLowerCase(Locale.ROOT), uri.getPort(), null, null, null).toString();
        } catch (Exception e) {
            throw new IllegalArgumentException("请输入 HTTPS 服务地址；本机开发可使用 http://10.0.2.2:8080。");
        }
    }
}
