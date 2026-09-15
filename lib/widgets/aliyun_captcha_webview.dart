// Webview implementation of the Aliyun captcha widget.
//
// KEY INSIGHT: we must navigate the WebView to the REAL https://chat.z.ai/
// URL (not inject HTML via initialData). The Aliyun captcha SDK sends
// XHRs to captcha-open.aliyuncs.com, and Aliyun's server checks the
// Referer header — which the browser auto-attaches based on the page's
// origin. If we use initialData, the page loads as about:blank with no
// real origin, so the Referer is empty and Aliyun refuses to issue a
// valid certifyId.
//
// By navigating to https://chat.z.ai/ first, the browser attaches
// Referer: https://chat.z.ai/ to all XHRs. Aliyun accepts the request,
// issues a valid certifyId, and the resulting captcha_verify_param is
// accepted by chat.z.ai's backend.

import 'dart:developer' as developer;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import 'aliyun_captcha_platform.dart' show CaptchaWebviewImpl;

/// Real webview implementation. Navigates to chat.z.ai and injects
/// the captcha initialization code after the page loads.
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
  String _statusText = 'Loading chat.z.ai…';
  InAppWebViewController? _controller;
  bool _captchaInjected = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: <Widget>[
          InAppWebView(
            // Navigate to the REAL chat.z.ai URL — not initialData.
            // This ensures the browser attaches the correct Referer
            // header to all XHRs, which Aliyun's captcha server
            // requires to issue a valid certifyId.
            initialUrlRequest: URLRequest(
              url: WebUri('https://chat.z.ai/'),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: false,
              supportZoom: false,
              useShouldOverrideUrlLoading: false,
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
              _registerHandlers(controller);
            },
            onLoadStart: (controller, url) {
              developer.log('WebView load start: $url', name: 'captcha');
              if (mounted) {
                setState(() => _statusText = 'Loading chat.z.ai…');
              }
            },
            onLoadStop: (controller, url) async {
              developer.log('WebView load stop: $url', name: 'captcha');
              if (url != null && url.toString().contains('chat.z.ai')) {
                // Page loaded — inject the captcha initialization code.
                if (!_captchaInjected) {
                  _captchaInjected = true;
                  if (mounted) {
                    setState(() => _statusText = 'Initializing captcha…');
                  }
                  await _injectCaptcha(controller);
                }
              }
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
          // Status bar at the top — doesn't block the captcha below.
          Positioned(
            top: 4,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_loaded && !_error)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    if (!_loaded && !_error) const SizedBox(width: 8),
                    Text(
                      _error ? 'Error: $_errorMsg' : _statusText,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
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
                          _captchaInjected = false;
                          _controller?.reload();
                          if (mounted) {
                            setState(() {
                              _error = false;
                              _loaded = false;
                              _statusText = 'Reloading…';
                            });
                          }
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _registerHandlers(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'onCaptchaSuccess',
      callback: (args) {
        developer.log('Captcha success: args=$args', name: 'captcha');
        final param = args.isEmpty ? '' : (args.first?.toString() ?? '');
        if (param.isNotEmpty) {
          if (mounted) {
            setState(() {
              _loaded = true;
              _statusText = 'Verified!';
            });
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
    controller.addJavaScriptHandler(
      handlerName: 'onCaptchaStatus',
      callback: (args) {
        final status = args.isEmpty ? '' : (args.first?.toString() ?? '');
        developer.log('Captcha status: $status', name: 'captcha');
        if (mounted) {
          setState(() => _statusText = status);
        }
      },
    );
  }

  /// Injects the Aliyun captcha initialization code into the loaded
  /// chat.z.ai page. The captcha SDK is loaded from alicdn.com, then
  /// initialized with chat.z.ai's scene id.
  Future<void> _injectCaptcha(InAppWebViewController controller) async {
    // JavaScript code that:
    // 1. Creates a container for the captcha
    // 2. Loads the Aliyun captcha SDK (if not already loaded)
    // 3. Initializes the captcha with chat.z.ai's config
    // 4. Forwards success/error to Dart via flutter_inappwebview handlers
    final js = '''
(function() {
  try {
    // Create a container for the captcha.
    var container = document.createElement('div');
    container.id = 'lz-captcha-container';
    container.style.cssText = 'position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);z-index:999999;background:white;padding:20px;border-radius:8px;box-shadow:0 4px 20px rgba(0,0,0,0.3);';
    var title = document.createElement('div');
    title.textContent = 'Solve the captcha to continue';
    title.style.cssText = 'font-size:14px;font-weight:600;margin-bottom:12px;color:#333;';
    container.appendChild(title);
    var captchaEl = document.createElement('div');
    captchaEl.id = 'lz-captcha-element';
    captchaEl.style.cssText = 'min-height:200px;min-width:300px;';
    container.appendChild(captchaEl);
    var btn = document.createElement('button');
    btn.id = 'lz-captcha-button';
    btn.style.cssText = 'position:absolute;left:-9999px;';
    container.appendChild(btn);
    document.body.appendChild(container);

    // Hide chat.z.ai's own UI so only our captcha container is visible.
    var chatRoot = document.getElementById('root') || document.body;
    if (chatRoot && chatRoot !== document.body) {
      chatRoot.style.display = 'none';
    }

    function initCaptcha() {
      if (!window.initAliyunCaptcha) {
        window.flutter_inappwebview.callHandler('onCaptchaError', 'initAliyunCaptcha not found after SDK load');
        return;
      }
      window.flutter_inappwebview.callHandler('onCaptchaStatus', 'Rendering captcha…');
      window.initAliyunCaptcha({
        SceneId: '${AppConfig.aliyunCaptchaSceneIdChatZai}',
        mode: 'embed',
        element: '#lz-captcha-element',
        button: '#lz-captcha-button',
        prefix: '${AppConfig.aliyunCaptchaPrefix}',
        region: '${AppConfig.aliyunCaptchaRegion}',
        language: 'en',
        timeout: 60000,
        delayBeforeSuccess: false,
        success: function(v) {
          window.flutter_inappwebview.callHandler('onCaptchaStatus', 'Verified!');
          var param = (typeof v === 'string') ? v : JSON.stringify(v);
          if (!param || param === 'null' || param === 'undefined') {
            param = '';
          }
          window.flutter_inappwebview.callHandler('onCaptchaSuccess', param);
          // Remove the container.
          var c = document.getElementById('lz-captcha-container');
          if (c) c.remove();
        },
        fail: function(e) {
          window.flutter_inappwebview.callHandler('onCaptchaError', String(e || 'fail'));
        },
        onError: function(e) {
          window.flutter_inappwebview.callHandler('onCaptchaError', String(e || 'error'));
        }
      });
    }

    // Check if the SDK is already loaded (chat.z.ai loads it lazily).
    if (window.initAliyunCaptcha) {
      initCaptcha();
    } else {
      // Load the SDK ourselves.
      window.flutter_inappwebview.callHandler('onCaptchaStatus', 'Loading captcha SDK…');
      var s = document.createElement('script');
      s.src = '${AppConfig.aliyunCaptchaSdkUrl}';
      s.async = true;
      s.onload = function() {
        // Wait a tick for initAliyunCaptcha to be assigned.
        setTimeout(initCaptcha, 100);
      };
      s.onerror = function() {
        window.flutter_inappwebview.callHandler('onCaptchaError', 'Failed to load captcha SDK');
      };
      document.head.appendChild(s);
    }
  } catch (e) {
    window.flutter_inappwebview.callHandler('onCaptchaError', 'inject error: ' + String(e));
  }
})();
''';

    try {
      await controller.evaluateJavascript(source: js);
    } catch (e) {
      developer.log('Failed to inject captcha JS: $e', name: 'captcha');
      if (mounted) {
        setState(() {
          _error = true;
          _errorMsg = 'JS injection failed: $e';
        });
      }
      widget.onError?.call('JS injection failed: $e');
    }
  }
}
