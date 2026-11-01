import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'features/journal/journal_page.dart';
import 'features/money/money_page.dart';
import 'features/tasks/tasks_page.dart';
import 'features/more/more_page.dart';
import 'features/more/more_store.dart';
import 'features/progress/progress_page.dart';
import 'features/security/app_lock.dart';
import 'features/backup/backup_service.dart';
import 'features/backup/backup_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final recoveryError = await BackupService.instance.startup();
  if (recoveryError != null) {
    runApp(BackupRecoveryApp(message: recoveryError, onRetry: main));
    return;
  }
  runApp(const DaynestApp());
}
class DaynestApp extends StatefulWidget {
  const DaynestApp({super.key});

  @override
  State<DaynestApp> createState() => _DaynestAppState();
}
class _DaynestAppState extends State<DaynestApp> {
  @override
  void initState() {
    super.initState();
    DaynestSettings.load();
  }

  ThemeData buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF234C3D),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF101713) : const Color(0xFFF8F5ED),
      appBarTheme: AppBarTheme(
        backgroundColor:
            isDark ? const Color(0xFF101713) : const Color(0xFFF8F5ED),
        foregroundColor: scheme.onSurface,
        centerTitle: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: DaynestSettings.theme,
      builder: (context, mode, _) => MaterialApp(
        title: 'Daynest',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          quill.FlutterQuillLocalizations.delegate,
        ],
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        builder: (context, child) => BackupRestartGuard(
          child: AppLockGate(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: const AppShell(),
      ),
    );
  }
}


class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int selectedIndex = 0;
  static const titles = ['Daynest', 'Journal', 'Money', 'Tasks', 'More'];
  @override
  Widget build(BuildContext context) => Scaffold(
    // Journal and Money own their headers, including their search and menus.
    appBar: selectedIndex != 0 ? null : AppBar(
      title: Row(mainAxisSize: MainAxisSize.min, children: [
        if (selectedIndex == 0) ...[
          ClipRRect(borderRadius: BorderRadius.circular(9), child: Image.asset('assets/branding/daynest_icon.png', width: 34, height: 34)),
          const SizedBox(width: 10),
        ],
        Text(titles[selectedIndex], style: const TextStyle(fontWeight: FontWeight.bold)),
      ])),
    body: IndexedStack(index: selectedIndex, children: const [
      TodayPage(), JournalPage(), MoneyPage(),
      TasksPage(), DaynestMorePage(),
    ]),
    bottomNavigationBar: NavigationBar(selectedIndex: selectedIndex,
      onDestinationSelected: (index) => setState(() => selectedIndex = index),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Today'),
        NavigationDestination(icon: Icon(Icons.auto_stories_outlined), selectedIcon: Icon(Icons.auto_stories), label: 'Journal'),
        NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Money'),
        NavigationDestination(icon: Icon(Icons.check_circle_outline), selectedIcon: Icon(Icons.check_circle), label: 'Tasks'),
        NavigationDestination(icon: Icon(Icons.menu), label: 'More'),
      ]),
  );
}

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final date = MaterialLocalizations.of(context).formatFullDate(DateTime.now());
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(date, style: TextStyle(color: colors.onSurfaceVariant)),
      const SizedBox(height: 24),
      Container(padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.spa_outlined, size: 36, color: colors.onPrimaryContainer),
          const SizedBox(height: 16),
          Text('Your day, in one place.', style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: colors.onPrimaryContainer, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('A private space for your thoughts, plans, and everyday life.',
            style: TextStyle(color: colors.onPrimaryContainer)),
        ])),
      const SizedBox(height: 24),
      Text('Your space is ready', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('Use the tabs below to explore. We will build and connect each feature step by step.'),
      const SizedBox(height: 24),
      const HomeProgressSection(),
    ]);
  }
}

class MorePage extends StatelessWidget {
  const MorePage({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: const [
    FeatureMenuItem(icon: Icons.note_alt_outlined, title: 'Notes', description: 'Folders, ideas, and important notes.'),
    FeatureMenuItem(icon: Icons.folder_outlined, title: 'Documents', description: 'Organize your important files.'),
    FeatureMenuItem(icon: Icons.lock_outline, title: 'Passwords', description: 'Vault not implemented yet. Do not enter real passwords.'),
    FeatureMenuItem(icon: Icons.settings_outlined, title: 'Settings', description: 'Preferences and backup options.'),
  ]);
}

class FeatureMenuItem extends StatelessWidget {
  final IconData icon;
  final String title, description;
  const FeatureMenuItem({super.key, required this.icon, required this.title, required this.description});
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    leading: Icon(icon), title: Text(title), subtitle: Text(description),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(
      appBar: AppBar(title: Text(title)), body: FeaturePlaceholder(icon: icon, title: title,
        description: '$description\n\nComing in a later step.')))),
  );
}

class FeaturePlaceholder extends StatelessWidget {
  final IconData icon;
  final String title, description;
  const FeaturePlaceholder({super.key, required this.icon, required this.title, required this.description});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(32), children: [
    const SizedBox(height: 48), Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
    const SizedBox(height: 20), Text(title, textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 12), Text(description, textAlign: TextAlign.center),
    const SizedBox(height: 20), const Text('Not implemented yet', textAlign: TextAlign.center,
      style: TextStyle(fontStyle: FontStyle.italic)),
  ]);
}
