// Prompts screen — list + manage system prompts.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../state/providers.dart';

class PromptsScreen extends ConsumerWidget {
  const PromptsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final promptsAsync = ref.watch(_allPromptsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.navPrompts),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l.promptsNew,
            onPressed: () => context.go('/prompts/new'),
          ),
        ],
      ),
      body: promptsAsync.when(
        data: (prompts) => prompts.isEmpty
            ? Center(child: Text(l.commonEmpty))
            : ListView.builder(
                itemCount: prompts.length,
                itemBuilder: (_, i) {
                  final p = prompts[i];
                  return ListTile(
                    leading: Icon(p.builtin
                        ? Icons.lock_outline
                        : Icons.edit_note),
                    title: Text(p.name),
                    subtitle: Text(p.body, maxLines: 2),
                    onTap: () => context.go('/prompts/${p.id}'),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('${l.commonError}: $e')),
      ),
    );
  }
}

final _allPromptsProvider = FutureProvider((ref) async {
  final repo = await ref.watch(systemPromptRepositoryProvider.future);
  return repo.listAll();
});
