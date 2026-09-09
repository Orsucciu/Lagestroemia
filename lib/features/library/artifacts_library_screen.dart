// Artifacts library — browse all artifacts produced across all chats,
// with a search bar (issue #9).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../state/providers.dart';
import '../../data/models/models.dart';

final artifactsSearchProvider = StateProvider<String>((ref) => '');

class ArtifactsLibraryScreen extends ConsumerWidget {
  const ArtifactsLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final artifactsAsync = ref.watch(_allArtifactsProvider);
    final search = ref.watch(artifactsSearchProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.libraryTabsArtifacts)),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: l.commonSearch,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) =>
                  ref.read(artifactsSearchProvider.notifier).state = value,
            ),
          ),
          Expanded(
            child: artifactsAsync.when(
              data: (artifacts) {
                final filtered = search.isEmpty
                    ? artifacts
                    : artifacts.where((a) {
                        final q = search.toLowerCase();
                        final name = (a.name ?? '').toLowerCase();
                        final lang = (a.language ?? '').toLowerCase();
                        final body = a.body.toLowerCase();
                        return name.contains(q) ||
                            lang.contains(q) ||
                            body.contains(q);
                      }).toList(growable: false);
                if (filtered.isEmpty) {
                  return Center(child: Text(l.libraryArtifactsEmpty));
                }
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final a = filtered[i];
                    return ListTile(
                      leading: const Icon(Icons.code),
                      title: Text(a.name ?? a.kind.wire),
                      subtitle: Text(a.language ?? a.kind.wire),
                      onTap: () {
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
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('${l.commonError}: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

final _allArtifactsProvider = FutureProvider<List<Artifact>>((ref) async {
  final repo = await ref.watch(artifactRepositoryProvider.future);
  return repo.listAll();
});
