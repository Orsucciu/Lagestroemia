// Webview implementation of the Aliyun captcha widget.
// This file imports flutter_inappwebview, which is only available on
// Android, iOS, Windows, and Web. On Linux/macOS, the parent file
// (aliyun_captcha_platform.dart) uses a fallback instead.

import 'dart:developer' as developer;

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
  bool _error = false;
  String _errorMsg = '';
  InAppWebViewController? _controller;

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
              // Allow mixed content (the captcha SDK loads from
              // alicdn.com over HTTPS, but some sub-resources may
              // be loaded over HTTP).
              allowFileAccessFromFileURLs: true,
              allowUniversalAccessFromFileURLs: true,
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
              controller.addJavaScriptHandler(
                handlerName: 'onCaptchaSuccess',
                callback: (args) {
                  developer.log('Captcha success: args=$args',
                      name: 'captcha');
                  final param =
                      args.isEmpty ? '' : (args.first?.toString() ?? '');
                  if (param.isNotEmpty) {
                    if (mounted) {
                      setState(() => _loaded = true);
                    }
                    widget.onSolved(param);
                  } else {
                    developer.log('Captcha success but param is empty',
                        name: 'captcha');
                    widget.onError?.call('Captcha returned empty param');
                  }
                },
              );
              controller.addJavaScriptHandler(
                handlerName: 'onCaptchaError',
                callback: (args) {
                  final err = args.isEmpty
                      ? 'unknown'
                      : (args.first?.toString() ?? 'unknown');
                  developer.log('Captcha error: $err', name: 'captcha');
                  if (mounted) {
                    setState(() {
                      _error = true;
                      _errorMsg = err;
                    });
                  }
                  widget.onError?.call(err);
                },
              );
            },
            onLoadStart: (controller, url) {
              developer.log('WebView load start: $url', name: 'captcha');
            },
            onLoadStop: (controller, url) {
              developer.log('WebView load stop: $url', name: 'captcha');
              // The page has loaded. The flutterInAppWebViewPlatformReady
              // event should fire soon, after which the JS handlers
              // will work.
            },
            onReceivedError: (controller, request, error) {
              developer.log('WebView error: ${error.description}',
                  name: 'captcha');
              if (mounted) {
                setState(() {
                  _error = true;
                  _errorMsg = error.description;
                });
              }
              widget.onError?.call(error.description);
            },
            onConsoleMessage: (controller, consoleMessage) {
              developer.log('WebView console: ${consoleMessage.message}',
                  name: 'captcha');
            },
          ),
          if (_error)
            Container(
              color: Colors.red.withValues(alpha: 0.1),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(height: 8),
                      Text(
                        'Captcha failed to load: $_errorMsg',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          _controller?.reload();
                          if (mounted) {
                            setState(() {
                              _error = false;
                              _loaded = false;
                            });
                          }
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (!_loaded)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
