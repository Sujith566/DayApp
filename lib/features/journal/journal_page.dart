import 'package:flutter/material.dart';

import 'journal_database.dart';
import 'journal_editor.dart';
import 'journal_photos.dart';
import 'journal_widgets.dart';

class JournalPage extends StatefulWidget {
  const JournalPage({super.key});
  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  final _db = JournalDatabase.instance;
  final _search = TextEditingController();
  List<JournalEntry> _entries = [];
  List<JournalDraft> _drafts = [];
  bool _loading = true, _trash = false, _calendar = false;
  bool _showSearch = false;
  String? _error, _recoveryWarning;
  String _scope = 'all', _mood = '', _tag = '';
  int _view = 0;
  int _loadGeneration = 0;
  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());
  late DateTime _month = DateTime(_selectedDate.year, _selectedDate.month);
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    _search.addListener(_searchChanged);
    _start();
  }

  Future<void> _start() async {
    try {
      await JournalPhotos.recoverPicker();
    } catch (_) {
      _recoveryWarning =
          'Photo recovery could not finish. Existing entries are safe; '
          'check recovered drafts before choosing photos again.';
    }
    await _load();
  }

  void _searchChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    final trash = _trash;
    setState(() { _loading = true; _error = null; });
    try {
      final entries = await _db.getEntries(trash: trash);
      final drafts = await _db.drafts();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _entries = entries;
        _drafts = drafts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your journal. Pull down to retry.';
      });
    }
  }

  Future<void> _cleanFiles() async {
    try {
      await JournalPhotos.removeUnused();
    } catch (_) {
      _message(
        'Saved successfully, but unused-photo cleanup needs a later retry.',
      );
    }
  }

  void _message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirm(String title, String text) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(text),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _edit({JournalEntry? entry, JournalDraft? draft}) async {
    try {
      if (entry != null && draft == null)
        draft = await _db.draft('entry_${entry.id}');
      if (!mounted) return;
      if (entry != null &&
          draft != null &&
          draft.data['baseUpdatedAt'] != entry.updatedAt) {
        _message(
          'This draft belongs to an older entry version. Discard it from Drafts '
          'before editing the newer entry.',
        );
        return;
      }
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => JournalEditor(
            entry: entry,
            draft: draft,
            initialDate: _scope == 'day' ? _selectedDate : DateTime.now(),
          ),
        ),
      );
      if (!mounted) return;
      await _load();
      if (_recoveryWarning == null) await _cleanFiles();
    } catch (_) {
      _message('Could not open this entry. Its stored data is unchanged.');
    }
  }

  Future<void> _resume(JournalDraft draft) async {
    final id = draft.data['entryId'] as int?;
    if (id == null) {
      await _edit(draft: draft);
      return;
    }
    try {
      final entry = await _db.getEntry(id);
      if (entry == null || entry.deletedAt != null) {
        _message(
          'The original entry is unavailable. Keep the draft until you recover it.',
        );
        return;
      }
      await _edit(entry: entry, draft: draft);
    } catch (_) {
      _message('Could not load this draft.');
    }
  }

  Future<void> _action(JournalEntry entry, String action) async {
    if (action == 'edit') {
      await _edit(entry: entry);
      return;
    }
    if (action == 'trash' &&
        !await _confirm(
          'Move to trash?',
          'You can restore this entry later. Any unsaved draft for this entry will be removed.',
        ))
      return;
    if (action == 'delete' &&
        !await _confirm(
          'Delete permanently?',
          'This removes the entry and its unreferenced photos. This cannot be undone.',
        ))
      return;
    try {
      if (action == 'trash') await _db.trash(entry.id!);
      if (action == 'restore') await _db.restore(entry.id!);
      if (action == 'delete') await _db.permanentlyDelete(entry.id!);
      await _load();
      if (_recoveryWarning == null) await _cleanFiles();
    } catch (_) {
      _message('Could not complete this action. Retry.');
    }
  }

  List<JournalEntry> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return _entries.where((entry) {
      final date = DateUtils.dateOnly(entry.date);
      final matchesDate = switch (_scope) {
        'day' => DateUtils.isSameDay(date, _selectedDate),
        'month' => date.year == _month.year && date.month == _month.month,
        'range' =>
          _range == null ||
              (!date.isBefore(DateUtils.dateOnly(_range!.start)) &&
                  !date.isAfter(DateUtils.dateOnly(_range!.end))),
        _ => true,
      };
      final matchesView = switch (_view) {
        1 => entry.improvement.trim().isNotEmpty,
        2 => entry.reflection.trim().isNotEmpty,
        _ => true,
      };
      final text = [
        entry.title,
        entry.content,
        entry.improvement,
        entry.reflection,
        entry.mood,
        ...entry.tags,
        ...entry.photos.map((photo) => photo.caption),
      ].join('\n').toLowerCase();
      return matchesDate &&
          matchesView &&
          (_mood.isEmpty || entry.mood == _mood) &&
          (_tag.isEmpty || entry.tags.contains(_tag)) &&
          (query.isEmpty || text.contains(query));
    }).toList();
  }

  Future<void> _chooseScope(String value) async {
    if (value == 'range') {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime(2100, 12, 31),
        initialDateRange: _range,
      );
      if (range == null || !mounted) return;
      setState(() {
        _range = range;
        _scope = 'range';
      });
    } else {
      setState(() {
        _scope = value;
        if (value == 'day') {
          _selectedDate = DateUtils.dateOnly(DateTime.now());
          _month = DateTime(_selectedDate.year, _selectedDate.month);
        }
      });
    }
  }

  void _reset() {
    _search.clear();
    setState(() { _scope = 'all'; _mood = ''; _tag = ''; _view = 0; });
  }

  Future<void> _menu(String value) async {
    if (value == 'trash') {
      setState(() => _trash = !_trash);
      await _load();
    } else if (value == 'calendar') {
      setState(() {
        _calendar = !_calendar;
        if (_selectedDate.year != _month.year || _selectedDate.month != _month.month) {
          _selectedDate = DateTime(_month.year, _month.month);
        }
      });
    } else if (value == 'reset') {
      _reset();
    } else if (value == 'ai') {
      showJournalAiStatus(context);
    } else {
      await _chooseScope(value);
    }
  }

  void _changeMonth(int offset) {
    final next = DateTime(_month.year, _month.month + offset);
    if (next.year < 1900 || next.year > 2100) return;
    setState(() {
      final last = DateTime(next.year, next.month + 1, 0).day;
      _selectedDate = DateTime(next.year, next.month, _selectedDate.day.clamp(1, last).toInt());
      _month = next;
      _scope = 'month';
    });
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      _month = DateTime(date.year, date.month);
      _scope = 'day';
    });
  }

  List<PopupMenuEntry<String>> _menuItems() => [
    PopupMenuItem(value: 'calendar', child: Text(_calendar ? 'Compact calendar' : 'Full calendar')),
    const PopupMenuDivider(),
    const PopupMenuItem(value: 'all', child: Text('All entries')),
    const PopupMenuItem(value: 'day', child: Text('Today')),
    const PopupMenuItem(value: 'month', child: Text('Displayed month')),
    const PopupMenuItem(value: 'range', child: Text('Choose date range')),
    const PopupMenuDivider(),
    PopupMenuItem(value: 'trash', child: Text(_trash ? 'Back to journal' : 'Trash')),
    const PopupMenuItem(value: 'reset', child: Text('Reset filters')),
    const PopupMenuItem(value: 'ai', child: Text('AI status')),
  ];

  Widget _entryCard(BuildContext context, JournalEntry entry) {
    final colors = Theme.of(context).colorScheme;
    final excerpt = switch (_view) {
      1 => entry.improvement,
      2 => entry.reflection,
      _ => entry.content,
    };
    return Card(
      key: ValueKey(entry.id),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _trash ? null : () async {
          final result = await Navigator.of(context).push<String>(
            MaterialPageRoute(builder: (_) => JournalDetail(entry: entry)),
          );
          if (mounted && result != null) await _action(entry, result);
        },
        child: Padding(padding: const EdgeInsets.fromLTRB(14, 4, 10, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Wrap(spacing: 10, runSpacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(MaterialLocalizations.of(context).formatMediumDate(entry.date),
                    style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                  if (entry.mood.isNotEmpty) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(20)),
                    child: Text(entry.mood, style: TextStyle(fontSize: 11,
                      color: colors.onSecondaryContainer))),
                ])),
              PopupMenuButton<String>(tooltip: 'Entry actions',
                onSelected: (action) => _action(entry, action),
                itemBuilder: (_) => _trash ? const [
                  PopupMenuItem(value: 'restore', child: Text('Restore')),
                  PopupMenuItem(value: 'delete', child: Text('Delete permanently')),
                ] : const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'trash', child: Text('Move to trash')),
                ]),
            ]),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                    height: 1.35, color: colors.onSurface)),
                if (excerpt.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(excerpt, maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, height: 1.6, color: colors.onSurfaceVariant)),
                ],
              ])),
              if (entry.photos.isNotEmpty) ...[
                const SizedBox(width: 12),
                SizedBox(width: 76, child: Stack(children: [
                  JournalPhotoView(photo: entry.photos.first, height: 84),
                  if (entry.photos.length > 1) Positioned(bottom: 4, right: 4,
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black54,
                        borderRadius: BorderRadius.circular(6)),
                      child: Text('+${entry.photos.length - 1}',
                        style: const TextStyle(fontSize: 10, color: Colors.white)))),
                ])),
              ],
            ]),
            if (entry.tags.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10),
              child: Text(entry.tags.take(3).map((t) => '#$t').join('  '),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: colors.primary))),
          ])),
      ),
    );
  }

  Widget _tabs(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(28)),
      child: Row(children: [
        for (final item in const [(0, 'Entries'), (1, 'Improvements'), (2, 'Reflections')])
          Expanded(child: Semantics(selected: _view == item.$1, button: true,
            child: Material(color: _view == item.$1 ? colors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(borderRadius: BorderRadius.circular(24),
                onTap: () => setState(() => _view = item.$1),
                child: Padding(padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 3),
                  child: Text(item.$2, textAlign: TextAlign.center, softWrap: true,
                    style: TextStyle(fontSize: 12, fontWeight: _view == item.$1
                      ? FontWeight.w600 : FontWeight.w400,
                      color: _view == item.$1 ? colors.onPrimary : colors.onSurfaceVariant))),
              ),
            ),
          )),
      ]),
    );
  }

  String _scopeLabel(BuildContext context) {
    final l = MaterialLocalizations.of(context);
    return switch (_scope) {
      'day' => l.formatMediumDate(_selectedDate),
      'month' => l.formatMonthYear(_month),
      'range' => _range == null ? 'Date range' :
        '${l.formatShortDate(_range!.start)} – ${l.formatShortDate(_range!.end)}',
      _ => 'All dates',
    };
  }

  Widget _draftsCard() => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: ExpansionTile(
      leading: const Icon(Icons.edit_note_outlined),
      title: Text('Continue writing · ${_drafts.length}',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: const Text('Drafts saved on this device', style: TextStyle(fontSize: 11)),
      children: [for (final draft in _drafts) ListTile(
        title: Text((draft.data['title'] as String? ?? '').trim().isEmpty
          ? 'Untitled draft' : draft.data['title'] as String),
        onTap: () => _resume(draft),
        trailing: IconButton(tooltip: 'Discard draft', icon: const Icon(Icons.close),
          onPressed: () async {
            if (!await _confirm('Discard draft?', 'The saved entry, if any, is kept.')) return;
            try {
              await _db.removeDraft(draft.key);
              await _load();
              if (_recoveryWarning == null) await _cleanFiles();
            } catch (_) { _message('Could not discard draft.'); }
          }),
      )],
    ),
  );

  @override
  Widget build(BuildContext context) => Theme(
    data: journalTheme(context), child: Builder(builder: _buildPage));

  Widget _buildPage(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final entries = _filtered;
    final tags = _entries.expand((e) => e.tags).toSet().toList()..sort();
    final marked = _entries.map((e) => JournalMonth.dayKey(e.date)).toSet();
    final filtered = _scope != 'all' || _mood.isNotEmpty || _tag.isNotEmpty || _search.text.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: Text(_trash ? 'Trash' : 'Journal', style: const TextStyle(
          fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.7)),
        actions: [
          IconButton(tooltip: _showSearch ? 'Close search' : 'Search journal',
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) _search.clear();
            })),
          PopupMenuButton<String>(tooltip: 'Journal options',
            onSelected: _menu, itemBuilder: (_) => _menuItems()),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _trash ? null : FloatingActionButton.extended(
        onPressed: () => _edit(), icon: const Icon(Icons.edit_outlined, size: 19),
        label: const Text('Write entry')),
      body: SafeArea(top: false, child: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: SliverToBoxAdapter(child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_showSearch) ...[
                  const SizedBox(height: 8),
                  TextField(controller: _search, autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(hintText: 'Search memories, moods, tags…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty ? null : IconButton(tooltip: 'Clear search',
                        onPressed: _search.clear, icon: const Icon(Icons.close)))),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    PopupMenuButton<String>(
                      onSelected: (v) => setState(() => _mood = v),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: '', child: Text('Any mood')),
                        for (final m in journalMoods) PopupMenuItem(value: m, child: Text(m)),
                      ], child: Chip(label: Text(_mood.isEmpty ? 'Mood ▾' : '$_mood ▾'))),
                    PopupMenuButton<String>(
                      onSelected: (v) => setState(() => _tag = v),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: '', child: Text('Any tag')),
                        for (final t in tags) PopupMenuItem(value: t, child: Text(t)),
                      ], child: Chip(label: Text(_tag.isEmpty ? 'Tag ▾' : '$_tag ▾'))),
                  ]),
                ],
                if (_calendar) JournalMonth(
                  month: _month, selected: _selectedDate, markedDates: marked,
                  onSelect: _selectDate, onMonth: _changeMonth,
                ) else JournalWeek(
                  month: _month, selected: _selectedDate, markedDates: marked,
                  onExpand: () => setState(() => _calendar = true),
                  onSelect: _selectDate, onMonth: _changeMonth,
                ),
                const SizedBox(height: 14),
                _tabs(context),
                const SizedBox(height: 14),
                if (filtered) Wrap(spacing: 6, runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if (_scope != 'all') Chip(label: Text(_scopeLabel(context))),
                    if (_mood.isNotEmpty) InputChip(label: Text(_mood),
                      onDeleted: () => setState(() => _mood = '')),
                    if (_tag.isNotEmpty) InputChip(label: Text('#$_tag'),
                      onDeleted: () => setState(() => _tag = '')),
                    TextButton(onPressed: _reset, child: const Text('Show all')),
                  ]),
                if (_trash) Padding(padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text('Entries stay here until you restore or permanently delete them.',
                    style: TextStyle(fontSize: 12, height: 1.5, color: colors.onSurfaceVariant))),
                if (_recoveryWarning != null) Padding(
                  padding: const EdgeInsets.only(bottom: 14), child: Text(_recoveryWarning!)),
                if (!_trash && _drafts.isNotEmpty) _draftsCard(),
                if (_loading) const Padding(padding: EdgeInsets.all(34),
                  child: Center(child: CircularProgressIndicator()))
                else if (_error != null) Padding(padding: const EdgeInsets.all(20),
                  child: Column(children: [Text(_error!, textAlign: TextAlign.center),
                    TextButton(onPressed: _load, child: const Text('Retry'))]))
                else if (entries.isEmpty) Padding(
                  padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 18),
                  child: Column(children: [
                    Container(padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: colors.primary.withAlpha(15),
                        shape: BoxShape.circle),
                      child: Icon(_trash ? Icons.delete_outline : Icons.menu_book_outlined,
                        size: 30, color: colors.primary)),
                    const SizedBox(height: 18),
                    Text(_trash ? 'Your trash is empty' : filtered || _view != 0
                      ? 'No entries in this view' : 'Your story starts here',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Text(_trash ? 'Removed entries will appear here.' : filtered || _view != 0
                      ? 'Try another day or show all your entries.'
                      : 'A quiet moment. A small win. Something you want to remember.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 13,
                        height: 1.7, color: colors.onSurfaceVariant)),
                    if (filtered || _view != 0) TextButton(onPressed: _reset,
                      child: const Text('Show all entries')),
                  ])),
              ]))),
            if (!_loading && _error == null && entries.isNotEmpty)
              SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(delegate: SliverChildBuilderDelegate(
                  (context, index) => _entryCard(context, entries[index]),
                  childCount: entries.length))),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      )),
    );
  }
}

