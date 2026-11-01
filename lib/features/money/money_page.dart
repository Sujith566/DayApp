import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'money_database.dart';

typedef MoneyRow = Map<String, Object?>;
const _expenseCategories = ['Food & Dining', 'Transport', 'Shopping', 'Utilities', 'Health', 'Bills', 'Education', 'Other'];
const _paymentMethods = ['UPI', 'Cash', 'Card', 'Bank', 'Other'];
const _incomeCategories = ['Salary', 'Freelance', 'Business', 'Gift', 'Other'];
const _chartColors = [Color(0xFF27836A), Color(0xFFF28B52), Color(0xFF578DCD),
  Color(0xFFAC78BF), Color(0xFFDCB354), Color(0xFF7A9591), Color(0xFF6B78B0), Color(0xFFA5ADAB)];

String moneyText(int paise) {
  final sign = paise < 0 ? '−' : '';
  final absolute = paise.abs();
  var whole = (absolute ~/ 100).toString();
  if (whole.length > 3) {
    final tail = whole.substring(whole.length - 3);
    var head = whole.substring(0, whole.length - 3);
    final parts = <String>[];
    while (head.length > 2) {
      parts.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    parts.insert(0, head);
    whole = '${parts.join(',')},$tail';
  }
  final cents = absolute % 100;
  return '$sign₹$whole${cents == 0 ? '' : '.${cents.toString().padLeft(2, '0')}'}';
}

int? parseMoney(String value) {
  final text = value.trim();
  if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(text)) return null;
  final parts = text.split('.');
  final amount = int.parse(parts[0]) * 100 + (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  return amount > 0 && amount <= 100000000000 ? amount : null;
}

ThemeData moneyTheme(BuildContext context) {
  final base = Theme.of(context);
  final dark = base.brightness == Brightness.dark;
  final colors = ColorScheme.fromSeed(seedColor: const Color(0xFF174F43), brightness: base.brightness)
    .copyWith(primary: dark ? const Color(0xFF9ED7C0) : const Color(0xFF174F43),
      onPrimary: dark ? const Color(0xFF103D31) : Colors.white,
      surface: dark ? const Color(0xFF17211E) : const Color(0xFFFCFAF5),
      surfaceContainerHighest: dark ? const Color(0xFF26332E) : const Color(0xFFEEEDE7),
      outlineVariant: dark ? const Color(0xFF35443D) : const Color(0xFFE8E6DE));
  return base.copyWith(colorScheme: colors, scaffoldBackgroundColor: colors.surface,
    appBarTheme: AppBarTheme(backgroundColor: colors.surface, foregroundColor: colors.onSurface,
      elevation: 0, scrolledUnderElevation: 0, centerTitle: false),
    cardTheme: CardThemeData(color: colors.surface, elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant))),
    floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: colors.primary,
      foregroundColor: colors.onPrimary, shape: const StadiumBorder(), elevation: 3),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: colors.surfaceContainerHighest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.primary))),
  );
}

class MoneyPage extends StatefulWidget {
  const MoneyPage({super.key});
  @override
  State<MoneyPage> createState() => _MoneyPageState();
}

class _MoneyPageState extends State<MoneyPage> {
  final _db = MoneyDatabase.instance;
  final _search = TextEditingController();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<MoneyRow> _transactions = [], _previous = [], _people = [], _bills = [];
  int _tab = 0, _generation = 0;
  bool _loading = true, _showSearch = false, _mutating = false;
  String? _error;
  String _flow = 'all';

  @override
  void initState() { super.initState(); _search.addListener(_searchChanged); _load(); }
  void _searchChanged() { if (mounted) setState(() {}); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_generation;
    final month = _month;
    setState(() { _loading = true; _error = null; });
    try {
      final result = await Future.wait([
        _db.transactions(month), _db.transactions(DateTime(month.year, month.month - 1)),
        _db.people(), _db.bills(month),
      ]);
      if (!mounted || generation != _generation) return;
      setState(() {
        _transactions = result[0]; _previous = result[1];
        _people = result[2]; _bills = result[3]; _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() { _loading = false; _error = 'Could not load your money records. Please retry.'; });
    }
  }

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirm(String title, String message) async => await showDialog<bool>(
    context: context, builder: (context) => AlertDialog(title: Text(title), content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm'))])) ?? false;

  Future<void> _mutate(Future<void> Function() action) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    try { await action(); await _load(); }
    catch (_) { _message('Could not complete this action. Your records are kept; please retry.'); }
    finally { if (mounted) setState(() => _mutating = false); }
  }

  Future<void> _edit(String type, {MoneyRow? row, String? flow}) async {
    if (_mutating) return;
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => MoneyEditor(type: type, row: row, initialFlow: flow,
        initialDate: _month.year == DateTime.now().year && _month.month == DateTime.now().month
          ? DateUtils.dateOnly(DateTime.now()) : _month)));
    if (changed == true && mounted) await _load();
  }

