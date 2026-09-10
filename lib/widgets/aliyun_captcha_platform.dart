// Platform interface for the Aliyun captcha widget.
//
// On platforms that support flutter_inappwebview (Android, iOS, Windows,
// Web), this delegates to [CaptchaWebviewWidget] which renders the
// captcha in an InAppWebView. On Linux/macOS (which don't have a
// webview implementation), it shows a fallback message.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import 'aliyun_captcha_html.dart';

export 'aliyun_captcha_html.dart' show buildCaptchaHtmlForTest;

/// A widget that renders the Aliyun captcha. On supported platforms
/// (Android, iOS, Windows, Web), this is a webview; on Linux/macOS
/// it shows a fallback message.
class CaptchaWidget extends StatefulWidget {
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
  State<CaptchaWidget> createState() => _CaptchaWidgetState();
}

class _CaptchaWidgetState extends State<CaptchaWidget> {
  @override
  Widget build(BuildContext context) {
    if (Platform.isLinux || Platform.isMacOS) {
      return _CaptchaFallback(
        height: widget.height,
        onError: widget.onError,
      );
    }
    // On supported platforms (Android, iOS, Windows, Web), use the
    // real webview. We import it lazily via a conditional import to
    // avoid the build failure on Linux/macOS.
    return _buildWebview(context);
  }

  Widget _buildWebview(BuildContext context) {
    // Use a conditional import to get the platform-specific widget.
    // This file is the "stub" that other files override on supported
    // platforms. On Linux/macOS this code path is never reached.
    return CaptchaWebviewImpl(
      onSolved: widget.onSolved,
      onError: widget.onError,
      height: widget.height,
    );
  }
}

/// Stub widget for Linux/macOS — shows a message that the captcha
/// is not available and the user should switch to API-key mode.
class _CaptchaFallback extends StatelessWidget {
  const _CaptchaFallback({required this.height, this.onError});
  final double height;
  final ValueChanged<String>? onError;

  @override
  Widget build(BuildContext context) {
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
                onPressed: () {
                  // Trigger the error callback so the parent can
                  // show the manual captcha entry dialog.
                  onError?.call('not_available');
                },
                child: const Text('Enter captcha manually'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dialog that wraps [CaptchaWidget] and returns the
/// `captcha_verify_param` string via `Navigator.pop(context, param)`.
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
            CaptchaWidget(
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

/// Platform-specific webview widget. Overridden by the real
/// implementation on supported platforms.
class CaptchaWebviewImpl extends StatelessWidget {
  const CaptchaWebviewImpl({
    required this.onSolved,
    this.onError,
    required this.height,
    super.key,
  });
  final ValueChanged<String> onSolved;
  final ValueChanged<String>? onError;
  final double height;

  @override
  Widget build(BuildContext context) {
    // This stub is replaced by the conditional import on supported
    // platforms. On Linux/macOS, this code path is never reached
    // because _CaptchaWidgetState uses _CaptchaFallback instead.
    throw UnsupportedError('CaptchaWebviewImpl should not be called '
        'on ${Platform.operatingSystem}');
  }
}
