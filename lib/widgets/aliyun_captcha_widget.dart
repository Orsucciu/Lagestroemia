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
    // Web: open a popup window with /captcha.html.
    // Native Linux/macOS: no webview implementation available. Same fallback.
    //
    // We use kIsWeb + PlatformInfo.* instead of dart:io's Platform.*
    // because Platform.* throws on the Web target.
    if (kIsWeb || PlatformInfo.isLinux || PlatformInfo.isMacOS) {
      return _CaptchaFallback(
        height: widget.height,
        onSolved: widget.onSolved,
        onError: widget.onError,
        onOpenPopup: kIsWeb ? _openPopup : null,
        popupOpening: _popupOpening,
      );
    }

    // On supported native platforms (Android/iOS/Windows), use the
    // real webview which renders AliyunCaptcha.js and forwards the
    // captcha_verify_param string back via JS interop.
    return CaptchaWebviewImplReal(
      onSolved: widget.onSolved,
      onError: widget.onError,
      height: widget.height,
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
}

/// Fallback widget shown on platforms where the in-app webview is
/// unavailable (Linux, macOS) OR where the popup is the better approach
/// (Web). On web it shows a "Solve captcha" button that opens the popup.
/// On Linux/macOS it shows a manual-paste text field.
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
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.verified_user_outlined, size: 40),
              const SizedBox(height: 8),
              Text(
                kIsWeb
                    ? 'Solve the Aliyun captcha to continue.'
                    : 'Captcha widget not available on ${PlatformInfo.operatingSystem}.',
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              // On web, the primary action is to open the popup.
              // On Linux/macOS, the primary action is to switch to
              // API-key mode (and there's a manual paste field too).
              if (kIsWeb) ...<Widget>[
                Text(
                  'A new window will open with the captcha. Solve it '
                  'there and the result will be sent back automatically.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: widget.popupOpening
                      ? null
                      : widget.onOpenPopup,
                  icon: widget.popupOpening
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.open_in_new),
                  label: Text(
                    widget.popupOpening
                        ? 'Waiting for captcha…'
                        : 'Open captcha popup',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Or paste a captcha_verify_param manually:',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                _ManualPasteField(
                  controller: _controller,
                  onSolved: widget.onSolved,
                ),
              ] else ...<Widget>[
                Text(
                  'To use guest mode, switch to a browser to solve the '
                  'captcha on chat.z.ai, then copy the captcha_verify_param '
                  'and paste it into the app. Or switch to API-key mode in '
                  'Settings (no captcha needed).',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                _ManualPasteField(
                  controller: _controller,
                  onSolved: widget.onSolved,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Text field + button for manual paste of the captcha_verify_param.
class _ManualPasteField extends StatelessWidget {
  const _ManualPasteField({
    required this.controller,
    required this.onSolved,
  });
  final TextEditingController controller;
  final ValueChanged<String> onSolved;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'captcha_verify_param',
              hintText: 'Paste the captcha verify param here',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLines: 1,
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          onPressed: () {
            final value = controller.text.trim();
            if (value.isNotEmpty) {
              onSolved(value);
            }
          },
          child: const Text('Use'),
        ),
      ],
    );
  }
}