  Future<void> _add() async {
    final choice = await showModalBottomSheet<String>(context: context,
      builder: (context) => SafeArea(child: Padding(padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Add to Money', style: TextStyle(fontWeight: FontWeight.w600))),
          for (final item in const [('expense', Icons.remove_circle_outline, 'Expense'),
            ('income', Icons.add_circle_outline, 'Income'),
            ('receivable', Icons.people_outline, 'Someone owes me'),
            ('payable', Icons.person_outline, 'I owe someone'),
            ('bill', Icons.receipt_long_outlined, 'Bill')])
              ListTile(leading: Icon(item.$2), title: Text(item.$3),
                onTap: () => Navigator.pop(context, item.$1)),
        ]))));
    if (choice == null || !mounted) return;
    await _edit(choice == 'bill' ? 'bill' : ['income','expense'].contains(choice)
      ? 'transaction' : 'person', flow: choice);
  }

  Future<void> _recordAction(String type, MoneyRow row, String action) async {
    if (_mutating) return;
    final id = row['id'] as int;
    if (action == 'edit') { await _edit(type, row: row); return; }
    if (action == 'delete') {
      final message = type == 'bill' && row['paid'] == 1
        ? 'Delete this bill? Its recorded expense will remain in Transactions.'
        : type == 'transaction'
          ? 'Delete this transaction? If it paid a bill, that bill will become unpaid.'
          : 'Delete this record permanently? This cannot be undone.';
      if (await _confirm('Delete record?', message) && mounted) {
        await _mutate(() => _db.delete(type, id));
      }
      return;
    }
    if (action == 'settle' || action == 'unsettle') {
      if (await _confirm(action == 'settle' ? 'Mark settled?' : 'Reopen balance?',
        'This changes the balance status only. Record any actual money received or paid separately in Transactions.') && mounted) {
        await _mutate(() => _db.settle(id, action == 'settle'));
      }
    }
    if (action == 'pay') {
      final today = DateUtils.dateOnly(DateTime.now());
      final date = await showDatePicker(context: context, initialDate: today,
        firstDate: DateTime(1900), lastDate: today);
      if (date == null || !mounted) return;
      if (await _confirm('Record bill payment?',
        'This marks the bill paid and adds ${moneyText(row['amount'] as int)} to expenses on ${MoneyDatabase.day(date)}.') && mounted) {
        await _mutate(() => _db.payBill(id, date));
      }
    }
    if (action == 'reopen') {
      if (await _confirm('Reopen bill?', 'This also removes the expense created for this bill payment.') && mounted) {
        await _mutate(() => _db.reopenBill(id));
      }
    }
  }

  int _total(List<MoneyRow> rows, String flow) => rows.where((r) => r['flow'] == flow)
    .fold(0, (sum, r) => sum + (r['amount'] as int));
  void _changeMonth(int n) {
    final next = DateTime(_month.year, _month.month + n);
    if (next.year < 1900 || next.year > 2100) return;
    setState(() => _month = next); _load();
  }

  Widget _summary(BuildContext context, String label, int amount, int previous, bool income) {
    final colors = Theme.of(context).colorScheme;
    final diff = amount - previous;
    final comparison = previous == 0 ? (amount == 0 ? 'No records this month' : 'No previous-month total')
      : '${diff >= 0 ? '+' : '−'}${(diff.abs() * 100 / previous).toStringAsFixed(0)}% from previous month';
    return Card(child: Padding(padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Text(moneyText(amount), style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w600,
          letterSpacing: -0.6)),
        const SizedBox(height: 7),
        Text(comparison, style: TextStyle(fontSize: 10, height: 1.4,
          color: previous == 0 ? colors.onSurfaceVariant : (income ? diff >= 0 : diff <= 0)
            ? colors.primary : colors.error)),
      ])));
  }

  Widget _tabs(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(26)),
      child: Row(children: [
        for (final item in const [(0, 'Overview'), (1, 'Transactions'), (2, 'People'), (3, 'Bills')])
          Expanded(child: Semantics(selected: _tab == item.$1, button: true,
            child: Material(color: _tab == item.$1 ? colors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(22), child: InkWell(
                borderRadius: BorderRadius.circular(22), onTap: () => setState(() => _tab = item.$1),
                child: Padding(padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 2),
                  child: Text(item.$2, textAlign: TextAlign.center, style: TextStyle(fontSize: 11,
                    color: _tab == item.$1 ? colors.onPrimary : colors.onSurfaceVariant))))))),
      ]));
  }

  Widget _overview(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final expense = _total(_transactions, 'expense');
    final income = _total(_transactions, 'income');
    final grouped = <String,int>{};
    for (final row in _transactions.where((r) => r['flow'] == 'expense')) {
      final category = row['category'] as String;
      grouped[category] = (grouped[category] ?? 0) + (row['amount'] as int);
    }
    final groups = grouped.entries.toList()..sort((a,b) => b.value.compareTo(a.value));
    final outstanding = _people.where((r) => r['settled'] == 0).toList();
    final owedToYou = _total(outstanding, 'receivable');
    final youOwe = _total(outstanding, 'payable');
    final due = _bills.where((r) => r['paid'] == 0).toList();
    final dueAmount = due.fold<int>(0,(sum,r) => sum + (r['amount'] as int));
    final chart = SizedBox(height: 176, width: 176, child: Stack(alignment: Alignment.center, children: [
      Positioned.fill(child: CustomPaint(painter: _DonutPainter(
        groups.map((e) => e.value).toList(), colors.surfaceContainerHighest))),
      Padding(padding: const EdgeInsets.all(35), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(moneyText(expense), textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        Text('spent', style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
      ])),
    ]));
    final legend = Column(children: [for (var i=0; i<groups.length; i++) Padding(
      padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle,
          color: _chartColors[i % _chartColors.length])),
        const SizedBox(width: 8),
        Expanded(child: Text(groups[i].key, style: const TextStyle(fontSize: 11))),
        const SizedBox(width: 6),
        Text('${(groups[i].value * 100 / expense).toStringAsFixed(0)}%',
          style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
        const SizedBox(width: 8),
        Text(moneyText(groups[i].value), style: const TextStyle(fontSize: 11)),
      ]))]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (groups.isEmpty) _empty(context, Icons.donut_large, 'See where your money goes',
        'Add an expense to see your spending by category.')
      else Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Spending breakdown', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, size) => size.maxWidth >= 460
          ? Row(children: [chart, const SizedBox(width: 24), Expanded(child: legend)])
          : Column(children: [Center(child: chart), const SizedBox(height: 18), legend])),
      ]))),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
        Icon(Icons.savings_outlined, color: colors.primary), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Net cash flow', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 4), Text(moneyText(income-expense),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          Text('Recorded income minus expenses', style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
        ])),
      ]))),
      _overviewLink(context, Icons.people_outline, 'Money owed to you', moneyText(owedToYou),
        'All outstanding balances', () => setState(() => _tab = 2)),
      _overviewLink(context, Icons.person_outline, 'Money you owe', moneyText(youOwe),
        'All outstanding balances', () => setState(() => _tab = 2)),
      _overviewLink(context, Icons.receipt_long_outlined, 'Bills still to pay', moneyText(dueAmount),
        '${due.length} unpaid in the displayed month', () => setState(() => _tab = 3)),
    ]);
  }

  Widget _overviewLink(BuildContext context, IconData icon, String title, String value,
      String subtitle, VoidCallback onTap) => Card(child: ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primary.withAlpha(18),
      child: Icon(icon, color: Theme.of(context).colorScheme.primary)),
    title: Text(title, style: const TextStyle(fontSize: 13)),
    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: TextStyle(fontSize: 20, color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w600)), Text(subtitle, style: const TextStyle(fontSize: 10)),
    ]), trailing: const Icon(Icons.chevron_right, size: 19), onTap: onTap));

  Widget _empty(BuildContext context, IconData icon, String title, String description) =>
    Padding(padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18),
      child: Column(children: [Icon(icon, size: 34, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 14), Text(title, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8), Text(description, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.6, color: Theme.of(context).colorScheme.onSurfaceVariant))]));

  bool _matches(MoneyRow row) => '${row['title']} ${row['category'] ?? ''} ${row['note']} ${row['payment_method'] ?? ''} ${row['payment_source'] ?? ''}'
    .toLowerCase().contains(_search.text.trim().toLowerCase());

  Widget _recordCard(BuildContext context, MoneyRow row, String type) {
    final colors = Theme.of(context).colorScheme;
    final transaction = type == 'transaction';
    final person = type == 'person';
    final done = row[person ? 'settled' : 'paid'] == 1;
    final income = row['flow'] == 'income';
    final receivable = row['flow'] == 'receivable';
    final linked = transaction && row['bill_id'] != null;
    final date = DateTime.parse(row['entry_date'] as String);
    final overdue = !transaction && !person && !done && date.isBefore(DateUtils.dateOnly(DateTime.now()));
    final payment = [row['payment_method'] as String? ?? '', row['payment_source'] as String? ?? '']
      .where((part) => part.isNotEmpty).join(' · ');
    final status = transaction ? '${row['category']}${payment.isEmpty ? '' : ' · $payment'}' : person
      ? (done ? 'Settled' : receivable ? 'Owes you' : 'You owe')
      : done ? 'Paid' : overdue ? 'Overdue' : 'Unpaid';
    return Card(child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 19, backgroundColor: (transaction && !income || overdue
          ? colors.error : colors.primary).withAlpha(18),
          child: Icon(transaction ? (income ? Icons.south_west : Icons.north_east)
            : person ? Icons.person_outline : Icons.receipt_long_outlined,
            size: 19, color: transaction && !income || overdue ? colors.error : colors.primary)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(row['title'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text('${transaction ? income ? '+' : '−' : ''}${moneyText(row['amount'] as int)}',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
              color: transaction ? income ? colors.primary : colors.error : colors.onSurface)),
          const SizedBox(height: 5),
          Text('$status · ${MaterialLocalizations.of(context).formatMediumDate(date)}',
            style: TextStyle(fontSize: 11, height: 1.5, color: overdue ? colors.error : colors.onSurfaceVariant)),
          if ((row['note'] as String).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
            child: Text(row['note'] as String, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant))),
        ])),
        PopupMenuButton<String>(tooltip: 'Record actions', enabled: !_mutating,
          onSelected: (action) => _recordAction(type, row, action),
          itemBuilder: (_) => [
            if (!(type == 'bill' && done) && !linked)
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
            if (person) PopupMenuItem(value: done ? 'unsettle' : 'settle',
              child: Text(done ? 'Reopen balance' : 'Mark settled')),
            if (type == 'bill') PopupMenuItem(value: done ? 'reopen' : 'pay',
              child: Text(done ? 'Reopen bill' : 'Record payment')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ]),
      ])));
  }

  @override
  Widget build(BuildContext context) => Theme(data: moneyTheme(context), child: Builder(builder: _buildPage));

  Widget _buildPage(BuildContext context) {
    final income = _total(_transactions, 'income');
    final expense = _total(_transactions, 'expense');
    final rows = (_tab == 1 ? _transactions : _tab == 2 ? _people : _bills)
      .where((r) => _matches(r) && (_tab != 1 || _flow == 'all' || r['flow'] == _flow)).toList();
    final type = _tab == 1 ? 'transaction' : _tab == 2 ? 'person' : 'bill';
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, titleSpacing: 20,
        title: const Text('Money', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.7)),
        actions: [
          IconButton(tooltip: 'Search records', icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () => setState(() { _showSearch = !_showSearch;
              if (_showSearch && _tab == 0) _tab = 1;
              if (!_showSearch) _search.clear(); })),
          PopupMenuButton<String>(onSelected: (v) {
            if (v == 'refresh') _load();
            if (v == 'today') { setState(() => _month = DateTime(DateTime.now().year, DateTime.now().month)); _load(); }
          }, itemBuilder: (_) => const [
            PopupMenuItem(value: 'today', child: Text('Current month')),
            PopupMenuItem(value: 'refresh', child: Text('Refresh')),
          ]),
        ]),
      floatingActionButton: FloatingActionButton(onPressed: _mutating ? null : _add,
        tooltip: 'Add money record', child: const Icon(Icons.add)),
      body: SafeArea(top: false, child: RefreshIndicator(onRefresh: _load,
        child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
          SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                IconButton(tooltip: 'Previous month', onPressed: _month.year == 1900 && _month.month == 1
                  ? null : () => _changeMonth(-1), icon: const Icon(Icons.chevron_left, size: 20)),
                Expanded(child: Text(MaterialLocalizations.of(context).formatMonthYear(_month),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                IconButton(tooltip: 'Next month', onPressed: _month.year == 2100 && _month.month == 12
                  ? null : () => _changeMonth(1), icon: const Icon(Icons.chevron_right, size: 20)),
              ]),
              if (!_loading && _error == null) LayoutBuilder(builder: (context, size) {
                final left = _summary(context, 'Monthly income', income, _total(_previous, 'income'), true);
                final right = _summary(context, 'Total expenses', expense, _total(_previous, 'expense'), false);
                return size.maxWidth < 330 || MediaQuery.textScalerOf(context).scale(1) > 1.4
                  ? Column(children: [SizedBox(width: double.infinity, child: left), SizedBox(width: double.infinity, child: right)])
                  : Row(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Expanded(child: left), const SizedBox(width: 10), Expanded(child: right)]);
              }),
              const SizedBox(height: 4), _tabs(context), const SizedBox(height: 16),
              if (_showSearch && _tab != 0) ...[
                TextField(controller: _search, decoration: const InputDecoration(
                  hintText: 'Search records…', prefixIcon: Icon(Icons.search))),
                const SizedBox(height: 12),
              ],
              if (_tab == 1) Wrap(spacing: 8, children: [for (final f in const ['all','income','expense'])
                ChoiceChip(label: Text(f == 'all' ? 'All' : f == 'income' ? 'Income' : 'Expenses'),
                  selected: _flow == f, onSelected: (_) => setState(() => _flow = f))]),
              if (_tab == 2) const Padding(padding: EdgeInsets.only(bottom: 14),
                child: Text('All dates · balances are tracked separately from cash transactions.',
                  style: TextStyle(fontSize: 11, height: 1.5))),
              if (_tab == 3) const Padding(padding: EdgeInsets.only(bottom: 14),
                child: Text('Bills due in the displayed month. Record payment to add the expense.',
                  style: TextStyle(fontSize: 11, height: 1.5))),
              if (_mutating) const LinearProgressIndicator(),
              if (_loading) const Padding(padding: EdgeInsets.all(38), child: Center(child: CircularProgressIndicator()))
              else if (_error != null) Column(children: [Text(_error!),
                TextButton(onPressed: _load, child: const Text('Retry'))])
              else if (_tab == 0) _overview(context)
              else if (rows.isEmpty) _empty(context, _tab == 1 ? Icons.swap_vert : _tab == 2 ? Icons.people_outline : Icons.receipt_long_outlined,
                _search.text.isNotEmpty ? 'No matching records' : _tab == 1 ? 'Your money, clearly recorded'
                  : _tab == 2 ? 'Keep track of shared money' : 'Stay ahead of your bills',
                _search.text.isNotEmpty ? 'Try a different search.' : 'Tap + to add your first record in this view.'),
            ]))),
          if (!_loading && _error == null && _tab != 0) SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(delegate: SliverChildBuilderDelegate(
              (context, index) => _recordCard(context, rows[index], type), childCount: rows.length))),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ]))),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<int> amounts;
  final Color empty;
  _DonutPainter(this.amounts, this.empty);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(center: Offset(size.width/2,size.height/2),
      width: math.min(size.width,size.height)-24, height: math.min(size.width,size.height)-24);
    final paint = Paint()..style=PaintingStyle.stroke..strokeWidth=24;
    canvas.drawArc(rect,0,math.pi*2,false,paint..color=empty);
    final total=amounts.fold<int>(0,(a,b)=>a+b);
    if(total==0)return;
    var angle=-math.pi/2;
    for(var i=0;i<amounts.length;i++){
      final sweep=amounts[i]/total*math.pi*2;
      canvas.drawArc(rect,angle,sweep,false,paint..color=_chartColors[i%_chartColors.length]);
      angle+=sweep;
    }
  }
  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.empty!=empty || old.amounts.length!=amounts.length ||
    List.generate(amounts.length,(i)=>i).any((i)=>old.amounts[i]!=amounts[i]);
}

