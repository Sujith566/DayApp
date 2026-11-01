import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;

import 'dart:convert';

import 'journal_database.dart';

q.Document journalDocument(JournalEntry? entry) {
  if (entry?.richText != null && entry!.richText!.isNotEmpty) {
    // Do not silently replace malformed rich text with plain text on save.
    return q.Document.fromJson(jsonDecode(entry.richText!) as List);
  }
  final text = entry?.content ?? '';
  return q.Document.fromJson([
    {'insert': text.endsWith('\n') ? text : '$text\n'},
  ]);
}

class JournalRichReader extends StatefulWidget {
  final JournalEntry entry;
  const JournalRichReader({super.key, required this.entry});
  @override
  State<JournalRichReader> createState() => _JournalRichReaderState();
}

class _JournalRichReaderState extends State<JournalRichReader> {
  q.QuillController? controller;
  @override
  void initState() {
    super.initState();
    try {
      controller = q.QuillController(
        document: journalDocument(widget.entry),
        selection: const TextSelection.collapsed(offset: 0),
      )..readOnly = true;
    } catch (_) {
      // Reader fallback preserves the original rich data in the database.
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null) return SelectableText(widget.entry.content);
    return q.QuillEditor.basic(
      controller: controller!,
      config: const q.QuillEditorConfig(
        scrollable: false,
        autoFocus: false,
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class JournalMonth extends StatelessWidget {
  final DateTime month, selected;
  final Set<String> markedDates;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<int> onMonth;
  const JournalMonth({
    super.key,
    required this.month,
    required this.selected,
    required this.markedDates,
    required this.onSelect,
    required this.onMonth,
  });

  static String dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final offset = first.weekday - 1;
    final cells = ((offset + days + 6) ~/ 7) * 7;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: month.year == 1900 && month.month == 1
                      ? null
                      : () => onMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    MaterialLocalizations.of(context).formatMonthYear(month),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: month.year == 2100 && month.month == 12
                      ? null
                      : () => onMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Row(
              children: [
                for (final day in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(day, textAlign: TextAlign.center),
                    ),
                  ),
              ],
            ),
            for (var row = 0; row < cells ~/ 7; row++)
              Row(
                children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final day = row * 7 + col - offset + 1;
                          if (day < 1 || day > days)
                            return const SizedBox(height: 48);
                          final date = DateTime(month.year, month.month, day);
                          final active = DateUtils.isSameDay(date, selected);
                          final marked = markedDates.contains(dayKey(date));
                          return Semantics(
                            label:
                                '${MaterialLocalizations.of(context).formatFullDate(date)}${marked ? ', has entries' : ''}',
                            selected: active,
                            child: InkWell(
                              onTap: () => onSelect(date),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 48,
                                ),
                                margin: const EdgeInsets.all(1),
                                decoration: BoxDecoration(
                                  color: active
                                      ? colors.primaryContainer
                                      : null,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '$day',
                                      style: TextStyle(
                                        color: active
                                            ? colors.onPrimaryContainer
                                            : colors.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Container(
                                      width: 4,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: marked
                                            ? (active
                                                  ? colors.onPrimaryContainer
                                                  : colors.primary)
                                            : Colors.transparent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

void showJournalAiStatus(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Journal AI is not configured',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'Offline speech recognition, writing polish, and summaries '
              'will need a separate local model integration. Nothing is sent to a server. '
              'Your journal works without AI.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    ),
  );
}

ThemeData journalTheme(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final base = Theme.of(context);
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xFF174F43),
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: dark ? const Color(0xFF9ED7C0) : const Color(0xFF174F43),
    onPrimary: dark ? const Color(0xFF103D31) : Colors.white,
    surface: dark ? const Color(0xFF17211E) : const Color(0xFFFCFAF5),
    surfaceContainerHighest: dark ? const Color(0xFF26332E) : const Color(0xFFEEEDE7),
    onSurface: dark ? const Color(0xFFECEEE7) : const Color(0xFF172A27),
    onSurfaceVariant: dark ? const Color(0xFFB8C4BC) : const Color(0xFF747B80),
    outlineVariant: dark ? const Color(0xFF35443D) : const Color(0xFFE8E6DE),
    secondaryContainer: dark ? const Color(0xFF4A3D21) : const Color(0xFFFFF0D5),
    onSecondaryContainer: dark ? const Color(0xFFFFDDA5) : const Color(0xFFA26719),
  );
  return base.copyWith(
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    appBarTheme: AppBarTheme(backgroundColor: colors.surface,
      foregroundColor: colors.onSurface, elevation: 0, scrolledUnderElevation: 0,
      centerTitle: false),
    cardTheme: CardThemeData(color: colors.surface, elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant))),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colors.primary, foregroundColor: colors.onPrimary,
      elevation: 3, shape: const StadiumBorder()),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: colors.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.primary)),
    ),
  );
}

class JournalWeek extends StatelessWidget {
  final DateTime month, selected;
  final Set<String> markedDates;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<int> onMonth;
  final VoidCallback onExpand;
  const JournalWeek({super.key, required this.month, required this.selected,
    required this.markedDates, required this.onSelect, required this.onMonth,
    required this.onExpand});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final monday = DateTime(selected.year, selected.month, selected.day - selected.weekday + 1);
    return Column(children: [
      Row(children: [
        IconButton(tooltip: 'Previous month',
          onPressed: month.year == 1900 && month.month == 1 ? null : () => onMonth(-1),
          icon: const Icon(Icons.chevron_left, size: 20)),
        Expanded(child: TextButton(onPressed: onExpand,
          child: Text(MaterialLocalizations.of(context).formatMonthYear(month),
            style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w600)))),
        IconButton(tooltip: 'Next month',
          onPressed: month.year == 2100 && month.month == 12 ? null : () => onMonth(1),
          icon: const Icon(Icons.chevron_right, size: 20)),
      ]),
      Row(children: [for (var i = 0; i < 7; i++) Expanded(child: Builder(builder: (context) {
        final d = DateTime(monday.year, monday.month, monday.day + i);
        final active = DateUtils.isSameDay(d, selected);
        final marked = markedDates.contains(JournalMonth.dayKey(d));
        return Semantics(selected: active,
          label: '${MaterialLocalizations.of(context).formatFullDate(d)}${marked ? ', has entries' : ''}',
          child: InkWell(borderRadius: BorderRadius.circular(12),
            onTap: d.year < 1900 || d.year > 2100 ? null : () => onSelect(d),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                Text(const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i],
                  style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
                const SizedBox(height: 6),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  decoration: BoxDecoration(color: active ? colors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(9)),
                  child: Text('${d.day}', style: TextStyle(fontWeight: FontWeight.w600,
                    color: active ? colors.onPrimary : colors.onSurface))),
                const SizedBox(height: 5),
                Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle,
                  color: marked ? colors.primary : Colors.transparent)),
              ])),
          ));
      }))]),
    ]);
  }
}
