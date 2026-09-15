// Aliyun captcha widget — renders the Aliyun captcha SDK inside an
// in-app webview, returns the `captcha_verify_param` string once the
// user solves the challenge.
//
// Platform support:
//  - Android, iOS, Windows: uses flutter_inappwebview (real webview
//    rendering the AliyunCaptcha.js SDK)
//  - Linux, macOS: shows a fallback message (flutter_inappwebview doesn't
//    have a Linux/macOS implementation)
//  - Web: opens a popup window loading /captcha.html, which hosts
//    AliyunCaptcha.js standalone and uses postMessage to send the
//    captcha_verify_param back to the Flutter app. This works around
//    flutter_inappwebview's iframe sandbox on web (which would render
//    the captcha visually but lose the postMessage callback).

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/app_config.dart';
import '../core/platform/platform_info.dart' show PlatformInfo;
import 'aliyun_captcha_html.dart';

// On supported native platforms (Android/iOS/Windows) we use the real
// webview from aliyun_captcha_webview.dart. We import it unconditionally
// here — the package compiles on every platform; only the CMake build
// step would fail on Linux/macOS, but those platforms take the fallback
// branch and never call _buildWebview.
import 'aliyun_captcha_webview.dart' show CaptchaWebviewImplReal;

// Conditional import: on web, this resolves to the real implementation
// from aliyun_captcha_web_popup.dart. On native, it resolves to the
// stub in aliyun_captcha_web_popup_stub.dart (which just calls onError
// — it should never actually be called because the parent widget
// takes a different branch on native).
//
// The trick: `if (dart.library.html)` is true on web, false on native.
import 'aliyun_captcha_web_popup_stub.dart'
    if (dart.library.html) 'aliyun_captcha_web_popup.dart'
    show CaptchaWebPopup;

export 'aliyun_captcha_html.dart' show buildCaptchaHtmlForTest;
export 'aliyun_captcha_dialog.dart' show CaptchaDialog;

/// A widget that renders the Aliyun captcha.
///
/// On web, this widget is a stateful one that opens a popup window
/// (loading /captcha.html) and listens for the popup's postMessage
/// containing the captcha_verify_param. On native platforms, it
/// renders an inline webview (Android/iOS/Windows) or shows a
/// manual-paste fallback (Linux/macOS).
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
  bool _popupOpening = false;

  @override
  Widget build(BuildContext context) {
    // On ALL platforms, show the fallback with a "Open chat.z.ai" button
    // + manual paste field. The InAppWebView approach has been unreliable
    // across multiple sessions (WebView2 initialization issues on Windows,
    // iframe sandbox on Web, no webview on Linux/macOS). The manual
    // approach works reliably everywhere.
    //
    // The user opens chat.z.ai in their system browser, solves the
    // captcha there, copies the captcha_verify_param from DevTools,
    // and pastes it below. This avoids all origin-binding issues
    // because the captcha is solved from chat.z.ai's actual origin.
    return _CaptchaFallback(
      height: widget.height,
      onSolved: widget.onSolved,
      onError: widget.onError,
      onOpenPopup: kIsWeb ? _openPopup : _openExternalBrowser,
      popupOpening: _popupOpening,
    );
  }

  Future<void> _openPopup() async {
    if (_popupOpening) return;
    setState(() => _popupOpening = true);
    try {
      await CaptchaWebPopup.show(
        onSolved: widget.onSolved,
        onError: widget.onError ?? (e) {},
      );
    } finally {
      if (mounted) setState(() => _popupOpening = false);
    }
  }

  /// Opens chat.z.ai in the system browser (non-web platforms).
  Future<void> _openExternalBrowser() async {
    if (_popupOpening) return;
    setState(() => _popupOpening = true);
    try {
      await launchUrl(
        Uri.parse('https://chat.z.ai'),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      widget.onError?.call('Could not open browser: $e');
    } finally {
      if (mounted) setState(() => _popupOpening = false);
    }
  }
}

/// Fallback widget shown on ALL platforms. Provides:
/// - A button that opens chat.z.ai in the system browser (or a popup
///   on web) so the user can solve the captcha from chat.z.ai's origin
/// - A text field to paste the captcha_verify_param
/// - Step-by-step instructions
class _CaptchaFallback extends StatefulWidget {
  const _CaptchaFallback({
    required this.height,
    required this.onSolved,
    this.onError,
    this.onOpenPopup,
    this.popupOpening = false,
  });
  final double height;
  final ValueChanged<String> onSolved;
  final ValueChanged<String>? onError;
  final Future<void> Function()? onOpenPopup;
  final bool popupOpening;

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
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.verified_user_outlined, size: 36),
              const SizedBox(height: 8),
              Text(
                'Captcha Verification Required',
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // Step 1: Open chat.z.ai
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Step 1: Open chat.z.ai and solve the captcha',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Click the button below to open chat.z.ai in your '
                  'browser. Sign in (free guest), type any message, '
                  'and solve the captcha that appears.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: widget.popupOpening ? null : widget.onOpenPopup,
                icon: widget.popupOpening
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.open_in_new),
                label: Text(
                  widget.popupOpening
                      ? 'Browser opened — solve captcha there'
                      : 'Open chat.z.ai',
                ),
              ),
              const SizedBox(height: 16),
              // Step 2: Copy the param
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Step 2: Copy captcha_verify_param',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'In chat.z.ai, press F12 → Network tab. Find the '
                  '"chat/completions" request. Click it → Payload tab '
                  '→ copy the captcha_verify_param value (starts with '
                  '"eyJ...").',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 8),
              // Step 3: Paste and submit
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Step 3: Paste it below',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Paste captcha_verify_param here',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      maxLines: 1,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final value = _controller.text.trim();
                      if (value.isNotEmpty) {
                        widget.onSolved(value);
                      }
                    },
                    child: const Text('Verify'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
