// Domain models for the chat / library / prompts / settings areas.
//
// These are plain Dart classes (no codegen in the MVP) so they are easy to
// read and grep. Each one has a `fromMap` / `toMap` pair so it can be
// round-tripped through SQLite rows, and a `fromJson` / `toJson` pair so it
// can be sent over the wire to / from the z.ai API.

import 'package:flutter/foundation.dart';

import '../../core/result/result.dart';

part 'chat.dart';
part 'message.dart';
part 'attachment.dart';
part 'artifact.dart';
part 'system_prompt.dart';
part 'account.dart';
part 'api_error.dart';
