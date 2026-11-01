import 'dart:async';
import 'package:flutter/material.dart';
import '../journal/journal_editor.dart';
import '../money/money_page.dart' show moneyText;
import 'progress_model.dart';
import 'progress_store.dart';

final _store = ProgressStore.instance;
void _message(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save this change. Please retry. ($error)')));
}
Future<void> _change(BuildContext context, Future<void> Function() action) async {
  try { await action(); } catch (error) { if (context.mounted) { _message(context, error); } }
}
Future<void> openProgressHub(BuildContext context) => showDialog<void>(context: context,
  builder: (_) => Dialog(insetPadding: const EdgeInsets.all(12), clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: const ProgressHub())));

class HomeProgressSection extends StatefulWidget {
  const HomeProgressSection({super.key});
  @override State<HomeProgressSection> createState() => _HomeProgressSectionState();
}
class _HomeProgressSectionState extends State<HomeProgressSection> with WidgetsBindingObserver {
  late Future<ProgressSnapshot> _future;
  Timer? _timer;
  String _day = progressDay(DateTime.now());
  @override void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this);
    _future = _store.snapshot(); _store.revision.addListener(_reload);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _checkDate());
  }
  void _checkDate() { if (_day != progressDay(DateTime.now())) { _day = progressDay(DateTime.now()); _reload(); } }
  @override void didChangeAppLifecycleState(AppLifecycleState state) { if (state == AppLifecycleState.resumed) { _checkDate(); } }
  void _reload() { if (mounted) { setState(() => _future = _store.snapshot()); } }
  @override void dispose() { _timer?.cancel(); _store.revision.removeListener(_reload); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(
        color: colors.brightness == Brightness.dark ? colors.primaryContainer : const Color(0xFF173F33), borderRadius: BorderRadius.circular(26)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.auto_stories_outlined, color: Color(0xFF99D8BE)), SizedBox(width: 8),
            Text('DAILY REFLECTION', style: TextStyle(color: Color(0xFF99D8BE), letterSpacing: 1))]),
          const SizedBox(height: 12), const Text('A little space for your day',
            style: TextStyle(fontFamily: 'serif', fontSize: 25, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 8), const Text('Capture your thoughts, what you learned, and daily wins.', style: TextStyle(color: Color(0xFFD4E6DC), height: 1.5)),
          const SizedBox(height: 16), FilledButton.tonal(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => JournalEditor(initialDate: DateTime.now()))), child: const Text('Write a reflection')),
        ])),
      const SizedBox(height: 20),
      Card(margin: EdgeInsets.zero, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26), side: BorderSide(color: colors.outlineVariant)),
        child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, children: [
            const Text('🔥 Daily Habits', style: TextStyle(fontFamily: 'serif', fontSize: 23, fontWeight: FontWeight.bold)),
            TextButton(onPressed: () => openProgressHub(context), child: const Text('Progress Hub ›')),
          ]),
          FutureBuilder<ProgressSnapshot>(future: _future, builder: (context, state) {
            if (state.hasError) { return TextButton(onPressed: _reload, child: const Text('Could not load habits. Tap to retry.')); }
            if (!state.hasData) { return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())); }
            final data = state.data!, active = data.active(DateTime.now());
            return Column(children: [
              if (active.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Text('Start small. Add a daily habit you want to keep.')),
              for (final habit in active) Padding(padding: const EdgeInsets.only(top: 8), child: DecoratedBox(
                decoration: BoxDecoration(border: Border.all(color: colors.outlineVariant), borderRadius: BorderRadius.circular(16)),
                child: CheckboxListTile(controlAffinity: ListTileControlAffinity.leading,
                  value: data.logs.contains(logKey(habit['id'] as int, progressDay(DateTime.now()))),
                  onChanged: (done) => _change(context, () => _store.checkHabit(habit['id'] as int, DateTime.now(), done ?? false)),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(habit['title'] as String),
                        ),
                        IconButton(
                          tooltip: 'Delete habit',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final confirmed = await _confirm(
                              context,
                              'Delete this habit?',
                              'This permanently removes the habit and its saved check-ins.',
                            );

                            if (!confirmed || !context.mounted) return;

                            await _change(
                              context,
                                  () => _store.deleteHabit(habit['id'] as int),
                            );
                          },
                        ),
                      ],
                    ),
                    subtitle: Text(habit['category'] as String)))),
              const SizedBox(height: 10), TextButton.icon(onPressed: () => _habitDialog(context), icon: const Icon(Icons.add), label: const Text('Add a daily habit')),
            ]);
          }),
        ]))),
    ]);
  }
}

