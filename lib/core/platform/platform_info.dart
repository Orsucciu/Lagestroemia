// Platform detection helpers.
//
// Most cross-platform code in the app should use `defaultTargetPlatform`
// (from `package:flutter/foundation.dart`) or `MediaQuery.platformBrightness`.
// This file wraps the few extra things we need:
//  - whether the build is for the Web (WASM or JS) target,
//  - whether the current OS is desktop (Linux/Windows/macOS) vs mobile
//    (Android/iOS),
//  - the platform-specific SQLite factory to use.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Helpers around the runtime platform.
///
/// Use these instead of `Platform.is*` directly so that the WASM build (which
/// compiles to `dart2js`-style "Web" but cannot use `dart:io`) still works.
class PlatformInfo {
  const PlatformInfo._();

  /// True if the app is compiled for the Web (HTML or WASM).
  ///
  /// Equivalent to `kIsWeb` — exposed here for symmetry with the other
  /// helpers and to make call-sites grep-able.
  static bool get isWeb => kIsWeb;

  /// True if the app is running as a desktop binary (Linux/Windows/macOS).
  ///
  /// Computed once from `defaultTargetPlatform`. On Web and mobile this is
  /// `false`.
  static bool get isDesktop {
    if (isWeb) return false;
    return defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  /// True if the app is running on Android or iOS.
  static bool get isMobile {
    if (isWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// True if the app is running on Linux desktop.
  static bool get isLinux =>
      !isWeb && defaultTargetPlatform == TargetPlatform.linux;

  /// True if the app is running on Windows desktop.
  static bool get isWindows =>
      !isWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// True if the app is running on macOS desktop.
  static bool get isMacOS =>
      !isWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// True if the app is running on Android.
  static bool get isAndroid =>
      !isWeb && defaultTargetPlatform == TargetPlatform.android;

  /// True if the app is running on iOS.
  static bool get isIOS =>
      !isWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Returns a short label suitable for diagnostics / about screens.
  static String get label {
    if (isWeb) return 'web';
    if (isAndroid) return 'android';
    if (isIOS) return 'ios';
    if (isLinux) return 'linux';
    if (isWindows) return 'windows';
    if (isMacOS) return 'macos';
    return 'unknown';
  }

  /// Returns `true` if we can safely use `dart:io`'s `Platform.is*` getters.
  ///
  /// On the Web target `dart:io` is unavailable at runtime (the import is
  /// tree-shaken by the compiler when no code path uses it, but calling the
  /// getters crashes).
  static bool get supportsDartIo => !kIsWeb;

  /// Returns the operating system name via `dart:io` when available.
  ///
  /// Falls back to the Flutter platform detection for Web.
  static String get operatingSystem {
    if (kIsWeb) return 'web';
    return Platform.operatingSystem;
  }

  /// Returns the operating system version via `dart:io` when available.
  static String get operatingSystemVersion {
    if (kIsWeb) return 'n/a';
    return Platform.operatingSystemVersion;
  }
}
