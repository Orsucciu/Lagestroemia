// Aliyun captcha widget — renders the Aliyun captcha SDK inside an
// in-app webview, returns the `captcha_verify_param` string once the
// user solves the challenge.
//
// Platform support:
//  - Android, iOS, Windows: uses flutter_inappwebview (real webview
//    rendering the AliyunCaptcha.js SDK)
//  - Linux, macOS: shows a fallback message (flutter_inappwebview doesn't
//    have a Linux/macOS implementation)
//  - Web: shows a fallback message — flutter_inappwebview on web uses
//    an iframe, which works for static content but the Aliyun captcha
//    SDK uses postMessage to its parent window which doesn't route
//    back through Flutter's iframe sandbox. The captcha would render
//    but the `captcha_verify_param` callback would be lost. The user
//    can switch to API-key mode (no captcha needed) or solve the
//    captcha in a browser at chat.z.ai and paste the param manually.

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../core/platform/platform_info.dart' show PlatformInfo;
import 'aliyun_captcha_html.dart';

// On supported native platforms (Android/iOS/Windows) we use the real
// webview from aliyun_captcha_webview.dart. We import it unconditionally
// here — the package compiles on every platform; only the CMake build
// step would fail on Linux/macOS, but those platforms take the fallback
// branch and never call _buildWebview.
import 'aliyun_captcha_webview.dart' show CaptchaWebviewImplReal;

export 'aliyun_captcha_html.dart' show buildCaptchaHtmlForTest;
export 'aliyun_captcha_dialog.dart' show CaptchaDialog;

/// A widget that renders the Aliyun captcha.
class CaptchaWidget extends StatelessWidget {
  const CaptchaWidget({
    required this.onSolved,
    this.onError,
    super.key,
    this.height = 350,
  });

  final ValueChanged<String> onSolved;
  final ValueChanged<String>? onError;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Web: flutter_inappwebview uses an iframe on web, which breaks the
    // captcha SDK's postMessage callback. Show the fallback instead.
    // Native Linux/macOS: no webview implementation available. Same fallback.
    //
    // We use kIsWeb + PlatformInfo.* instead of dart:io's Platform.*
    // because Platform.* throws on the Web target.
    if (kIsWeb || PlatformInfo.isLinux || PlatformInfo.isMacOS) {
      return _CaptchaFallback(
        height: height,
        onSolved: onSolved,
        onError: onError,
      );
    }

    // On supported native platforms (Android/iOS/Windows), use the
    // real webview which renders AliyunCaptcha.js and forwards the
    // captcha_verify_param string back via JS interop.
    return CaptchaWebviewImplReal(
      onSolved: onSolved,
      onError: onError,
      height: height,
    );
  }
}

/// Fallback widget shown on platforms where the in-app webview is
/// unavailable (Linux, macOS, Web). Tells the user to either:
///   - switch to API-key mode (no captcha needed), OR
///   - solve the captcha in a browser at chat.z.ai and paste the
///     `captcha_verify_param` string into the manual entry field
///     below.
class _CaptchaFallback extends StatefulWidget {
  const _CaptchaFallback({
    required this.height,
    required this.onSolved,
    this.onError,
  });
  final double height;
  final ValueChanged<String> onSolved;
  final ValueChanged<String>? onError;

  @override
  State<_CaptchaFallback> createState() => _CaptchaFallbackState();
}

class _CaptchaFallbackState extends State<_CaptchaFallback> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.warning_amber, size: 40),
              const SizedBox(height: 8),
              Text(
                kIsWeb
                    ? 'In-app captcha not available on Web.'
                    : 'Captcha widget not available on ${PlatformInfo.operatingSystem}.',
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Either switch to API-key mode in Settings (no captcha '
                'needed), or open https://chat.z.ai in a browser, solve '
                'the captcha there, then copy the captcha_verify_param '
                'from your browser devtools (Network tab → /v2/chat/'
                'completions request body) and paste it below.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'captcha_verify_param',
                  hintText: 'Paste the captcha verify param here',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  final value = _controller.text.trim();
                  if (value.isNotEmpty) {
                    widget.onSolved(value);
                  }
                },
                child: const Text('Use this param'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
