// The captcha HTML template. Kept separate from the platform-specific
// widget files so tests can access it without importing flutter_inappwebview.

import 'package:flutter/foundation.dart' show visibleForTesting;

// The HTML page that hosts the Aliyun captcha SDK. We inject the SDK
// script, initialise it with the chat.z.ai scene id, and forward the
// verify result to Dart via `window.flutter_inappwebview.callHandler`.
// Kept at top-level so the test helper can access it.
const String kCaptchaHtml = r'''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
  html, body { margin: 0; padding: 0; height: 100%; background: transparent; }
  body { display: flex; align-items: center; justify-content: center; }
  #captcha-element { width: 100%; min-height: 320px; }
  #trigger-button { position: absolute; left: -9999px; }
</style>
</head>
<body>
  <div id="captcha-element"></div>
  <button id="trigger-button" type="button" tabindex="-1" aria-hidden="true"></button>
  <script>
    function loadScript(src, onload, onerror) {
      var s = document.createElement('script');
      s.src = src; s.async = true;
      s.onload = onload; s.onerror = onerror;
      document.head.appendChild(s);
    }
    loadScript('__SDK_URL__', function () {
      if (!window.initAliyunCaptcha) {
        window.flutter_inappwebview.callHandler('onCaptchaError', 'initAliyunCaptcha not found');
        return;
      }
      window.initAliyunCaptcha({
        SceneId: '__SCENE_ID__',
        mode: 'embed',
        element: '#captcha-element',
        button: '#trigger-button',
        prefix: '__PREFIX__',
        region: '__REGION__',
        language: 'en',
        timeout: 10000,
        delayBeforeSuccess: false,
        success: function (v) {
          window.flutter_inappwebview.callHandler('onCaptchaSuccess', v || '');
        },
        fail: function (e) {
          window.flutter_inappwebview.callHandler('onCaptchaError', String(e || 'fail'));
        },
        onError: function (e) {
          window.flutter_inappwebview.callHandler('onCaptchaError', String(e || 'error'));
        }
      });
    }, function () {
      window.flutter_inappwebview.callHandler('onCaptchaError', 'Failed to load captcha SDK');
    });
  </script>
</body>
</html>
''';

String getInjectedCaptchaHtml({
  required String sdkUrl,
  required String sceneId,
  required String prefix,
  required String region,
}) {
  return kCaptchaHtml
      .replaceAll('__SDK_URL__', sdkUrl)
      .replaceAll('__SCENE_ID__', sceneId)
      .replaceAll('__PREFIX__', prefix)
      .replaceAll('__REGION__', region);
}

@visibleForTesting
String buildCaptchaHtmlForTest({
  required String sdkUrl,
  required String sceneId,
  required String prefix,
  required String region,
}) {
  return getInjectedCaptchaHtml(
    sdkUrl: sdkUrl,
    sceneId: sceneId,
    prefix: prefix,
    region: region,
  );
}