class ProgressHub extends StatefulWidget {
  const ProgressHub({super.key});
  @override State<ProgressHub> createState() => _ProgressHubState();
}
class _ProgressHubState extends State<ProgressHub> with WidgetsBindingObserver {
  int _tab = 0, _range = 7;
  late Future<ProgressSnapshot> _future;
  Future<ReviewSummary>? _review;
  DateTime _now = DateTime.now();
  Timer? _timer;
  @override void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this); _load(); _store.revision.addListener(_reload);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _checkDate());
  }
  void _load() { _now = DateTime.now(); _future = _store.snapshot(); _setReview(); }
  void _setReview() { _review = null; }
  void _reload() { if (mounted) { setState(_load); } }
  void _checkDate() { if (progressDay(_now) != progressDay(DateTime.now())) { _reload(); } }
  @override void didChangeAppLifecycleState(AppLifecycleState state) { if (state == AppLifecycleState.resumed) { _reload(); } }
  @override void dispose() { _timer?.cancel(); _store.revision.removeListener(_reload); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(height: MediaQuery.sizeOf(context).height * .90, child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 18, 8, 8), child: Row(children: [
        Icon(Icons.emoji_events_outlined, color: colors.primary), const SizedBox(width: 12),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Personal Progress & Streaks', style: TextStyle(fontFamily: 'serif', fontSize: 23, fontWeight: FontWeight.bold)),
          SizedBox(height: 4), Text('Calculated from your saved logs', style: TextStyle(fontSize: 13)),
        ])), IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
      ])), const Divider(),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: [
        Expanded(child: _tabButton('Habit Streaks\n& Goals', 0)), const SizedBox(width: 8),
        Expanded(child: _tabButton('Periodic Review\n& Analytics', 1)),
      ])),
      Expanded(child: _tab == 0 ? FutureBuilder<ProgressSnapshot>(future: _future, builder: (context, state) {
        if (state.hasError) { return _failure('Could not load progress.'); }
        if (state.connectionState == ConnectionState.waiting || !state.hasData) { return const Center(child: CircularProgressIndicator()); }
        return _habits(state.data!);
      }) : FutureBuilder<ReviewSummary>(future: _review ??= _future.then((data) => _store.review(data, _range, _now)), builder: (context, state) {
        if (state.hasError) { return _failure('Could not load your review.'); }
        if (state.connectionState == ConnectionState.waiting || !state.hasData) { return const Center(child: CircularProgressIndicator()); }
        return _analytics(state.data!);
      })),
    ]));
  }
  Widget _tabButton(String label, int index) => TextButton(
    style: TextButton.styleFrom(backgroundColor: _tab == index ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6)),
    onPressed: () => setState(() => _tab = index), child: Text(label, textAlign: TextAlign.center));
  Widget _failure(String text) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(text), TextButton(onPressed: _reload, child: const Text('Retry'))]));
  Widget _habits(ProgressSnapshot data) {
    final habits = data.active(_now), days = reviewDays(_now, 7), colors = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(18), children: [
      Text('Daily consistency · last 7 days', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6), const Text('Swipe the table to see every day. Tap a box to update a saved check-in.', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 14),
      if (habits.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('No daily habits yet. Add your first one below.')),
      if (habits.isNotEmpty) SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: 660,
        child: Column(children: [
          Row(children: [const SizedBox(width: 210), for (final day in days) SizedBox(width: 58,
            child: Text('${const ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][day.weekday-1]}\n${day.day}/${day.month}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)))]),
          for (final h in habits) Container(margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(border: Border.all(color: colors.outlineVariant), borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              SizedBox(width: 210, child: Padding(padding: const EdgeInsets.only(left: 12), child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(h['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4), Text('${h['category']} · 🔥 ${habitStreak(h['id'] as int, data.logs, _now)}d', style: const TextStyle(fontSize: 12)),
                  if (h['archived_on'] != null) const Text('Retires tomorrow', style: TextStyle(fontSize: 11)),
                ])),
                if (h['archived_on'] == null) IconButton(
                  tooltip: 'Delete habit',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () async {
                    final confirmed = await _confirm(
                      context,
                      'Delete this habit?',
                      'This permanently removes the habit and its saved check-ins.',
                    );

                    if (!confirmed || !mounted) return;

                    await _change(
                      context,
                          () => _store.deleteHabit(h['id'] as int),
                    );
                  },
                ),
              ]))),
              for (final day in days) SizedBox(width: 58, child: habitEligible(h, progressDay(day)) ? Checkbox(
                value: data.logs.contains(logKey(h['id'] as int, progressDay(day))),
                onChanged: (v) => _change(context, () => _store.checkHabit(h['id'] as int, day, v ?? false))) : const Center(child: Text('—'))),
            ])),
        ]))),
      const SizedBox(height: 14), OutlinedButton.icon(onPressed: () => _habitDialog(context), icon: const Icon(Icons.add), label: const Text('Add a daily habit')),
      const SizedBox(height: 26), const Divider(),
      Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Quarterly & annual goals', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontFamily: 'serif')),
        TextButton.icon(onPressed: () => _goalDialog(context), icon: const Icon(Icons.add), label: const Text('Add goal')),
      ]),
      if (data.goals.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Set a goal and update its progress as you go.')),
      for (final goal in data.goals) _goalCard(goal),
    ]);
  }
  Widget _goalCard(ProgressRow goal) {
    final current = (goal['current'] as num).toDouble(), target = (goal['target'] as num).toDouble();
    final ratio = current / target;
    String number(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    return Card(elevation: 0, margin: const EdgeInsets.symmetric(vertical: 6), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(goal['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17))),
        IconButton(tooltip: 'Update goal', onPressed: () => _goalDialog(context, goal), icon: const Icon(Icons.edit_outlined)),
        IconButton(tooltip: 'Delete goal', onPressed: () async {
          final confirmed = await _confirm(context, 'Delete this goal?', 'This removes this goal and its progress.');
          if (confirmed && mounted) { await _change(context, () => _store.deleteGoal(goal['id'] as int)); }
        }, icon: const Icon(Icons.delete_outline)),
      ]), Text('${number(current)} / ${number(target)} ${goal['unit']} · ${(ratio * 100).round()}%'),
      const SizedBox(height: 10), LinearProgressIndicator(value: ratio.clamp(0.0, 1.0).toDouble(), minHeight: 8, borderRadius: BorderRadius.circular(8)),
      const SizedBox(height: 10), Text('${goal['period']} · ${goal['start_on']} to ${goal['end_on']}', style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 4), const Text('Progress updated manually', style: TextStyle(fontSize: 11)),
    ])));
  }
  Widget _analytics(ReviewSummary data) => ListView(padding: const EdgeInsets.all(18), children: [
    Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [const Text('Review range:'),
      for (final range in [7,30]) ChoiceChip(label: Text('Last $range days'), selected: _range == range,
        onSelected: (_) => setState(() { _range = range; _setReview(); })),
    ]), const SizedBox(height: 18),
    LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth >= 340 ? (constraints.maxWidth-12)/2 : constraints.maxWidth;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        _metric(width, Icons.check_circle_outline, 'Tasks finished', '${data.finished} tasks', 'Completed in this range', 0),
        _metric(width, Icons.auto_stories_outlined, 'Journal consistency', '${data.journalPercent}% (${data.journalDays}d)', 'Days with a saved entry', 1),
        _metric(width, Icons.local_fire_department_outlined, 'Habit score', data.habits.percent == null ? '—' : '${data.habits.percent}%',
          '${data.habits.completed} / ${data.habits.eligible} check-ins', 2),
        _metric(width, Icons.account_balance_wallet_outlined, 'Recorded spending', moneyText(data.spending), 'Logged expenses', 3),
      ]);
    }), const SizedBox(height: 18),
    Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Your ${_range == 7 ? 'weekly' : 'monthly'} insight', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 10), Text(data.insight, style: const TextStyle(height: 1.6)),
      const SizedBox(height: 8), const Text('Based on recorded activity. No AI service is used.', style: TextStyle(fontSize: 11)),
    ]))),
    const SizedBox(height: 10), const Text('Includes today. Habits count only from their creation day until retirement. Journal consistency counts distinct dates; trash is excluded. Task completion dates are recorded from this update onward.', style: TextStyle(fontSize: 12, height: 1.5)),
    if (data.unknownCompletions > 0) Padding(padding: const EdgeInsets.only(top: 10), child: Text('${data.unknownCompletions} older completed tasks have no completion date and are excluded from this review.', style: const TextStyle(fontSize: 12))),
    TextButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('Refresh review')),
  ]);
  Widget _metric(double width, IconData icon, String title, String value, String caption, int tint) {
    final colors = Theme.of(context).colorScheme;
    final background = colors.brightness == Brightness.dark ? colors.surfaceContainerHigh :
      const [Color(0xFFF0F7F4),Color(0xFFFFFAE9),Color(0xFFEBFAF2),Color(0xFFF5F4F1)][tint];
    return SizedBox(width: width, child: Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: background,
      border: Border.all(color: colors.outlineVariant), borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: colors.primary), const SizedBox(height: 8), Text(title, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 14), Text(value, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8), Text(caption, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
      ])));
  }
}
Future<bool> _confirm(BuildContext context, String title, String text) async => await showDialog<bool>(context: context, builder: (context) => AlertDialog(
  title: Text(title), content: Text(text), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm'))])) ?? false;
Future<void> _habitDialog(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _HabitDialog());
class _HabitDialog extends StatefulWidget {
  const _HabitDialog(); @override State<_HabitDialog> createState() => _HabitDialogState();
}
class _HabitDialogState extends State<_HabitDialog> {
  final _title = TextEditingController(); final _form = GlobalKey<FormState>();
  String _category = 'Mind'; bool _busy = false; String? _error;
  @override void dispose() { _title.dispose(); super.dispose(); }
  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) { return; }
    setState(() { _busy = true; _error = null; });
    try { await _store.addHabit(_title.text, _category); if (mounted) { Navigator.pop(context); } }
    catch (_) { if (mounted) { setState(() { _busy = false; _error = 'Could not save your habit. Please retry.'; }); } }
  }
  @override Widget build(BuildContext context) => PopScope(canPop: !_busy, child: AlertDialog(title: const Text('Add a daily habit'),
    content: SingleChildScrollView(child: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextFormField(controller: _title, enabled: !_busy, maxLength: 100, decoration: const InputDecoration(labelText: 'Habit name', hintText: 'Read 20 pages'), validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a habit name' : null),
      const SizedBox(height: 12), DropdownButtonFormField<String>(initialValue: _category, decoration: const InputDecoration(labelText: 'Category'),
        items: [for (final category in ['Mind','Body','Growth']) DropdownMenuItem(value: category, child: Text(category))], onChanged: _busy ? null : (v) => setState(() => _category = v!)),
      if (_error != null) Text(_error!),
    ]))), actions: [TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Add'))]));
}
Future<void> _goalDialog(BuildContext context, [ProgressRow? goal]) => showDialog<void>(context: context, builder: (_) => _GoalDialog(goal: goal));
class _GoalDialog extends StatefulWidget {
  final ProgressRow? goal; const _GoalDialog({this.goal}); @override State<_GoalDialog> createState() => _GoalDialogState();
}
class _GoalDialogState extends State<_GoalDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _unit, _target, _current;
  String _period = 'Annual'; bool _busy = false; String? _error;
  @override void initState() { super.initState(); final g = widget.goal;
    _title = TextEditingController(text: g?['title'] as String? ?? ''); _unit = TextEditingController(text: g?['unit'] as String? ?? '');
    _target = TextEditingController(text: g?['target']?.toString() ?? ''); _current = TextEditingController(text: g?['current']?.toString() ?? '0');
    _period = g?['period'] as String? ?? 'Annual';
  }
  @override void dispose() { for (final c in [_title,_unit,_target,_current]) { c.dispose(); } super.dispose(); }
  String? _number(String? v, bool target) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n < 0 || n>1e9 || (target && n == 0) ? 'Enter a valid ${target ? 'positive target' : 'progress value'}' : null; }
  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) { return; } setState(() { _busy = true; _error = null; });
    try { await _store.saveGoal(id: widget.goal?['id'] as int?, title: _title.text, unit: _unit.text,
      target: double.parse(_target.text), current: double.parse(_current.text), period: _period);
      if (mounted) { Navigator.pop(context); }
    } catch (_) { if (mounted) { setState(() { _busy = false; _error = 'Could not save your goal. Please retry.'; }); } }
  }
  @override Widget build(BuildContext context) => PopScope(canPop: !_busy, child: AlertDialog(title: Text(widget.goal == null ? 'Add a goal' : 'Update goal'),
    content: SingleChildScrollView(child: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextFormField(controller: _title, enabled: !_busy, maxLength: 100, decoration: const InputDecoration(labelText: 'Goal name'), validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null),
      TextFormField(controller: _unit, enabled: !_busy, maxLength: 30, decoration: const InputDecoration(labelText: 'Unit', hintText: 'books, sessions, hours'), validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a unit' : null),
      TextFormField(controller: _target, enabled: !_busy, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Target'), validator: (v) => _number(v, true)),
      TextFormField(controller: _current, enabled: !_busy, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Current progress'), validator: (v) => _number(v, false)),
      const SizedBox(height: 12), DropdownButtonFormField<String>(initialValue: _period, decoration: const InputDecoration(labelText: 'Period'),
        items: [for (final p in ['Quarterly','Annual']) DropdownMenuItem(value: p, child: Text(p))],
        onChanged: _busy || widget.goal != null ? null : (v) => setState(() => _period = v!)),
      const SizedBox(height: 8), Text(widget.goal == null ? 'Starts in the current calendar quarter or year.' : 'The original period dates are preserved.', style: const TextStyle(fontSize: 12)),
      if (_error != null) Text(_error!),
    ]))), actions: [TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save'))]));
}
