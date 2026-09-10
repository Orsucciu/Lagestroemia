// Webview implementation of the Aliyun captcha widget.
// This file imports flutter_inappwebview, which is only available on
// Android, iOS, Windows, and Web. On Linux/macOS, the parent file
// (aliyun_captcha_platform.dart) uses a fallback instead.

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import 'aliyun_captcha_html.dart';
import 'aliyun_captcha_platform.dart' show CaptchaWebviewImpl;

/// Real webview implementation. Overrides the stub in
/// [aliyun_captcha_platform.dart].
class CaptchaWebviewImplReal extends CaptchaWebviewImpl {
  const CaptchaWebviewImplReal({
    required super.onSolved,
    super.onError,
    required super.height,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return _CaptchaWebviewStateful(
      onSolved: onSolved,
      onError: onError,
      height: height,
    );
  }
}

class _CaptchaWebviewStateful extends StatefulWidget {
  const _CaptchaWebviewStateful({
    required this.onSolved,
    this.onError,
    required this.height,
  });
  final ValueChanged<String> onSolved;
  final ValueChanged<String>? onError;
  final double height;

  @override
  State<_CaptchaWebviewStateful> createState() => _CaptchaWebviewStatefulState();
}

class _CaptchaWebviewStatefulState extends State<_CaptchaWebviewStateful> {
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    final html = getInjectedCaptchaHtml(
      sdkUrl: AppConfig.aliyunCaptchaSdkUrl,
      sceneId: AppConfig.aliyunCaptchaSceneIdChatZai,
      prefix: AppConfig.aliyunCaptchaPrefix,
      region: AppConfig.aliyunCaptchaRegion,
    );
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: <Widget>[
          InAppWebView(
            initialData: InAppWebViewInitialData(
              data: html,
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
              controller.addJavaScriptHandler(
                handlerName: 'onCaptchaSuccess',
                callback: (args) {
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
