// The captcha HTML template. Kept separate from the platform-specific
// widget files so tests can access it without importing flutter_inappwebview.

import 'package:flutter/foundation.dart' show visibleForTesting;

// The HTML page that hosts the Aliyun captcha SDK. We inject the SDK
// script, initialise it with the chat.z.ai scene id, and forward the
// verify result to Dart via `window.flutter_inappwebview.callHandler`.
//
// IMPORTANT: the `flutter_inappwebview` JS object is NOT available
// immediately when the page loads. We must wait for the
// `flutterInAppWebViewPlatformReady` event before calling
// `callHandler`. We use a helper that queues calls if the object
// isn't ready yet.
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
  #status { text-align: center; color: #888; font-family: sans-serif; font-size: 13px; padding: 8px; }
</style>
</head>
<body>
  <div id="status">Loading captcha…</div>
  <div id="captcha-element"></div>
  <button id="trigger-button" type="button" tabindex="-1" aria-hidden="true"></button>
  <script>
    // Queue of pending callHandler calls — flushed when
    // flutterInAppWebViewPlatformReady fires.
    var _ready = false;
    var _queue = [];
    function callHandler(name, arg) {
      if (_ready && window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        try {
          window.flutter_inappwebview.callHandler(name, arg);
        } catch (e) {
          console.error('callHandler failed:', e);
        }
      } else {
        _queue.push({ name: name, arg: arg });
      }
    }
    // Flush the queue when the platform is ready.
    window.addEventListener('flutterInAppWebViewPlatformReady', function () {
      _ready = true;
      console.log('flutterInAppWebViewPlatformReady — flushing ' + _queue.length + ' queued calls');
      while (_queue.length > 0) {
        var item = _queue.shift();
        callHandler(item.name, item.arg);
      }
    });

    function setStatus(text) {
      var el = document.getElementById('status');
      if (el) el.textContent = text;
    }

    function loadScript(src, onload, onerror) {
      var s = document.createElement('script');
      s.src = src; s.async = true;
      s.onload = onload; s.onerror = onerror;
      document.head.appendChild(s);
    }

    // Load the Aliyun captcha SDK.
    setStatus('Loading captcha SDK…');
    loadScript('__SDK_URL__', function () {
      if (!window.initAliyunCaptcha) {
        setStatus('Error: initAliyunCaptcha not found');
        callHandler('onCaptchaError', 'initAliyunCaptcha not found');
        return;
      }
      setStatus('Rendering captcha…');
      window.initAliyunCaptcha({
        SceneId: '__SCENE_ID__',
        mode: 'embed',
        element: '#captcha-element',
        button: '#trigger-button',
        prefix: '__PREFIX__',
        region: '__REGION__',
        language: 'en',
        timeout: 60000,
        delayBeforeSuccess: false,
        success: function (v) {
          setStatus('Verified!');
          var param = (typeof v === 'string') ? v : JSON.stringify(v);
          if (!param || param === 'null' || param === 'undefined') {
            param = '';
          }
          callHandler('onCaptchaSuccess', param);
        },
        fail: function (e) {
          setStatus('Captcha failed: ' + String(e || 'fail'));
          callHandler('onCaptchaError', String(e || 'fail'));
        },
        onError: function (e) {
          setStatus('Captcha error: ' + String(e || 'error'));
          callHandler('onCaptchaError', String(e || 'error'));
        }
      });
    }, function () {
      setStatus('Failed to load captcha SDK');
      callHandler('onCaptchaError', 'Failed to load captcha SDK');
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
