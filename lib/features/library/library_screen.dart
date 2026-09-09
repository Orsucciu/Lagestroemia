// Library screen — entry to the Library views (artifacts + files).
// Each is a separate route so deep-linking works.

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
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: Text(l.libraryTabsFiles),
            subtitle: const Text('Browse all attachments across all chats'),
            onTap: () => context.go('/library/files'),
          ),
        ],
      ),
    );
  }
}