class JournalDetail extends StatelessWidget {
  final JournalEntry entry;
  const JournalDetail({super.key, required this.entry});
  @override
  Widget build(BuildContext context) => Theme(
    data: journalTheme(context), child: Builder(builder: _buildDetail));

  Widget _buildDetail(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal entry'),
        actions: [
          IconButton(
            tooltip: 'Edit entry',
            onPressed: () => Navigator.pop(context, 'edit'),
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => Navigator.pop(context, value),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'trash', child: Text('Move to trash')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Text(MaterialLocalizations.of(context).formatFullDate(entry.date)),
          const SizedBox(height: 12),
          Text(entry.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (entry.mood.isNotEmpty) Chip(label: Text(entry.mood)),
              for (final tag in entry.tags) Chip(label: Text('#$tag')),
            ],
          ),
          const SizedBox(height: 16),
          JournalRichReader(entry: entry),
          if (entry.improvement.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'What I want to improve',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            SelectableText(entry.improvement),
          ],
          if (entry.reflection.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'What I would do differently',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            SelectableText(entry.reflection),
          ],
          for (final photo in entry.photos) ...[
            const SizedBox(height: 20),
            InkWell(
              onTap: () => openJournalPhoto(context, photo),
              child: JournalPhotoView(photo: photo, height: 240),
            ),
            if (photo.caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(photo.caption),
              ),
          ],
        ],
      ),
    );
  }
}
