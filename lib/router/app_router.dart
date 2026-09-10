// App router (go_router).
//
// The splash screen is NOT a route — it's shown directly by the root
// widget (LagestroemiaApp in main.dart) during startup. The router
// only activates after startup is complete. This eliminates the race
// condition where the router disposes the splash while restore() is
// still running.
//
// Layout:
//   /auth              → AuthScreen (first-run API key entry)
//   /                  → ChatShell (scaffold + nav rail + current screen)
//   /chat/:id          → ChatScreen opened on chat `id`
//   /chat/new         → ChatScreen on a fresh chat
//   /library          → LibraryScreen
//   /library/artifacts → ArtifactsLibraryScreen
//   /library/files    → FilesLibraryScreen
//   /prompts          → PromptsScreen
//   /prompts/new      → PromptEditorScreen
//   /prompts/:id      → PromptEditorScreen on existing prompt
//   /settings         → SettingsScreen

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_screen.dart';
import '../features/chat/chat_list_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/library/library_screen.dart';
import '../features/library/artifacts_library_screen.dart';
import '../features/library/files_library_screen.dart';
import '../features/prompts/prompts_screen.dart';
import '../features/prompts/prompt_editor_screen.dart';
import '../features/settings/settings_screen.dart';
import '../state/auth_state.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);
  return GoRouter(
    // Start at the root — if not signed in, the redirect sends to /auth.
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/auth',
        builder: (_, __) => const AuthScreen(),
      ),
      ShellRoute(
        builder: (_, __, child) => _AppScaffold(child: child),
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (_, __) => const ChatListScreen(),
          ),
          GoRoute(
            path: '/chat/new',
            builder: (_, __) => const ChatScreen(chatId: null),
          ),
          GoRoute(
            path: '/chat/:id',
            builder: (_, state) =>
                ChatScreen(chatId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/library',
            builder: (_, __) => const LibraryScreen(),
          ),
          GoRoute(
            path: '/library/artifacts',
            builder: (_, __) => const ArtifactsLibraryScreen(),
          ),
          GoRoute(
            path: '/library/files',
            builder: (_, __) => const FilesLibraryScreen(),
          ),
          GoRoute(
            path: '/prompts',
            builder: (_, __) => const PromptsScreen(),
          ),
          GoRoute(
            path: '/prompts/new',
            builder: (_, __) => const PromptEditorScreen(promptId: null),
          ),
          GoRoute(
            path: '/prompts/:id',
            builder: (_, state) =>
                PromptEditorScreen(promptId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
          ),
        ],
      ),
    ],
    redirect: (context, state) {
      final path = state.matchedLocation;
      if (!auth.signedIn && path != '/auth') return '/auth';
      if (auth.signedIn && path == '/auth') return '/';
      return null;
    },
  );
});

class _AppScaffold extends ConsumerWidget {
  const _AppScaffold({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _destinationIndex(location);
    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (i) => _goTo(context, i),
            labelType: NavigationRailLabelType.all,
            destinations: const <NavigationRailDestination>[
              NavigationRailDestination(
                icon: Icon(Icons.chat_outlined),
                selectedIcon: Icon(Icons.chat),
                label: Text('Chats'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder),
                label: Text('Library'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.edit_outlined),
                selectedIcon: Icon(Icons.edit),
                label: Text('Prompts'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }

  int _destinationIndex(String location) {
    if (location.startsWith('/library')) return 1;
    if (location.startsWith('/prompts')) return 2;
    if (location.startsWith('/settings')) return 3;
    return 0; // chats
  }

  void _goTo(BuildContext context, int i) {
    switch (i) {
      case 0:
        context.go('/');
      case 1:
        context.go('/library');
      case 2:
        context.go('/prompts');
      case 3:
        context.go('/settings');
    }
  }
}
