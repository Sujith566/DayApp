import 'package:flutter/material.dart';

import 'more_store.dart';
import 'more_theme.dart';
import '../security/app_lock.dart';
import '../backup/backup_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false, _loading = true;
  String? _error;
  Map<String, int> _counts = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final db = await MoreStore.instance.db;
      final counts = <String, int>{};
      for (final name in ['notes', 'documents', 'vault_entries']) {
        final result = await db.rawQuery('SELECT count(*) AS n FROM $name');
        counts[name] = result.first['n'] as int;
      }
      if (mounted)
        setState(() {
          _counts = counts;
          _loading = false;
          _error = null;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = 'Could not load storage information.';
        });
    }
  }

  Future<void> _theme(ThemeMode mode) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await DaynestSettings.setTheme(mode);
    } catch (_) {
      if (mounted)
        moreMessage(context, 'Could not save the preference. Please retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MoreSurface(
    builder: (context) => Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Appearance',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: DaynestSettings.theme,
            builder: (context, value, _) => DropdownButtonFormField<ThemeMode>(
              key: ValueKey(value),
              initialValue: value,
              decoration: const InputDecoration(labelText: 'Theme'),
              items: const [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('System'),
                ),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
              onChanged: _busy
                  ? null
                  : (v) {
                      if (v != null) _theme(v);
                    },
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (DaynestSettings.loadError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(DaynestSettings.loadError!),
            ),
          const SizedBox(height: 24),
          const AppLockSetting(),
          const SizedBox(height: 24),
          const Text(
            'Your data',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.phone_android_outlined),
                  title: const Text('Stored on this device'),
                  subtitle: const Text(
                    'Notes and imported documents stay local. Vault records are encrypted with your master password.',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Backup & Restore'),
                  subtitle: const Text(
                    'Export an encrypted backup or restore a saved copy.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const BackupPage()),
                  ),
                ),
                const ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('Vault lock'),
                  subtitle: Text(
                    'Locks when Daynest loses focus and after 2 minutes without interaction. The master password cannot be recovered.',
                  ),
                ),
              ],
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: const Text('Saved items'),
              subtitle: Text(
                _loading
                    ? 'Checking…'
                    : _error ??
                          '${_counts['notes'] ?? 0} notes · ${_counts['documents'] ?? 0} documents · ${_counts['vault_entries'] ?? 0} vault entries. Includes trash.',
              ),
              trailing: IconButton(
                tooltip: 'Refresh counts',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About Daynest'),
              subtitle: const Text('Your private everyday companion'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'Daynest',
                applicationVersion: '1.0.0',
                applicationIcon: const Icon(Icons.spa_outlined, size: 32),
                children: [
                  const Text(
                    'An offline organizer for your thoughts, tasks, money and personal records.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
