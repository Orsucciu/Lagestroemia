// Lightweight logging setup.
//
// We use `package:logging` (already pulled in by Riverpod) and route records
// to `print` on every platform. On native we could additionally write to a
// log file; on Web we could surface via `console.log`. The MVP just keeps
// it simple — every log line goes to the platform's stdout.

import 'package:logging/logging.dart';

/// One-time logger setup. Call from `main()` before any other code runs.
void initLogging(Level level) {
  // Wipe any previous hierarchical config (relevant for hot-reload).
  Logger.root.clearListeners();
  Logger.root.level = level;
  Logger.root.onRecord.listen((LogRecord rec) {
    // <LEVEL> logger.name: message
    // Example: INFO  lagestroemia.api: HTTP GET /chat/completions -> 200 OK
    final String levelLabel = rec.level.name.padLeft(5);
    // ignore: avoid_print
    print('[$levelLabel] ${rec.loggerName}: ${rec.message}'
        '${rec.error == null ? '' : ' — ${rec.error}'}'
        '${rec.stackTrace == null ? '' : '\n${rec.stackTrace}'}');
  });
}

/// Returns a logger for the calling library.
///
/// Convention: each file declares `final Logger _log = Logger('lagestroemia.<area>');`
/// at the top so log lines are easy to grep by area.
Logger logger(String name) => Logger(name);
