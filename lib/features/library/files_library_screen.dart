// Files library screen — flat list of all attachments across all chats,
// grouped by chat title.
//
// Issue #7 from the GitHub Issues list. The view:
//   - lists every row from the `attachments` table,
//   - groups them by chat (expansion tiles),
//   - shows image thumbnails when the file is on disk and is an image,
//   - offers a download button (uses FilePicker.saveFile) for any file
//     whose bytes are available in memory (read from `local_path` on
//     native).

import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../state/providers.dart';
import '../../data/repositories/attachment_repository.dart';

class FilesLibraryScreen extends ConsumerWidget {
  const FilesLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final attachmentsAsync = ref.watch(_allAttachmentsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.libraryTabsFiles)),
      body: attachmentsAsync.when(
        data: (attachments) {
          if (attachments.isEmpty) {
            return Center(child: Text(l.commonEmpty));
          }
          // Group by chatId
          final byChat = <String?, List<AttachmentWithChat>>{};
          for (final a in attachments) {
            byChat.putIfAbsent(a.chatId, () => <AttachmentWithChat>[]).add(a);
          }
          return ListView(
            children: <Widget>[
              for (final entry in byChat.entries)
                ExpansionTile(
                  initiallyExpanded: byChat.length == 1,
                  title: Text(entry.value.first.chatTitle ??
                      entry.value.first.chatId ??
                      'Unknown chat'),
                  subtitle: Text('${entry.value.length} file(s)'),
                  children: <Widget>[
                    for (final a in entry.value) _AttachmentTile(item: a),
                  ],
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('${l.commonError}: $e')),
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.item});
  final AttachmentWithChat item;

  @override
  Widget build(BuildContext context) {
    final isImage = item.attachment.mimeType.startsWith('image/');
    return ListTile(
      leading: isImage
          ? _Thumbnail(path: item.attachment.localPath)
          : const Icon(Icons.insert_drive_file),
      title: Text(item.attachment.filename),
      subtitle: Text(
        '${_formatBytes(item.attachment.byteSize)} · '
        '${item.attachment.mimeType} · '
        '${item.attachment.createdAt.toLocal()}',
      ),
      trailing: IconButton(
        icon: const Icon(Icons.download),
        onPressed: () => _download(context),
      ),
    );
  }

  Future<void> _download(BuildContext context) async {
    final localPath = item.attachment.localPath;
    if (localPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File is not on disk.')),
      );
      return;
    }
    try {
      final bytes = await File(localPath).readAsBytes();
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save as',
        fileName: item.attachment.filename,
        bytes: Uint8List.fromList(bytes),
      );
      if (savePath == null) return;
      // On desktop, saveFile returns a path and we need to write it
      // ourselves. On web, the bytes were already saved by FilePicker.
      if (savePath.isNotEmpty) {
        try {
          await File(savePath).writeAsBytes(bytes);
        } catch (_) {
          // May be bytes-only on web; ignore.
        }
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${item.attachment.filename}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  String _formatBytes(int bytes) {
    const units = <String>['B', 'KiB', 'MiB', 'GiB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path});
  final String? path;

  @override
  Widget build(BuildContext context) {
    if (path == null) return const SizedBox(width: 40, height: 40);
    final file = File(path!);
    bool exists = false;
    try {
      exists = file.existsSync();
    } catch (_) {}
    if (!exists) {
      return const Icon(Icons.broken_image, size: 40);
    }
    return Image.file(
      file,
      width: 40,
      height: 40,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          const Icon(Icons.broken_image, size: 40),
    );
  }
}

final _allAttachmentsProvider = FutureProvider((ref) async {
  final repo = await ref.watch(attachmentRepositoryProvider.future);
  return repo.listAll();
});
