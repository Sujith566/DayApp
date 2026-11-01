import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sqflite/sqflite.dart';
import '../more/more_store.dart';
import '../more/vault_store.dart';

/// Device authentication gates the UI. The password vault keeps its own encryption/password.
class AppLockController extends ChangeNotifier with WidgetsBindingObserver {
  AppLockController._();
  static final instance = AppLockController._();
  static const _native = MethodChannel('daynest/app_lock');
  final _auth = LocalAuthentication();
  bool loading = true, enabled = false, locked = true, authenticating = false;
  String? error;
  bool _started = false;
  AppLifecycleState _lifecycle = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  bool get covered => loading || authenticating || (enabled && locked);
  void start() {
    if (_started) { return; }
    _started = true; WidgetsBinding.instance.addObserver(this); load();
  }
  Future<void> _secure(bool value) => _native.invokeMethod<void>('secure', value);
  Future<void> load() async {
    loading = true; error = null; notifyListeners();
    try {
      final db = await MoreStore.instance.db;
      final rows = await db.query('preferences', where:'name = ?', whereArgs:['app_lock']);
      enabled = rows.isNotEmpty && rows.first['value'] == 'enabled';
      await _secure(enabled);
      locked = enabled; loading = false;
    } catch (_) {
      // Fail closed if the stored preference cannot be read or native protection fails.
      error = 'Could not load app security. Tap Retry to try again.';
    }
    notifyListeners();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state != AppLifecycleState.resumed) {
      VaultStore.instance.lock();
      if (enabled &&
          !authenticating &&
          (state == AppLifecycleState.hidden ||
              state == AppLifecycleState.paused)) {
        locked = true;
      }
    }
    notifyListeners();
  }
  Future<bool> _verify(String reason) async {
    if (!await _auth.isDeviceSupported()) {
      throw StateError('Set a PIN, pattern, password, or biometric screen lock in Android Settings first.');
    }
    return _auth.authenticate(localizedReason: reason, biometricOnly: false, persistAcrossBackgrounding: true);
  }
  Future<void> unlock() async {
    if (loading || authenticating || !enabled) { return; }
    authenticating = true; error = null; notifyListeners();
    try {
      final ok = await _verify('Unlock Daynest to access your private records');
      locked = !ok;
      if (!ok) { error = 'Authentication cancelled. Your app stays locked.'; }
    } catch (_) {
      locked = true; error = 'Could not authenticate. Check your device screen lock and try again.';
    } finally { authenticating = false; notifyListeners(); }
  }
  Future<String?> setEnabled(bool value) async {
    if (loading || authenticating) { return 'Please finish the current authentication first.'; }
    if (value == enabled) { return null; }
    authenticating = true; error = null; notifyListeners();
    String? failure;
    try {
      final ok = await _verify(value ? 'Enable app lock for Daynest' : 'Confirm turning off Daynest app lock');
      if (!ok) {
        failure = 'Authentication was not completed. The setting was not changed.';
      } else {
        // Apply protection before persisting enablement. Disabling stays protected until saved.
        if (value) { await _secure(true); }
        await (await MoreStore.instance.db).insert('preferences', {'name':'app_lock','value': value ? 'enabled' : 'disabled'}, conflictAlgorithm: ConflictAlgorithm.replace);
        enabled = value; locked = false;
        if (!value) { await _secure(false); }
      }
    } catch (e) {
      failure = e is StateError ? e.message.toString() : 'Could not change app lock. Check your Android screen lock and retry.';
    } finally {
      authenticating = false;
      if (enabled && _lifecycle != AppLifecycleState.resumed) { locked = true; }
      notifyListeners();
    }
    return failure;
  }
  void lockNow() { if (enabled) { locked = true; VaultStore.instance.lock(); notifyListeners(); } }
}

class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});
  @override State<AppLockGate> createState() => _AppLockGateState();
}
class _AppLockGateState extends State<AppLockGate> {
  final _lock = AppLockController.instance;
  @override void initState() { super.initState(); _lock.start(); }
  @override Widget build(BuildContext context) => ListenableBuilder(listenable: _lock, builder: (context, _) => Stack(fit: StackFit.expand, children: [
    // Keep routes alive while preventing painting, hit-testing, focus, or semantics access.
    ExcludeFocus(excluding: _lock.covered, child: Offstage(offstage: _lock.covered, child: widget.child)),
    if (_lock.covered) Positioned.fill(child: Material(color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(28), child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400), child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(borderRadius: BorderRadius.circular(24), child: Image.asset('assets/branding/daynest_icon.png', width: 96, height: 96)),
          const SizedBox(height: 24), Text(_lock.loading ? 'Opening Daynest' : 'Daynest is locked', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12), Text(_lock.error ?? (_lock.loading ? 'Checking your security preference…' : 'Use your device fingerprint, face, PIN, pattern, or password.'), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          if (_lock.authenticating || (_lock.loading && _lock.error == null)) const CircularProgressIndicator()
          else if (_lock.loading) FilledButton(onPressed: _lock.load, child: const Text('Retry'))
          else FilledButton.icon(onPressed: _lock.unlock, icon: const Icon(Icons.lock_open_outlined), label: const Text('Unlock')),
        ]))))))),
  ]));
}
class AppLockSetting extends StatelessWidget {
  const AppLockSetting({super.key});
  @override Widget build(BuildContext context) {
    final lock = AppLockController.instance;
    return ListenableBuilder(listenable: lock, builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Security', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('App lock'),
        subtitle: const Text('Use your Android screen lock when opening Daynest or returning to it. Screenshots are blocked while enabled.'),
        value: lock.enabled, onChanged: lock.loading || lock.authenticating ? null : (value) async {
          final failure = await lock.setEnabled(value);
          if (failure != null && context.mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure))); }
        }),
      if (lock.enabled) OutlinedButton.icon(onPressed: lock.lockNow, icon: const Icon(Icons.lock_outline), label: const Text('Lock now')),
      const SizedBox(height: 8), const Text('App lock controls access to the app. Your password vault still requires its separate master password.', style: TextStyle(fontSize: 12)),
    ]));
  }
}
