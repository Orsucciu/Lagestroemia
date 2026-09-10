// Web-only Aliyun captcha widget that uses a popup window + postMessage
// instead of flutter_inappwebview's iframe approach.
//
// Why: flutter_inappwebview on Web uses an iframe to host its content.
// The Aliyun captcha SDK uses postMessage to its parent window, but
// Flutter's iframe sandbox doesn't route those messages back to Dart's
// JS interop handlers — so the captcha would render visually but the
// captcha_verify_param callback would be lost.
//
// The workaround: open a real browser popup window (window.open) that
// loads /captcha.html. That page hosts AliyunCaptcha.js standalone
// (no iframe), and on success it calls window.opener.postMessage with
// the captcha_verify_param. Our Flutter app listens via
// dart:html's window.onMessage stream.
//
// This file uses dart:html, which only compiles on the Web target.
// On native platforms, the parent (aliyun_captcha_widget.dart) takes
// a different branch (uses the in-app webview instead). The
// conditional import in aliyun_captcha_widget.dart resolves to
// aliyun_captcha_web_popup_stub.dart on native so this file is never
// compiled there.

// dart:html is web-only — this file is only imported when
// `dart.library.html` is available, which is true on web only.
import 'dart:async' show Completer, StreamSubscription, Timer;
import 'dart:html' as html show window, MessageEvent;
import 'dart:js_util' as js_util;

import 'package:flutter/material.dart';

import '../core/config/app_config.dart';

/// Opens a popup window showing the Aliyun captcha, and forwards the
/// captcha_verify_param string back to [onSolved] when the user solves
/// it. Calls [onError] if the captcha fails to load or is rejected.
///
/// Only call this from the Web target. On native platforms, use the
/// flutter_inappwebview-based CaptchaWebviewImplReal instead.
class CaptchaWebPopup {
  CaptchaWebPopup._();

  static const _sourceTag = 'lagestroemia-captcha';

  /// Opens the popup and returns when either:
  ///   - the user solves the captcha (onSolved is called with the
  ///     captcha_verify_param), OR
  ///   - the user closes the popup before solving (onError is called
  ///     with 'cancelled'), OR
  ///   - the captcha SDK fails (onError is called with the message).
  ///
  /// [popupWidth] and [popupHeight] are the popup window dimensions
  /// in CSS pixels. The popup is centered on the parent window.
  static Future<void> show({
    required ValueChanged<String> onSolved,
    required ValueChanged<String> onError,
    double popupWidth = 460,
    double popupHeight = 480,
  }) async {
    // Build the captcha.html URL with our config as query params so
    // the page knows which Aliyun scene to render.
    final captchaUrl = Uri.parse('captcha.html').replace(queryParameters: {
      'sdk': AppConfig.aliyunCaptchaSdkUrl,
      'scene': AppConfig.aliyunCaptchaSceneIdChatZai,
      'prefix': AppConfig.aliyunCaptchaPrefix,
      'region': AppConfig.aliyunCaptchaRegion,
    }).toString();

    // Center the popup on the parent window's screen.
    final screen = js_util.getProperty(html.window, 'screen');
    final screenW = js_util.getProperty(screen, 'width') as int;
    final screenH = js_util.getProperty(screen, 'height') as int;
    final left = ((screenW - popupWidth) / 2).round();
    final top = ((screenH - popupHeight) / 2).round();
    final features = 'width=${popupWidth.round()},'
        'height=${popupHeight.round()},'
        'left=$left,top=$top,'
        'menubar=no,toolbar=no,location=no,status=no,resizable=yes';

    // Open the popup. Returns null if the browser blocks popups.
    final popup = html.window.open(captchaUrl, 'lagestroemia_captcha', features);
    if (popup == null) {
      onError('Popup blocked by browser. Allow popups for this site '
          'and try again.');
      return;
    }

    // Listen for postMessage events from the popup. We filter on the
    // source tag so other extensions/scripts on the page don't confuse
    // us. We also poll the popup's `closed` property so we can detect
    // the user closing it without solving.
    final completer = Completer<void>();
    StreamSubscription<html.MessageEvent>? sub;
    sub = html.window.onMessage.listen((event) {
      final data = event.data;
      if (data == null) return;
      // The data is a JS object — use dart:js_util to read its fields.
      final source = js_util.getProperty(data, 'source');
      if (source != _sourceTag) return;
      final type = js_util.getProperty(data, 'type') as String?;
      final value = js_util.getProperty(data, 'data') as String?;
      if (type == 'success') {
        if (!completer.isCompleted) {
          if (value != null && value.isNotEmpty) {
            onSolved(value);
          } else {
            onError('Captcha returned an empty verify param');
          }
          completer.complete();
        }
      } else if (type == 'error') {
        if (!completer.isCompleted) {
          onError(value ?? 'Captcha failed');
          completer.complete();
        }
      }
    });

    // Poll for the popup being closed (the user closed it manually,
    // or the captcha page closed itself after success).
    Timer? poll;
    poll = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (popup.closed ?? false) {
        if (!completer.isCompleted) {
          onError('cancelled');
          completer.complete();
        }
      }
    });

    // When the completer finishes, clean up both listeners.
    await completer.future.then((_) {
      sub?.cancel();
      poll?.cancel();
      // Best-effort close in case the popup is still open (e.g.
      // we got a success message but the popup didn't close itself).
      try {
        if (!(popup.closed ?? false)) popup.close();
      } catch (_) {}
    });
  }
}
