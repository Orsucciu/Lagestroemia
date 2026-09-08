// Artifacts library — browse all artifacts produced across all chats.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../state/providers.dart';

class ArtifactsLibraryScreen extends ConsumerWidget {
  const ArtifactsLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final artifactsAsync = ref.watch(_allArtifactsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.libraryTabsArtifacts)),
      body: artifactsAsync.when(
        data: (artifacts) => artifacts.isEmpty
            ? Center(child: Text(l.libraryArtifactsEmpty))
            : ListView.builder(
                itemCount: artifacts.length,
                itemBuilder: (_, i) {
                  final a = artifacts[i];
                  return ListTile(
                    leading: const Icon(Icons.code),
                    title: Text(a.name ?? a.kind.wire),
                    subtitle: Text(a.language ?? a.kind.wire),
                    onTap: () {
                      // MVP: open in a simple modal dialog with the body.
                      showDialog<void>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Text(a.name ?? a.kind.wire),
                          content: SizedBox(
                            width: 800,
                            child: SingleChildScrollView(
                              child: SelectableText(a.body),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(l.commonClose),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('${l.commonError}: $e')),
      ),
    );
  }
}

final _allArtifactsProvider = FutureProvider((ref) async {
  final repo = await ref.watch(artifactRepositoryProvider.future);
  return repo.listAll();
});
