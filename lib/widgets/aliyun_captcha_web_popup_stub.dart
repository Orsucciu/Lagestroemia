// Stub implementation of the web popup bridge. Used on non-web platforms
// so that the conditional import in aliyun_captcha_widget.dart resolves
// to something at compile time.
//
// On web, the import resolves to aliyun_captcha_web_popup.dart which
// has the real implementation. On native, it resolves to this file.
// The parent widget (aliyun_captcha_widget.dart) only calls [show]
// when kIsWeb is true, so this stub's [show] is never actually
// invoked — it just needs to satisfy the symbol resolution.

import 'package:flutter/material.dart';

/// Bridge class with the same signature as `CaptchaWebPopup` in the
/// real web implementation. Used on non-web platforms as a no-op
/// stub so the conditional import resolves.
class CaptchaWebPopup {
  CaptchaWebPopup._();

  static Future<void> show({
    required ValueChanged<String> onSolved,
    required ValueChanged<String> onError,
    double popupWidth = 460,
    double popupHeight = 480,
  }) async {
    onError('CaptchaWebPopup.show() should not be called on non-web '
        'platforms — the parent widget should use the native webview '
        'or the manual-paste fallback instead.');
  }
}
