part of 'models.dart';

/// A file attached to a [ChatMessage]. May be an image, a PDF, or any
/// arbitrary binary uploaded to z.ai via the /paas/v4/files endpoint.
@immutable
class Attachment {
  const Attachment({
    required this.id,
    required this.messageId,
    required this.filename,
    required this.mimeType,
    required this.byteSize,
    this.localPath,
    this.remoteId,
    required this.createdAt,
  });

  final String id;
  final String messageId;
  final String filename;
  final String mimeType;
  final int byteSize;

  /// Absolute path on the user's filesystem when the file has been picked
  /// locally. `null` if the attachment was uploaded first and only its z.ai
  /// id is known.
  final String? localPath;

  /// z.ai file id returned by `POST /paas/v4/files`. `null` for inline
  /// attachments that have not been uploaded yet.
  final String? remoteId;

  final DateTime createdAt;

  factory Attachment.fromMap(Map<String, Object?> row) {
    return Attachment(
      id: row['id']! as String,
      messageId: row['message_id']! as String,
      filename: row['filename']! as String,
      mimeType: row['mimeType']! as String,
      byteSize: row['byte_size']! as int,
      localPath: row['local_path'] as String?,
      remoteId: row['remote_id'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'message_id': messageId,
        'filename': filename,
        'mime_type': mimeType,
        'byte_size': byteSize,
        'local_path': localPath,
        'remote_id': remoteId,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  /// True if the attachment is small enough to be inlined into the chat
  /// completions request body (image_url or file_data). Larger files must
  /// be uploaded via /paas/v4/files and referenced by `remote_id`.
  bool get isInlineEligible => byteSize <= 5 * 1024 * 1024;
}