class MoneyEditor extends StatefulWidget {
  final String type;
  final MoneyRow? row;
  final String? initialFlow;
  final DateTime initialDate;
  const MoneyEditor({super.key, required this.type, this.row, this.initialFlow, required this.initialDate});
  @override
  State<MoneyEditor> createState() => _MoneyEditorState();
}

class _MoneyEditorState extends State<MoneyEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _amount, _note, _paymentSource;
  late DateTime _date;
  late String _flow, _category;
  String _paymentMethod = '';
  bool _busy = false, _dirty = false, _leaving = false, _exitDialog = false;
  List<String> get _categories => _flow == 'income' ? _incomeCategories : _expenseCategories;

  @override
  void initState() {
    super.initState();
    final row = widget.row;
    _title = TextEditingController(text: row?['title'] as String? ?? '');
    final paise = row?['amount'] as int?;
    _amount = TextEditingController(text: paise == null ? '' : '${paise ~/ 100}.${(paise % 100).toString().padLeft(2,'0')}');
    _note = TextEditingController(text: row?['note'] as String? ?? '');
    _paymentMethod = row?['payment_method'] as String? ?? '';
    if (!_paymentMethods.contains(_paymentMethod)) _paymentMethod = '';
    _paymentSource = TextEditingController(text: row?['payment_source'] as String? ?? '');
    _date = row == null ? widget.initialDate : DateTime.parse(row['entry_date'] as String);
    _flow = row?['flow'] as String? ?? widget.initialFlow ?? (widget.type == 'person' ? 'receivable' : 'expense');
    _category = row?['category'] as String? ?? _categories.first;
    if (!_categories.contains(_category)) _category = _categories.last;
    for (final c in [_title, _amount, _note, _paymentSource]) { c.addListener(_changed); }
  }
  void _changed() { if (mounted && !_dirty) setState(() => _dirty = true); }
  @override
  void dispose() { _title.dispose(); _amount.dispose(); _note.dispose(); _paymentSource.dispose(); super.dispose(); }

  void _close(bool saved) {
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.pop(context, saved); });
  }
  Future<void> _exit() async {
    if (_busy || _exitDialog || _leaving) return;
    if (!_dirty) { _close(false); return; }
    _exitDialog = true;
    final discard = await showDialog<bool>(context: context,
      builder: (context) => AlertDialog(title: const Text('Discard unsaved changes?'),
        content: const Text('This money record has not been saved yet.'), actions: [
          TextButton(onPressed: () => Navigator.pop(context,false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(context,true), child: const Text('Discard')),
        ]));
    _exitDialog = false;
    if (discard == true && mounted) _close(false);
  }
  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final data = <String,Object?>{'title': _title.text.trim(), 'amount': parseMoney(_amount.text)!,
        'entry_date': MoneyDatabase.day(_date), 'note': _note.text.trim()};
      if (widget.type != 'bill') data['flow'] = _flow;
      if (widget.type == 'transaction') {
        data['category'] = _category;
        data['payment_method'] = _flow == 'expense' ? _paymentMethod : '';
        data['payment_source'] = _flow == 'expense' && _paymentMethod != 'Cash'
          ? _paymentSource.text.trim() : '';
      }
      await MoneyDatabase.instance.save(widget.type, data, id: widget.row?['id'] as int?);
      if (mounted) _close(true);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not save. Your input is still here. A bill payment must be edited from Bills.')));
    } finally { if (mounted && !_leaving) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => Theme(data: moneyTheme(context), child: Builder(builder: _buildEditor));
  Widget _buildEditor(BuildContext context) {
    final person = widget.type == 'person';
    final bill = widget.type == 'bill';
    return PopScope(canPop: _leaving,
      onPopInvokedWithResult: (didPop,result) { if (!didPop) _exit(); },
      child: Scaffold(
        appBar: AppBar(title: Text('${widget.row == null ? 'Add' : 'Edit'} ${bill ? 'bill' : person ? 'balance' : 'transaction'}'),
          actions: [Padding(padding: const EdgeInsets.only(right: 12),
            child: FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save')))]),
        body: SafeArea(top: false, child: AbsorbPointer(absorbing: _busy,
          child: Form(key: _form, child: ListView(padding: const EdgeInsets.all(20), children: [
            if (!bill) ...[
              DropdownButtonFormField<String>(value: _flow, isExpanded: true,
                decoration: const InputDecoration(labelText: 'Type'),
                items: person ? const [
                  DropdownMenuItem(value: 'receivable', child: Text('Someone owes me')),
                  DropdownMenuItem(value: 'payable', child: Text('I owe someone')),
                ] : const [
                  DropdownMenuItem(value: 'expense', child: Text('Expense')),
                  DropdownMenuItem(value: 'income', child: Text('Income')),
                ],
                onChanged: (v) { if(v==null)return; setState(() {
                  _flow=v; _category=_categories.first; _dirty=true;
                }); }),
              const SizedBox(height: 18),
            ],
            TextFormField(controller: _amount, autofocus: widget.row == null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w500),
              decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', hintText: '0.00',
                helperText: 'Up to 2 decimal places. Maximum ₹1,00,00,00,000.'),
              validator: (v) => parseMoney(v ?? '') == null ? 'Enter a positive amount with up to 2 decimals.' : null),
            const SizedBox(height: 18),
            TextFormField(controller: _title, maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: bill ? 'Bill name' : person ? 'Person’s name' : 'Description',
                hintText: bill ? 'Electricity, rent, internet…' : person ? 'Who is this balance with?' : 'What was this for?'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Enter a name or description.' : null),
            if (!bill && !person) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(key: ValueKey(_flow), value: _category,
                isExpanded: true, decoration: const InputDecoration(labelText: 'Category'),
                items: [for(final c in _categories) DropdownMenuItem(value:c,child:Text(c))],
                onChanged: (v) { if(v!=null)setState(() { _category=v; _dirty=true; }); }),
              const SizedBox(height: 18),
            ],
            if (!bill && !person && _flow == 'expense') ...[
              DropdownButtonFormField<String>(
                value: _paymentMethod.isEmpty ? null : _paymentMethod,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Payment method', hintText: 'How did you pay?'),
                items: [for (final method in _paymentMethods)
                  DropdownMenuItem(value: method, child: Text(method))],
                validator: (value) => value == null || value.isEmpty ? 'Choose a payment method.' : null,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() { _paymentMethod = value; _paymentSource.clear(); _dirty = true; });
                },
              ),
              const SizedBox(height: 18),
              if (_paymentMethod.isNotEmpty && _paymentMethod != 'Cash') ...[
                TextFormField(
                  key: ValueKey('source-$_paymentMethod'),
                  controller: _paymentSource,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: switch (_paymentMethod) {
                      'UPI' => 'UPI app', 'Card' => 'Card name',
                      'Bank' => 'Bank / account name', _ => 'Payment source',
                    },
                    hintText: switch (_paymentMethod) {
                      'UPI' => 'PhonePe, Google Pay, Paytm…',
                      'Card' => 'HDFC credit card, SBI debit card…',
                      'Bank' => 'SBI savings, ICICI account…', _ => 'Name this payment source',
                    },
                    helperText: _paymentMethod == 'UPI' ? 'Enter the app you used.' : 'Use a nickname, not a full card or account number.',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter the payment source.' : null,
                ),
                const SizedBox(height: 8),
              ],
            ],
            OutlinedButton.icon(icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text('${bill ? 'Due' : 'Date'} · ${MaterialLocalizations.of(context).formatMediumDate(_date)}'),
              onPressed: () async {
                final picked=await showDatePicker(context:context,initialDate:_date,
                  firstDate:DateTime(1900),lastDate:DateTime(2100,12,31));
                if(picked!=null && mounted)setState(() { _date=picked; _dirty=true; });
              }),
            const SizedBox(height: 18),
            TextFormField(controller:_note,minLines:3,maxLines:5,maxLength:500,
              textCapitalization:TextCapitalization.sentences,
              decoration:const InputDecoration(labelText:'Note (optional)',alignLabelWithHint:true)),
            if(person) const Padding(padding:EdgeInsets.symmetric(vertical:12),
              child:Text('A balance tracks what is owed. It does not add income or expenses automatically.',
                style:TextStyle(fontSize:12,height:1.6))),
            if(bill) const Padding(padding:EdgeInsets.symmetric(vertical:12),
              child:Text('The bill stays unpaid until you record its payment from the Bills tab. This adds one expense.',
                style:TextStyle(fontSize:12,height:1.6))),
            const SizedBox(height:20),
            FilledButton.icon(onPressed:_busy?null:_save,icon:const Icon(Icons.check),
              label:Text(_busy?'Saving…':'Save record')),
          ])),
        )),
      ));
  }
}
