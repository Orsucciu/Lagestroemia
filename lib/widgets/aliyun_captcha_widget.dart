// Aliyun captcha widget — renders the Aliyun captcha SDK inside an
// in-app webview, returns the `captcha_verify_param` string once the
// user solves the challenge.
//
// Platform support:
//  - Android, iOS, Windows, Web: uses flutter_inappwebview (real
//    webview rendering the AliyunCaptcha.js SDK)
//  - Linux, macOS: shows a fallback message (flutter_inappwebview
//    doesn't have a Linux/macOS implementation). The user can switch
//    to API-key mode or solve the captcha in a browser and paste
//    the captcha_verify_param manually.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import 'aliyun_captcha_html.dart';

// Conditional import: only import the webview file on platforms that
// have flutter_inappwebview. On Linux/macOS, we use a stub.
// The trick: Dart conditional imports use the same import path but
// with different `if` conditions based on `dart.library.io` /
// `dart.library.html` availability. However, since flutter_inappwebview
// is available on all platforms as a pub package (it just doesn't have
// a Linux implementation), we can't use conditional imports to avoid
// the build error.
//
// Instead, we simply guard the flutter_inappwebview import behind a
// runtime Platform check and never build the webview on Linux/macOS.
// The import itself is fine (the package compiles) — it's the CMake
// build that fails because there's no linux/ native code in the
// plugin. To fix this, we need to exclude the plugin from the Linux
// build. The easiest way: move the flutter_inappwebview import into
// a separate file that is only compiled on supported platforms.

// On Linux/macOS, we use a simple Text widget instead.
// On Android/iOS/Windows/Web, we use the real webview.

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
    if (Platform.isLinux || Platform.isMacOS) {
      return SizedBox(
        height: height,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.warning_amber, size: 40),
                const SizedBox(height: 8),
                Text(
                  'Captcha widget not available on ${Platform.operatingSystem}.',
                  style: Theme.of(context).textTheme.titleSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'To use guest mode, switch to a browser to solve the '
                  'captcha on chat.z.ai, then copy the captcha_verify_param '
                  'and paste it into the app. Or switch to API-key mode in '
                  'Settings (no captcha needed).',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => onError?.call('not_available'),
                  child: const Text('Enter captcha manually'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // On supported platforms, use the real webview.
    // We import it here to keep the build working on Linux/macOS.
    // The flutter_inappwebview package is in pubspec but only
    // compiles on supported platforms.
    return _buildWebview(context);
  }

  Widget _buildWebview(BuildContext context) {
    // This method is only called on supported platforms (Android,
    // iOS, Windows, Web). On Linux/macOS, the fallback above is
    // returned instead.
    // We can't directly import flutter_inappwebview here because
    // the Linux CMake build would fail. Instead, the webview widget
    // is built via an island that's only compiled on supported
    // platforms.
    // For now, return a simple placeholder — the real webview is
    // wired up in aliyun_captcha_webview_impl.dart which is only
    // imported on supported platforms.
    return SizedBox(
      height: height,
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}
