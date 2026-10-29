import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n_ext.dart';
import '../player/player_controller.dart';
import '../settings/locale_controller.dart';
import '../src/rust/api/music.dart' as api;
import '../src/rust/api/types.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  static Route<void> route() => MaterialPageRoute(builder: (_) => const SettingsPage());

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// 设置里能选的默认音质（播放器能播的常用档位）。
const _qualities = [Quality.low, Quality.standard, Quality.high, Quality.lossless, Quality.hires, Quality.master];

/// 歌曲缓存上限的预设档位（MB），0 表示关闭。
const _limits = [0, 512, 1024, 2048, 4096, 8192];

const _languageNames = {'zh': '简体中文', 'en': 'English'};

String _sizeText(int bytes) {
  const mb = 1024 * 1024;
  if (bytes < mb) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / mb / 1024).toStringAsFixed(2)} GB';
}

String _limitText(AppLocalizations l, int mb) => switch (mb) {
      0 => l.audioCacheOff,
      _ when mb % 1024 == 0 => '${mb ~/ 1024} GB',
      _ => '$mb MB',
    };

class _SettingsPageState extends State<SettingsPage> {
  int _limitMb = api.getAudioCacheLimitMb();
  int? _audioSize;
  int? _apiSize;

  @override
  void initState() {
    super.initState();
    _loadSizes();
  }

  Future<void> _loadSizes() async {
    final audio = await api.getAudioCacheSize();
    final other = await api.getApiCacheSize();
    if (!mounted) return;
    setState(() {
      _audioSize = audio;
      _apiSize = other;
    });
  }

  Future<bool> _confirm(String text, String action, {bool danger = false}) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error) : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<T?> _choose<T>(String title, List<T> values, T current, String Function(T) label) {
    return showDialog<T>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          RadioGroup<T>(
            groupValue: current,
            onChanged: (v) => Navigator.of(context).pop(v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [for (final v in values) RadioListTile<T>(value: v, title: Text(label(v)))],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLanguage() async {
    final l = AppLocalizations.of(context);
    final controller = context.read<LocaleController>();
    // 空字符串表示跟随系统
    final codes = ['', for (final locale in AppLocalizations.supportedLocales) locale.languageCode];
    final v = await _choose<String>(
      l.language,
      codes,
      controller.locale?.languageCode ?? '',
      (c) => c.isEmpty ? l.languageSystem : _languageNames[c] ?? c,
    );
    if (v != null) controller.setLocale(v.isEmpty ? null : Locale(v));
  }

  Future<void> _pickQuality() async {
    final l = AppLocalizations.of(context);
    final player = context.read<PlayerController>();
    final q = await _choose<Quality>(l.defaultQuality, _qualities, player.defaultQuality, (q) => qualityLabel(l, q));
    if (q != null) player.setDefaultQuality(q);
  }

  Future<void> _pickLimit() async {
    final l = AppLocalizations.of(context);
    // -1 表示自定义
    final v = await _choose<int>(
      l.audioCacheLimit,
      [..._limits, -1],
      _limits.contains(_limitMb) ? _limitMb : -1,
      (mb) => mb < 0 ? '${l.audioCacheCustom}${_limits.contains(_limitMb) ? '' : ' (${_limitText(l, _limitMb)})'}' : _limitText(l, mb),
    );
    if (v == null) return;
    final mb = v < 0 ? await _customLimit() : v;
    if (mb == null) return;
    api.setAudioCacheLimitMb(mb: mb);
    setState(() => _limitMb = api.getAudioCacheLimitMb());
    await _loadSizes();
  }

  Future<int?> _customLimit() {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController(text: _limitMb > 0 ? '$_limitMb' : '');
    return showDialog<int>(
      context: context,
      builder: (context) {
        void submit() => Navigator.of(context).pop(int.tryParse(controller.text));
        return AlertDialog(
          title: Text(l.audioCacheCustomTitle),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(suffixText: l.audioCacheCustomUnit),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancel)),
            FilledButton(onPressed: submit, child: Text(l.ok)),
          ],
        );
      },
    ).whenComplete(controller.dispose);
  }

  Future<void> _clearAudio() async {
    final l = AppLocalizations.of(context);
    if (!await _confirm(l.clearAudioCacheConfirm, l.clear)) return;
    await api.clearAudioCache();
    await _loadSizes();
    if (mounted) showToast(context, l.cacheCleared);
  }

  Future<void> _clearApi() async {
    final l = AppLocalizations.of(context);
    if (!await _confirm(l.clearApiCacheConfirm, l.clear)) return;
    await api.clearCache();
    await _loadSizes();
    if (mounted) showToast(context, l.cacheCleared);
  }

  Future<void> _logout() async {
    final l = AppLocalizations.of(context);
    if (!await _confirm(l.logoutConfirm, l.logout, danger: true)) return;
    if (!mounted) return;
    await context.read<AuthController>().logout();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = context.watch<LocaleController>().locale;
    final defaultQuality = context.select<PlayerController, Quality>((p) => p.defaultQuality);
    final loggedIn = context.select<AuthController, bool>((a) => a.loggedIn);
    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        );
    Widget sizeTrailing(int? size, VoidCallback onClear) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(size == null ? '…' : _sizeText(size)),
            const SizedBox(width: 8),
            TextButton(onPressed: size == null || size == 0 ? null : onClear, child: Text(l.clear)),
          ],
        );
    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: ListView(
        children: [
          header(l.settingsGeneral),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(l.language),
            subtitle: Text(locale == null ? l.languageSystem : _languageNames[locale.languageCode] ?? locale.languageCode),
            onTap: _pickLanguage,
          ),
          ListTile(
            leading: const Icon(Icons.high_quality_outlined),
            title: Text(l.defaultQuality),
            subtitle: Text('${qualityLabel(l, defaultQuality)} · ${l.defaultQualityHint}'),
            onTap: _pickQuality,
          ),
          header(l.settingsCache),
          ListTile(
            leading: const Icon(Icons.sd_storage_outlined),
            title: Text(l.audioCacheLimit),
            subtitle: Text('${_limitText(l, _limitMb)} · ${l.audioCacheLimitHint}'),
            onTap: _pickLimit,
          ),
          ListTile(
            leading: const Icon(Icons.library_music_outlined),
            title: Text(l.audioCacheSize),
            trailing: sizeTrailing(_audioSize, _clearAudio),
          ),
          ListTile(
            leading: const Icon(Icons.dataset_outlined),
            title: Text(l.apiCacheSize),
            subtitle: Text(l.apiCacheSizeHint),
            trailing: sizeTrailing(_apiSize, _clearApi),
          ),
          if (loggedIn) ...[
            header(l.settingsAccount),
            ListTile(
              leading: Icon(Icons.logout, color: theme.colorScheme.error),
              title: Text(l.logout, style: TextStyle(color: theme.colorScheme.error)),
              onTap: _logout,
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
