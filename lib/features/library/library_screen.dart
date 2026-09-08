// Library screen — local artifacts (code/markdown/html/svg/json) the
// assistant produced during chats. Stub for the MVP; the artifacts list
// itself lives at /library/artifacts.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.navLibrary)),
      body: ListView(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(l.libraryTabsArtifacts),
            subtitle: Text(l.libraryArtifactsEmpty),
            onTap: () => context.go('/library/artifacts'),
          ),
          // Files view not implemented in MVP — leave the tile to keep the
          // section discoverable.
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: Text(l.libraryTabsFiles),
            enabled: false,
            onTap: null,
          ),
        ],
      ),
    );
  }
}
