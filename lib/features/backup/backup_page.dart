import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../more/more_theme.dart';
import 'backup_crypto.dart';
import 'backup_payload.dart';
import 'backup_service.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final _service = BackupService.instance;
  bool _busy = false;
  String? _message;
  Map<String, dynamic> _status = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await _service.status();
      if (mounted) {
        setState(() => _status = value);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Could not read backup history.');
      }
    }
  }

  String _date(dynamic value) {
    final date = value is String ? DateTime.tryParse(value) : null;
    if (date == null) {
      return 'Not yet';
    }
    final d = date.toLocal();
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => _message = e is FormatException
              ? e.message
              : e is FileSystemException
              ? e.message
              : 'Could not finish. Check your password, backup file, and available storage. Your current data was not replaced.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    }
  }

  Future<String?> _password(bool creating) => showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BackupPasswordDialog(creating: creating),
  );
  Future<bool> _save(Uint8List bytes, String prefix) async {
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final uri = await FilePicker.saveFile(
      fileName: '${prefix}_$stamp.daynest',
      bytes: bytes,
      mimeType: 'application/octet-stream',
      dialogTitle: 'Save your encrypted Daynest backup',
    );
    return uri != null;
  }

  Future<void> _create() async {
    final password = await _password(true);
    if (password == null || !mounted) {
      return;
    }
    await _run(() async {
      final bytes = await _service.create(password);
      if (!mounted) {
        return;
      }
      final saved = await _save(bytes, 'Daynest');
      if (saved) {
        await _service.recordExport();
      }
      if (mounted) {
        setState(
          () => _message = saved
              ? 'Backup exported successfully. Keep the file and its password safe.'
              : 'Save cancelled. No backup was exported.',
        );
      }
    });
  }

  Future<void> _restore() async => _run(() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose a .daynest backup',
    );
    if (file == null || !mounted) {
      return;
    }
    final size = await file.length();
    if (size != null && size > backupMaxFileBytes) {
      throw const FormatException('Choose a backup smaller than 64 MB.');
    }
    // Bounded streaming also handles providers that cannot report a length.
    final builder = BytesBuilder(copy: false);
    var count = 0;
    await for (final chunk in file.readAsByteStream()) {
      count += chunk.length;
      if (count > backupMaxFileBytes) {
        throw const FormatException('Backup file exceeds 64 MB.');
      }
      builder.add(chunk);
    }
    if (!mounted) {
      return;
    }
    final password = await _password(false);
    if (password == null) {
      return;
    }
    BackupPayload? payload;
    try {
      payload = await _service.inspect(builder.takeBytes(), password);
      if (!mounted) {
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RestorePreview(payload: payload!),
      );
      if (confirmed != true || !mounted) {
        return;
      }
      await _service.queueRestore(password);
    } finally {
      await _service.discardPreview();
    }
  });
  Future<void> _exportSafety() async => _run(() async {
    final bytes = await _service.safetyBytes();
    if (bytes == null) {
      throw const FormatException('No safety copy has been created yet.');
    }
    final saved = await _save(bytes, 'Daynest_PreRestore_Safety');
    if (mounted) {
      setState(
        () => _message = saved
            ? 'Safety copy exported. Use the backup password entered for that restore to open it.'
            : 'Save cancelled.',
      );
    }
  });
  @override
  Widget build(BuildContext context) => MoreSurface(
    builder: (context) => PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Backup & Restore')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Icon(
              Icons.cloud_upload_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              'Keep a copy of your Daynest',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            const Text(
              'Export one password-protected file containing your journals, drafts, photos, tasks, money, habits, goals, notes, documents and encrypted vault records.',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Create backup'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _restore,
              icon: const Icon(Icons.restore_outlined),
              label: const Text('Restore backup'),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text(
                'Preparing or validating your backup. Keep Daynest open; a large backup may take a little time.',
              ),
            ],
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SelectableText(_message!),
              ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last successful export: ${_date(_status['lastExport'])}',
                    ),
                    const SizedBox(height: 8),
                    Text('Last restore: ${_date(_status['lastRestore'])}'),
                    if (_status['notice'] is String) ...[
                      const SizedBox(height: 10),
                      Text(_status['notice'] as String),
                    ],
                    if (_status['reminderWarning'] is String) ...[
                      const SizedBox(height: 10),
                      Text(_status['reminderWarning'] as String),
                    ],
                  ],
                ),
              ),
            ),
            if (_status['safetyCreated'] != null) ...[
              const SizedBox(height: 12),
              Text('Safety copy created: ${_date(_status['safetyCreated'])}'),
              TextButton.icon(
                onPressed: _busy ? null : _exportSafety,
                icon: const Icon(Icons.save_alt),
                label: const Text('Export last pre-restore safety copy'),
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              'How it works',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            const Text(
              '• Choose where Android saves the file, including an available cloud-storage provider. There is no automatic cloud sync.\n\n'
              '• Remember your backup password. It cannot be recovered. Your vault still needs its original master password after restoration.\n\n'
              '• Restore replaces existing data after preview and confirmation. An encrypted safety copy is saved first using the password you enter for the restore. The latest safety copy replaces the previous one.\n\n'
              '• Daynest will ask you to close and reopen it to apply the restore safely. App lock is turned off in restored preferences; configure it again afterward.\n\n'
              '• This first version supports 25 MB of attachments in total, 40 MB of unencrypted backup data, and 100,000 records. No files are silently skipped.\n\n'
              '• Local safety copies are removed if you uninstall or clear app storage. Export important backups outside the app.',
              style: TextStyle(height: 1.5),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BackupPasswordDialog extends StatefulWidget {
  final bool creating;
  const _BackupPasswordDialog({required this.creating});
  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final _password = TextEditingController(), _confirm = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _show = false;
  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _password.text);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.creating ? 'Create backup password' : 'Enter backup password',
    ),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This password protects the exported file. It is separate from app lock and your vault master password.',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: !_show,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Backup password',
                suffixIcon: IconButton(
                  tooltip: 'Show/hide password',
                  onPressed: () => setState(() => _show = !_show),
                  icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                ),
              ),
              validator: (v) {
                if (widget.creating) {
                  try {
                    validateBackupPassword(v ?? '');
                  } on FormatException catch (e) {
                    return e.message;
                  }
                }
                return (v ?? '').isEmpty ? 'Enter the password' : null;
              },
            ),
            if (widget.creating)
              TextFormField(
                controller: _confirm,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                ),
                validator: (v) =>
                    v != _password.text ? 'Passwords do not match' : null,
              ),
            const SizedBox(height: 12),
            const Text(
              'Keep this password safe. Daynest cannot recover it.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Continue')),
    ],
  );
}

