import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'Lagestroemia';

  @override
  String get navChats => '对话';

  @override
  String get navLibrary => '资料库';

  @override
  String get navPrompts => '系统提示';

  @override
  String get navSettings => '设置';

  @override
  String get commonCancel => '取消';

  @override
  String get commonSave => '保存';

  @override
  String get commonDelete => '删除';

  @override
  String get commonRename => '重命名';

  @override
  String get commonOk => '确定';

  @override
  String get commonRetry => '重试';

  @override
  String get commonLoading => '加载中…';

  @override
  String get commonEmpty => '暂无内容';

  @override
  String get commonError => '出错了';

  @override
  String get commonClose => '关闭';

  @override
  String get commonCopy => '复制';

  @override
  String get commonSearch => '搜索';

  @override
  String get commonYes => '是';

  @override
  String get commonNo => '否';

  @override
  String get commonConfirmDelete => '确定要删除吗？';

  @override
  String get commonCreated => '创建于';

  @override
  String get commonUpdated => '更新于';

  @override
  String get commonTitle => '标题';

  @override
  String get commonDescription => '描述';

  @override
  String get splashLoading => '正在启动…';

  @override
  String authWelcomeTitle(String appName) {
    return '欢迎使用 $appName';
  }

  @override
  String authWelcomeBody(String url) {
    return 'Lagestroemia 是 z.ai 的原生客户端。请粘贴您的 z.ai API 密钥以开始使用。密钥可以在 $url 创建。';
  }

  @override
  String get authApiKeyLabel => 'API 密钥';

  @override
  String get authApiKeyHint => '粘贴从 z.ai 控制台复制的密钥';

  @override
  String get authApiKeyCreate => '创建 API 密钥';

  @override
  String get authSignIn => '登录';

  @override
  String get authSignOut => '退出登录';

  @override
  String get authInvalidKey => '看起来不是有效的 z.ai API 密钥。密钥通常为 30 个字符以上且以字母开头。';

  @override
  String get authTesting => '验证中…';

  @override
  String get chatNew => '新对话';

  @override
  String get chatEmptyTitle => '新对话';

  @override
  String get chatComposerPlaceholder => '发送消息…';

  @override
  String get chatStop => '停止生成';

  @override
  String get chatSend => '发送';

  @override
  String get chatRegenerate => '重新生成';

  @override
  String get chatEditMessage => '编辑';

  @override
  String get chatDeleteMessage => '删除';

  @override
  String get chatAttachFile => '附件';

  @override
  String get chatModelPicker => '模型';

  @override
  String get chatSystemPrompt => '系统提示';

  @override
  String get chatReasoning => '推理过程';

  @override
  String chatTokens(int count) {
    return '$count tokens';
  }

  @override
  String get chatErrorRateLimit => '已达速率限制，请稍后再试。';

  @override
  String get chatErrorAuth => 'API 密钥无效，请检查设置。';

  @override
  String get chatErrorNetwork => '无法连接 z.ai，请检查网络。';

  @override
  String get libraryTabsChats => '对话';

  @override
  String get libraryTabsArtifacts => '产物';

  @override
  String get libraryTabsFiles => '文件';

  @override
  String get libraryChatsArchived => '归档';

  @override
  String get libraryArtifactsEmpty => '助手生成的代码会显示在此处。';

  @override
  String get promptsNew => '新建提示';

  @override
  String get promptsEdit => '编辑';

  @override
  String get promptsBuiltinBadge => '内置';

  @override
  String get promptsCategory => '分类';

  @override
  String get promptsBody => '正文';

  @override
  String get settingsAccountSection => '账户';

  @override
  String get settingsAccountKey => 'API 密钥';

  @override
  String get settingsAccountKeyHint => '保存在系统钥匙串中';

  @override
  String get settingsAccountRotate => '更换密钥';

  @override
  String get settingsApiBaseUrl => 'API 基础地址';

  @override
  String get settingsApiBaseUrlReset => '恢复默认';

  @override
  String get settingsAppearanceSection => '外观';

  @override
  String get settingsTheme => '主题';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsLanguageSection => '语言';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsLanguageZh => '中文';

  @override
  String get settingsAboutSection => '关于';

  @override
  String get settingsVersion => '版本';

  @override
  String get settingsRepoLink => '源代码仓库';

  @override
  String get settingsDocsLink => '文档';

  @override
  String get settingsRateLimits => '查看速率限制';
}
