import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// Application name shown in title bars and splash.
  ///
  /// In en, this message translates to:
  /// **'Lagestroemia'**
  String get appName;

  /// Tab label for the chat list.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get navChats;

  /// Tab label for the local library (documents + artifacts).
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get navLibrary;

  /// Tab label for the system prompts library.
  ///
  /// In en, this message translates to:
  /// **'Prompts'**
  String get navPrompts;

  /// Tab label for settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get commonRename;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get commonLoading;

  /// No description provided for @commonEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get commonEmpty;

  /// No description provided for @commonError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong.'**
  String get commonError;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get commonCopy;

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @commonYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get commonYes;

  /// No description provided for @commonNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get commonNo;

  /// No description provided for @commonConfirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this?'**
  String get commonConfirmDelete;

  /// No description provided for @commonCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get commonCreated;

  /// No description provided for @commonUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get commonUpdated;

  /// No description provided for @commonTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get commonTitle;

  /// No description provided for @commonDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get commonDescription;

  /// Shown while the database is opening.
  ///
  /// In en, this message translates to:
  /// **'Starting up…'**
  String get splashLoading;

  /// Title on the first-run login screen.
  ///
  /// In en, this message translates to:
  /// **'Welcome to {appName}'**
  String authWelcomeTitle(String appName);

  /// Body on the first-run login screen.
  ///
  /// In en, this message translates to:
  /// **'Lagestroemia is a native client for z.ai. To use it, paste your z.ai API key below. You can create one at {url}.'**
  String authWelcomeBody(String url);

  /// No description provided for @authApiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get authApiKeyLabel;

  /// No description provided for @authApiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the key from the z.ai dashboard'**
  String get authApiKeyHint;

  /// Link/button to open the z.ai dashboard.
  ///
  /// In en, this message translates to:
  /// **'Create an API key'**
  String get authApiKeyCreate;

  /// No description provided for @authSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignIn;

  /// No description provided for @authSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get authSignOut;

  /// No description provided for @authInvalidKey.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a z.ai API key. Keys are usually 30+ characters and start with letters.'**
  String get authInvalidKey;

  /// No description provided for @authTesting.
  ///
  /// In en, this message translates to:
  /// **'Validating…'**
  String get authTesting;

  /// No description provided for @chatNew.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get chatNew;

  /// No description provided for @chatEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get chatEmptyTitle;

  /// No description provided for @chatComposerPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Send a message…'**
  String get chatComposerPlaceholder;

  /// No description provided for @chatStop.
  ///
  /// In en, this message translates to:
  /// **'Stop generating'**
  String get chatStop;

  /// No description provided for @chatSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSend;

  /// No description provided for @chatRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get chatRegenerate;

  /// No description provided for @chatEditMessage.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get chatEditMessage;

  /// No description provided for @chatDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get chatDeleteMessage;

  /// No description provided for @chatAttachFile.
  ///
  /// In en, this message translates to:
  /// **'Attach file'**
  String get chatAttachFile;

  /// No description provided for @chatModelPicker.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get chatModelPicker;

  /// No description provided for @chatSystemPrompt.
  ///
  /// In en, this message translates to:
  /// **'System prompt'**
  String get chatSystemPrompt;

  /// No description provided for @chatReasoning.
  ///
  /// In en, this message translates to:
  /// **'Reasoning'**
  String get chatReasoning;

  /// No description provided for @chatTokens.
  ///
  /// In en, this message translates to:
  /// **'{count} tokens'**
  String chatTokens(int count);

  /// No description provided for @chatErrorRateLimit.
  ///
  /// In en, this message translates to:
  /// **'Rate limit reached. Please wait and try again.'**
  String get chatErrorRateLimit;

  /// No description provided for @chatErrorAuth.
  ///
  /// In en, this message translates to:
  /// **'Your API key seems invalid. Please check Settings.'**
  String get chatErrorAuth;

  /// No description provided for @chatErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Could not reach z.ai. Check your connection.'**
  String get chatErrorNetwork;

  /// No description provided for @libraryTabsChats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get libraryTabsChats;

  /// No description provided for @libraryTabsArtifacts.
  ///
  /// In en, this message translates to:
  /// **'Artifacts'**
  String get libraryTabsArtifacts;

  /// No description provided for @libraryTabsFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get libraryTabsFiles;

  /// No description provided for @libraryChatsArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get libraryChatsArchived;

  /// No description provided for @libraryArtifactsEmpty.
  ///
  /// In en, this message translates to:
  /// **'When the assistant produces code, you\'ll find it here.'**
  String get libraryArtifactsEmpty;

  /// No description provided for @promptsNew.
  ///
  /// In en, this message translates to:
  /// **'New prompt'**
  String get promptsNew;

  /// No description provided for @promptsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get promptsEdit;

  /// No description provided for @promptsBuiltinBadge.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get promptsBuiltinBadge;

  /// No description provided for @promptsCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get promptsCategory;

  /// No description provided for @promptsBody.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get promptsBody;

  /// No description provided for @settingsAccountSection.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccountSection;

  /// No description provided for @settingsAccountKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get settingsAccountKey;

  /// No description provided for @settingsAccountKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Stored in your OS keychain'**
  String get settingsAccountKeyHint;

  /// No description provided for @settingsAccountRotate.
  ///
  /// In en, this message translates to:
  /// **'Rotate key'**
  String get settingsAccountRotate;

  /// No description provided for @settingsApiBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'API base URL'**
  String get settingsApiBaseUrl;

  /// No description provided for @settingsApiBaseUrlReset.
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get settingsApiBaseUrlReset;

  /// No description provided for @settingsAppearanceSection.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearanceSection;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsLanguageSection.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageSection;

  /// No description provided for @settingsLanguageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEn;

  /// No description provided for @settingsLanguageZh.
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get settingsLanguageZh;

  /// No description provided for @settingsAboutSection.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAboutSection;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get settingsVersion;

  /// No description provided for @settingsRepoLink.
  ///
  /// In en, this message translates to:
  /// **'Source repository'**
  String get settingsRepoLink;

  /// No description provided for @settingsDocsLink.
  ///
  /// In en, this message translates to:
  /// **'Documentation'**
  String get settingsDocsLink;

  /// No description provided for @settingsRateLimits.
  ///
  /// In en, this message translates to:
  /// **'View rate limits'**
  String get settingsRateLimits;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'zh': return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