class _RestorePreview extends StatefulWidget {
  final BackupPayload payload;
  const _RestorePreview({required this.payload});
  @override
  State<_RestorePreview> createState() => _RestorePreviewState();
}

class _RestorePreviewState extends State<_RestorePreview> {
  bool _agree = false;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Review backup'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Created: ${DateTime.parse(widget.payload.created).toLocal()}',
            ),
            const SizedBox(height: 12),
            for (final entry in widget.payload.counts.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text('${entry.key}: ${entry.value}'),
              ),
            const SizedBox(height: 16),
            const Text(
              'Counts include trash. Restoring replaces your current data. A complete encrypted safety copy must succeed before replacement is queued. Its password is the one you just entered.',
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _agree,
              onChanged: (v) => setState(() => _agree = v ?? false),
              title: const Text(
                'I understand that existing data will be replaced and I must reopen Daynest.',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _agree ? () => Navigator.pop(context, true) : null,
        child: const Text('Prepare restore'),
      ),
    ],
  );
}

/// Wrap the existing app-lock gate in MaterialApp.builder. Routes cannot be used once a restore is queued.
class BackupRestartGuard extends StatelessWidget {
  final Widget child;
  const BackupRestartGuard({super.key, required this.child});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: BackupService.instance.restartRequired,
    builder: (context, pending, _) => Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: pending,
          child: Offstage(offstage: pending, child: child),
        ),
        if (pending)
          Positioned.fill(
            child: Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.restart_alt, size: 54),
                        const SizedBox(height: 18),
                        Text(
                          'Restore is ready',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Your safety copy is saved. Close Daynest with the button below, then reopen it from the app icon. The restore will finish before your data screens open.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () => exit(0),
                          child: const Text('Close Daynest'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class BackupRecoveryApp extends StatelessWidget {
  static final _messenger = GlobalKey<ScaffoldMessengerState>();
  final String message;
  final Future<void> Function() onRetry;
  const BackupRecoveryApp({
    super.key,
    required this.message,
    required this.onRetry,
  });
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    scaffoldMessengerKey: _messenger,
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.restore, size: 48),
                const SizedBox(height: 16),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 18),
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
                TextButton(
                  onPressed: () async {
                    try {
                      if (await BackupService.instance.cancelPendingRestore()) {
                        await onRetry();
                      } else if (context.mounted) {
                        _messenger.currentState?.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'The restore is already committed. Tap Retry to complete recovery.',
                            ),
                          ),
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        _messenger.currentState?.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not cancel safely. Keep your app data and recovery files, free storage, and retry.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Cancel pending restore'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
