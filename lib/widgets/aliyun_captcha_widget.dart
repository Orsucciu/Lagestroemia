// Aliyun captcha widget — renders the Aliyun captcha SDK inside an
// in-app webview, returns the `captcha_verify_param` string once the
// user solves the challenge.
//
// This is the only piece of the app that uses a webview, and it renders
// *only* the captcha (not the chat.z.ai UI). The captcha SDK lives at
// https://o.alicdn.com/captcha-frontend/aliyunCaptcha/AliyunCaptcha.js
// and is the official Aliyun captcha SDK that chat.z.ai itself uses.
//
// The widget is intentionally minimal — just enough to host the captcha
// SDK and forward the verify result back to Dart via JS interop.
//
// On the Web (WASM) target, the same HTML is loaded into an iframe
// inside the page; the captcha SDK runs natively in the browser.

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/config/app_config.dart';

/// Result of an Aliyun captcha solve attempt.
class CaptchaResult {
  const CaptchaResult({this.verifyParam, this.error});
  final String? verifyParam;
  final String? error;

  bool get success => verifyParam != null && verifyParam!.isNotEmpty;
}

/// A widget that renders the Aliyun captcha and calls [onSolved] when
/// the user solves it (or [onError] if the SDK fails to load).
class AliyunCaptchaWidget extends StatefulWidget {
  const AliyunCaptchaWidget({
    required this.onSolved,
    this.onError,
    super.key,
    this.height = 350,
  });

  /// Called with the `captcha_verify_param` string once the user solves
  /// the captcha. After this fires, the parent can dismiss the widget
  /// and use the param in the chat completion request.
  final ValueChanged<String> onSolved;

  /// Called if the captcha SDK fails to load or the user cancels.
  final ValueChanged<String>? onError;

  /// Height of the captcha container in logical pixels.
  final double height;

  @override
  State<AliyunCaptchaWidget> createState() => _AliyunCaptchaWidgetState();
}

// The HTML page that hosts the Aliyun captcha SDK. We inject the SDK
// script, initialise it with the chat.z.ai scene id, and forward the
// verify result to Dart via `window.flutter_inappwebview.callHandler`.
// Kept at top-level so the test helper can access it.
const String _kCaptchaHtml = r'''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
  html, body { margin: 0; padding: 0; height: 100%; background: transparent; }
  body { display: flex; align-items: center; justify-content: center; }
  #captcha-element { width: 100%; min-height: 320px; }
  #trigger-button { position: absolute; left: -9999px; }
</style>
</head>
<body>
  <div id="captcha-element"></div>
  <button id="trigger-button" type="button" tabindex="-1" aria-hidden="true"></button>
  <script>
    // Load the Aliyun captcha SDK, then init with the chat.z.ai scene id.
    // The SDK calls onSuccess(e) with the captcha_verify_param string.
    function loadScript(src, onload, onerror) {
      var s = document.createElement('script');
      s.src = src;
      s.async = true;
      s.onload = onload;
      s.onerror = onerror;
      document.head.appendChild(s);
    }

    loadScript(
      '__SDK_URL__',
      function () {
        if (!window.initAliyunCaptcha) {
          window.flutter_inappwebview.callHandler('onCaptchaError', 'initAliyunCaptcha not found');
          return;
        }
        window.initAliyunCaptcha({
          SceneId: '__SCENE_ID__',
          mode: 'embed',
          element: '#captcha-element',
          button: '#trigger-button',
          prefix: '__PREFIX__',
          region: '__REGION__',
          language: 'en',
          timeout: 10000,
          delayBeforeSuccess: false,
          success: function (verifyParam) {
            window.flutter_inappwebview.callHandler('onCaptchaSuccess', verifyParam || '');
          },
          fail: function (err) {
            window.flutter_inappwebview.callHandler('onCaptchaError', String(err || 'captcha failed'));
          },
          onError: function (err) {
            window.flutter_inappwebview.callHandler('onCaptchaError', String(err || 'captcha error'));
          }
        });
      },
      function () {
        window.flutter_inappwebview.callHandler('onCaptchaError', 'Failed to load captcha SDK');
      }
    );
  </script>
</body>
</html>
''';

class _AliyunCaptchaWidgetState extends State<AliyunCaptchaWidget> {
  InAppWebViewController? _controller;
  bool _loaded = false;
  bool _disposed = false;

  String get _injectedHtml {
    return _kCaptchaHtml
        .replaceAll('__SDK_URL__', AppConfig.aliyunCaptchaSdkUrl)
        .replaceAll('__SCENE_ID__', AppConfig.aliyunCaptchaSceneIdChatZai)
        .replaceAll('__PREFIX__', AppConfig.aliyunCaptchaPrefix)
        .replaceAll('__REGION__', AppConfig.aliyunCaptchaRegion);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: <Widget>[
          InAppWebView(
            initialData: InAppWebViewInitialData(
              data: _injectedHtml,
              baseUrl: WebUri('https://chat.z.ai/'),
              mimeType: 'text/html',
              encoding: 'utf-8',
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: true,
              supportZoom: false,
              useShouldOverrideUrlLoading: false,
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
              controller.addJavaScriptHandler(
                handlerName: 'onCaptchaSuccess',
                callback: (args) {
                  if (_disposed) return;
                  final param =
                      args.isEmpty ? '' : (args.first?.toString() ?? '');
                  if (param.isNotEmpty) {
                    setState(() => _loaded = true);
                    widget.onSolved(param);
                  }
                },
              );
              controller.addJavaScriptHandler(
                handlerName: 'onCaptchaError',
                callback: (args) {
                  if (_disposed) return;
                  final err = args.isEmpty
                      ? 'unknown'
                      : (args.first?.toString() ?? 'unknown');
                  widget.onError?.call(err);
                },
              );
            },
          ),
          if (!_loaded)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

/// A dialog that wraps [AliyunCaptchaWidget] and returns the
/// `captcha_verify_param` string via `Navigator.pop(context, param)`.
///
/// Use:
/// ```dart
/// final param = await showDialog<String>(
///   context: context,
///   builder: (_) => const CaptchaDialog(),
/// );
/// if (param != null) {
///   ref.read(chatComposerProvider.notifier).setCaptchaAndRetry(param);
/// }
/// ```
class CaptchaDialog extends StatelessWidget {
  const CaptchaDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verification required'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'Free guest mode requires solving a captcha before each '
              'chat session. Solve it below to continue.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            AliyunCaptchaWidget(
              onSolved: (param) => Navigator.of(context).pop(param),
              onError: (err) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Captcha failed: $err')),
                );
              },
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

// Helper exposed for tests so they can build the same HTML without the
// webview. Not used at runtime.
@visibleForTesting
String buildCaptchaHtmlForTest({
  required String sdkUrl,
  required String sceneId,
  required String prefix,
  required String region,
}) {
  return _kCaptchaHtml
      .replaceAll('__SDK_URL__', sdkUrl)
      .replaceAll('__SCENE_ID__', sceneId)
      .replaceAll('__PREFIX__', prefix)
      .replaceAll('__REGION__', region);
}
