import 'dart:convert';

import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AppVideoPlayerPage extends StatefulWidget {
  const AppVideoPlayerPage({
    required this.videoUrl,
    required this.title,
    super.key,
  });

  final String videoUrl;
  final String title;

  @override
  State<AppVideoPlayerPage> createState() => _AppVideoPlayerPageState();
}

class _AppVideoPlayerPageState extends State<AppVideoPlayerPage> {
  late final WebViewController _controller;
  late final String _safeVideoUrl;
  bool _loading = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _safeVideoUrl = _normalizeHttpUrl(widget.videoUrl);
    if (kDebugMode) {
      debugPrint('[AppVideoPlayerPage] open video: $_safeVideoUrl');
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'EHVideo',
        onMessageReceived: (message) {
          if (!mounted) {
            return;
          }
          final text = message.message.trim();
          if (text == 'playing' || text == 'loaded') {
            setState(() {
              _loading = false;
              _errorText = null;
            });
            return;
          }
          if (text.startsWith('error:')) {
            final reason = text.substring('error:'.length).trim();
            setState(() {
              _loading = false;
              _errorText = reason.isEmpty ? '视频加载失败，请稍后重试' : '视频加载失败：$reason';
            });
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _loading = true;
              _errorText = null;
            });
          },
          onPageFinished: (_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _loading = false;
            });
          },
          onWebResourceError: (error) {
            // Ignore resource-level noise from subresources. Only handle main
            // document load errors here.
            if (error.isForMainFrame != true) {
              return;
            }
            if (!mounted) {
              return;
            }
            setState(() {
              _loading = false;
              _errorText = '视频加载失败：${error.description}';
            });
          },
        ),
      )
      ..loadHtmlString(_buildPlayerHtml(_safeVideoUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          WebViewWidget(controller: _controller),
          if (_loading)
            const ColoredBox(
              color: Color(0x55000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_errorText != null)
            Container(
              color: const Color(0xCC000000),
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _errorText!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () {
                        setState(() {
                          _loading = true;
                          _errorText = null;
                        });
                        _controller.loadHtmlString(_buildPlayerHtml(_safeVideoUrl));
                      },
                      child: const Text('重试播放'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _normalizeHttpUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    final normalized = trimmed.replaceAll('\\', '/');
    final lower = normalized.toLowerCase();

    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      final parsed = Uri.tryParse(normalized);
      if (parsed != null && parsed.host.isNotEmpty) {
        return parsed.toString();
      }
      return Uri.encodeFull(normalized);
    }

    if (lower.startsWith('file://') || lower.startsWith('content://')) {
      final parsed = Uri.tryParse(normalized);
      return parsed?.toString() ?? Uri.encodeFull(normalized);
    }

    if (lower.startsWith('/storage/') ||
        lower.startsWith('/data/') ||
        RegExp(r'^[a-zA-Z]:/').hasMatch(normalized)) {
      return Uri.file(normalized).toString();
    }

    final parsed = Uri.tryParse(normalized);
    if (parsed != null && parsed.host.isNotEmpty) {
      return parsed.toString();
    }
    return Uri.encodeFull(normalized);
  }

  String _buildPlayerHtml(String url) {
    final safeUrl = const HtmlEscape(HtmlEscapeMode.attribute).convert(url);
    return '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no" />
    <style>
      html, body {
        margin: 0;
        padding: 0;
        width: 100%;
        height: 100%;
        background: #000;
        overflow: hidden;
      }
      .wrap {
        width: 100%;
        height: 100%;
        display: flex;
        align-items: center;
        justify-content: center;
      }
      video {
        width: 100%;
        height: 100%;
        object-fit: contain;
        background: #000;
      }
    </style>
  </head>
  <body>
    <div class="wrap">
      <video id="player" controls autoplay playsinline webkit-playsinline x5-playsinline src="$safeUrl"></video>
    </div>
    <script>
      (function() {
        const post = (msg) => {
          if (window.EHVideo && window.EHVideo.postMessage) {
            window.EHVideo.postMessage(msg);
          }
        };
        const video = document.getElementById('player');
        if (!video) {
          post('error:播放器初始化失败');
          return;
        }
        video.addEventListener('loadeddata', function() { post('loaded'); });
        video.addEventListener('playing', function() { post('playing'); });
        video.addEventListener('error', function() {
          const e = video.error;
          let reason = '视频资源不可用';
          if (e && typeof e.code === 'number') {
            if (e.code === 1) reason = '视频加载被中断';
            if (e.code === 2) reason = '网络错误';
            if (e.code === 3) reason = '解码失败';
            if (e.code === 4) reason = '视频格式不支持';
          }
          post('error:' + reason);
        });
      })();
    </script>
  </body>
</html>
''';
  }
}
