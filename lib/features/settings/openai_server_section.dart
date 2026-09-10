// Settings screen section for the OpenAI-compatible local server.
//
// Lets the user:
//   - Enable/disable the server
//   - Pick the port
//   - Set an optional server-side API key (callers must send
//     Authorization: Bearer <this key>)
//   - Toggle CORS
//   - See the current URL
//   - Copy a curl example
//
// The server is loopback-only (127.0.0.1) so it can only be reached
// from the same machine. On Web/iOS/macOS this section is hidden
// because we cannot bind a TCP listener.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/platform/platform_info.dart' show PlatformInfo;
import '../../data/api/openai_api_server.dart';
import '../../state/openai_server_state.dart';

class OpenAiServerSection extends ConsumerStatefulWidget {
  const OpenAiServerSection({super.key});
  @override
  ConsumerState<OpenAiServerSection> createState() =>
      _OpenAiServerSectionState();
}

class _OpenAiServerSectionState extends ConsumerState<OpenAiServerSection> {
  late OpenAiServerConfig _config;
  late TextEditingController _portCtrl;
  late TextEditingController _apiKeyCtrl;
  bool _initialised = false;

  @override
  void dispose() {
    _portCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  void _ensureInit() {
    if (_initialised) return;
    final notifier = ref.read(openAiServerProvider.notifier);
    _config = notifier.loadConfig();
    _portCtrl = TextEditingController(text: _config.port.toString());
    _apiKeyCtrl = TextEditingController(text: _config.serverApiKey);
    _initialised = true;
  }

  @override
  Widget build(BuildContext context) {
    // Hide on Web and on platforms without a TCP listener (iOS/macOS).
    // dart:io's Platform.* throws on Web — guard with kIsWeb first.
    if (kIsWeb ||
        (!PlatformInfo.isLinux && !PlatformInfo.isWindows && !PlatformInfo.isAndroid)) {
      return const SizedBox.shrink();
    }
    _ensureInit();
    final status = ref.watch(openAiServerProvider);
    final notifier = ref.read(openAiServerProvider.notifier);
    final scheme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'OpenAI-compatible server',
            style: scheme.textTheme.labelMedium?.copyWith(
              color: scheme.colorScheme.primary,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: const Text('Enable local API server'),
          subtitle: Text(
            status.running
                ? 'Running at ${status.url}'
                : 'Off — other OpenAI-speaking clients (curl, Cline, '
                    'Continue, etc.) cannot reach z.ai through '
                    'Lagestroemia.',
          ),
          trailing: Switch(
            value: status.running,
            onChanged: (v) async {
              if (v) {
                await notifier.setServerApiKey(_apiKeyCtrl.text);
                await notifier.setPort(int.tryParse(_portCtrl.text) ?? 8081);
                await notifier.start();
              } else {
                await notifier.stop();
              }
            },
          ),
        ),
        if (status.running && status.error == null) ...<Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SelectableText(
                    'URL: ${status.url}',
                    style: scheme.textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy URL',
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: status.url ?? ''),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SelectableText(
                    'Test: curl ${status.url}/v1/chat/completions '
                        '-H "Content-Type: application/json" '
                        '${_config.serverApiKey.isNotEmpty ? '-H "Authorization: Bearer <your-key>" ' : ''}'
                        '-d \'{"model":"glm-4.7","messages":[{"role":"user","content":"hi"}],"stream":false}\'',
                    style: scheme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy curl example',
                  onPressed: () => Clipboard.setData(
                    ClipboardData(
                      text: 'curl ${status.url}/v1/chat/completions '
                          '-H "Content-Type: application/json" '
                          '${_config.serverApiKey.isNotEmpty ? '-H "Authorization: Bearer <your-key>" ' : ''}'
                          "-d '{\"model\":\"glm-4.7\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"stream\":false}'",
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (status.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Error: ${status.error}',
              style: scheme.textTheme.bodySmall
                  ?.copyWith(color: scheme.colorScheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _portCtrl,
            decoration: const InputDecoration(
              labelText: 'Port',
              hintText: '8081',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) async {
              final port = int.tryParse(value);
              if (port != null && port > 0 && port < 65536) {
                await notifier.setPort(port);
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: TextField(
            controller: _apiKeyCtrl,
            decoration: const InputDecoration(
              labelText: 'Server API key (optional)',
              hintText: 'Leave empty for no auth (loopback-only)',
              border: OutlineInputBorder(),
              helperText: 'Callers must send Authorization: Bearer <this key>. '
                  'Empty = no auth required.',
            ),
            onChanged: (value) async {
              await notifier.setServerApiKey(value);
            },
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.public),
          title: const Text('Allow CORS'),
          subtitle: const Text(
              'Sends Access-Control-Allow-Origin: * so browser-based '
              'clients can call the server. Safe because the server is '
              'loopback-only.'),
          value: _config.allowCors,
          onChanged: (v) async {
            await notifier.setAllowCors(v);
            setState(() => _config = _config.copyWith(allowCors: v));
          },
        ),
        ListTile(
          leading: const Icon(Icons.link),
          title: const Text('OpenAI API reference'),
          subtitle: const Text('https://platform.openai.com/docs/api-reference'),
          onTap: () {},
        ),
        ListTile(
          leading: const Icon(Icons.book_outlined),
          title: const Text('z.ai docs'),
          subtitle: const Text(AppConfig.docsUrl),
          onTap: () {},
        ),
      ],
    );
  }
}
