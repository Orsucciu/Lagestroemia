import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Lagestroemia';

  @override
  String get navChats => 'Chats';

  @override
  String get navLibrary => 'Library';

  @override
  String get navPrompts => 'Prompts';

  @override
  String get navSettings => 'Settings';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonRename => 'Rename';

  @override
  String get commonOk => 'OK';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonEmpty => 'Nothing here yet.';

  @override
  String get commonError => 'Something went wrong.';

  @override
  String get commonClose => 'Close';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get commonConfirmDelete => 'Are you sure you want to delete this?';

  @override
  String get commonCreated => 'Created';

  @override
  String get commonUpdated => 'Updated';

  @override
  String get commonTitle => 'Title';

  @override
  String get commonDescription => 'Description';

  @override
  String get splashLoading => 'Starting up…';

  @override
  String authWelcomeTitle(String appName) {
    return 'Welcome to $appName';
  }

  @override
  String authWelcomeBody(String url) {
    return 'Lagestroemia is a native client for z.ai. To use it, paste your z.ai API key below. You can create one at $url.';
  }

  @override
  String get authApiKeyLabel => 'API key';

  @override
  String get authApiKeyHint => 'Paste the key from the z.ai dashboard';

  @override
  String get authApiKeyCreate => 'Create an API key';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authSignOut => 'Sign out';

  @override
  String get authInvalidKey => 'That doesn\'t look like a z.ai API key. Keys are usually 30+ characters and start with letters.';

  @override
  String get authTesting => 'Validating…';

  @override
  String get chatNew => 'New chat';

  @override
  String get chatEmptyTitle => 'New chat';

  @override
  String get chatComposerPlaceholder => 'Send a message…';

  @override
  String get chatStop => 'Stop generating';

  @override
  String get chatSend => 'Send';

  @override
  String get chatRegenerate => 'Regenerate';

  @override
  String get chatEditMessage => 'Edit';

  @override
  String get chatDeleteMessage => 'Delete';

  @override
  String get chatAttachFile => 'Attach file';

  @override
  String get chatModelPicker => 'Model';

  @override
  String get chatSystemPrompt => 'System prompt';

  @override
  String get chatReasoning => 'Reasoning';

  @override
  String chatTokens(int count) {
    return '$count tokens';
  }

  @override
  String get chatErrorRateLimit => 'Rate limit reached. Please wait and try again.';

  @override
  String get chatErrorAuth => 'Your API key seems invalid. Please check Settings.';

  @override
  String get chatErrorNetwork => 'Could not reach z.ai. Check your connection.';

  @override
  String get libraryTabsChats => 'Chats';

  @override
  String get libraryTabsArtifacts => 'Artifacts';

  @override
  String get libraryTabsFiles => 'Files';

  @override
  String get libraryChatsArchived => 'Archived';

  @override
  String get libraryArtifactsEmpty => 'When the assistant produces code, you\'ll find it here.';

  @override
  String get promptsNew => 'New prompt';

  @override
  String get promptsEdit => 'Edit';

  @override
  String get promptsBuiltinBadge => 'Built-in';

  @override
  String get promptsCategory => 'Category';

  @override
  String get promptsBody => 'Body';

  @override
  String get settingsAccountSection => 'Account';

  @override
  String get settingsAccountKey => 'API key';

  @override
  String get settingsAccountKeyHint => 'Stored in your OS keychain';

  @override
  String get settingsAccountRotate => 'Rotate key';

  @override
  String get settingsApiBaseUrl => 'API base URL';

  @override
  String get settingsApiBaseUrlReset => 'Reset to default';

  @override
  String get settingsAppearanceSection => 'Appearance';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsLanguageSection => 'Language';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsLanguageZh => '中文';

  @override
  String get settingsAboutSection => 'About';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsRepoLink => 'Source repository';

  @override
  String get settingsDocsLink => 'Documentation';

  @override
  String get settingsRateLimits => 'View rate limits';
}
