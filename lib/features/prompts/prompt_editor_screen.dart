// Prompt editor — create / edit a system prompt.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../state/providers.dart';
import '../../data/models/models.dart';

class PromptEditorScreen extends ConsumerStatefulWidget {
  const PromptEditorScreen({required this.promptId, super.key});
  final String? promptId;

  @override
  ConsumerState<PromptEditorScreen> createState() => _PromptEditorScreenState();
}

class _PromptEditorScreenState extends ConsumerState<PromptEditorScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final TextEditingController _category = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final l = AppLocalizations.of(context);
    if (widget.promptId == null) {
      setState(() => _loading = false);
      return;
    }
    final repo = await ref.read(systemPromptRepositoryProvider.future);
    final p = await repo.findById(widget.promptId!);
    if (p != null) {
      _name.text = p.name;
      _body.text = p.body;
      _category.text = p.category ?? '';
    }
    setState(() => _loading = false);
    // ignore: unused_local_variable
    final _ = l;
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final repo = await ref.read(systemPromptRepositoryProvider.future);
    final now = DateTime.now().toUtc();
    final p = SystemPrompt(
      id: widget.promptId ?? 'user-${DateTime.now().millisecondsSinceEpoch}',
      name: _name.text.trim().isEmpty ? 'Untitled' : _name.text.trim(),
      body: _body.text,
      category: _category.text.trim().isEmpty ? null : _category.text.trim(),
      builtin: false,
      createdAt: now,
      updatedAt: now,
    );
    await repo.upsert(p);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.commonSave)),
    );
    context.go('/prompts');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.promptId == null ? l.promptsNew : l.promptsEdit)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: l.commonTitle),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _category,
              decoration: InputDecoration(labelText: l.promptsCategory),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _body,
                maxLines: null,
                expands: true,
                decoration: InputDecoration(
                  labelText: l.promptsBody,
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _save,
              child: Text(l.commonSave),
            ),
          ],
        ),
      ),
    );
  }
}
