import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:image_picker/image_picker.dart';

import 'journal_database.dart';
import 'journal_photos.dart';
import 'journal_widgets.dart';

class JournalEditor extends StatefulWidget {
  final JournalEntry? entry;
  final JournalDraft? draft;
  final DateTime? initialDate;
  const JournalEditor({super.key, this.entry, this.draft, this.initialDate});
  @override
  State<JournalEditor> createState() => _JournalEditorState();
}

class _JournalEditorState extends State<JournalEditor>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _improvement, _reflection, _tags;
  q.QuillController? _body;
  late final String _draftKey;
  late DateTime _date;
  late String _mood;
  List<JournalPhoto> _photos = [];
  bool _formatting = false;
  bool _details = false;
  Timer? _debounce;
  Future<void> _writes = Future<void>.value();
  int _revision = 0;
  bool _busy = false, _leaving = false, _exitDialog = false;
  bool _changed = false;
  String _status = 'Changes are saved as a draft';
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final entry = widget.entry;
    final data = widget.draft?.data;
    _draftKey =
        widget.draft?.key ??
        (entry?.id == null
            ? 'new_${DateTime.now().microsecondsSinceEpoch}'
            : 'entry_${entry!.id}');
    _title = TextEditingController(
      text: data?['title'] as String? ?? entry?.title ?? '',
    );
    _improvement = TextEditingController(
      text: data?['improvement'] as String? ?? entry?.improvement ?? '',
    );
    _reflection = TextEditingController(
      text: data?['reflection'] as String? ?? entry?.reflection ?? '',
    );
    _tags = TextEditingController(
      text: data?['tagsText'] as String? ?? entry?.tags.join(', ') ?? '',
    );
    _date = DateUtils.dateOnly(
      data?['date'] != null
          ? DateTime.parse(data!['date'] as String)
          : entry?.date ?? widget.initialDate ?? DateTime.now(),
    );
    _mood = data?['mood'] as String? ?? entry?.mood ?? '';
    _photos = data?['photos'] != null
        ? (data!['photos'] as List)
              .map(
                (photo) => JournalPhoto.fromJson(
                  Map<String, dynamic>.from(photo as Map),
                ),
              )
              .toList()
        : List.of(entry?.photos ?? []);
    try {
      final document = data?['delta'] != null
          ? q.Document.fromJson(data!['delta'] as List)
          : journalDocument(entry);
      _body = q.QuillController(
        document: document,
        selection: const TextSelection.collapsed(offset: 0),
        config: q.QuillControllerConfig(
          clipboardConfig: q.QuillClipboardConfig(
            onClipboardPaste: () async {
              // Photos are managed attachments. Paste text only so remote or
              // unsupported image embeds cannot enter the document.
              final value = await Clipboard.getData(Clipboard.kTextPlain);
              final body = _body;
              if (!mounted || body == null || value?.text == null) return true;
              final selection = body.selection;
              final maxOffset = body.document.length - 1;
              final start = selection.isValid
                  ? selection.start.clamp(0, maxOffset).toInt()
                  : maxOffset;
              final end = selection.isValid
                  ? selection.end.clamp(start, maxOffset).toInt()
                  : start;
              body.replaceText(
                start,
                end - start,
                value!.text!,
                TextSelection.collapsed(offset: start + value.text!.length),
              );
              return true;
            },
          ),
        ),
      );
      _body!.addListener(_bodyChanged);
    } catch (_) {
      _loadError =
          'This entry’s formatting could not be opened. '
          'The stored content has not been changed. Return and keep the original.';
    }
    for (final controller in [_title, _improvement, _reflection, _tags]) {
      controller.addListener(_markChanged);
    }
    _lastDelta = _body == null
        ? ''
        : jsonEncode(_body!.document.toDelta().toJson());
    if (widget.draft != null) _status = 'Recovered draft';
  }

  String _lastDelta = '';
  void _bodyChanged() {
    final delta = jsonEncode(_body!.document.toDelta().toJson());
    if (delta == _lastDelta) return; // Cursor changes are not edits.
    _lastDelta = delta;
    _markChanged();
  }

  Map<String, dynamic> _snapshot() => {
    'entryId': widget.entry?.id,
    'baseUpdatedAt': widget.entry?.updatedAt ?? '',
    'title': _title.text,
    'content': _body!.document.toPlainText().trim(),
    'delta': _body!.document.toDelta().toJson(),
    'improvement': _improvement.text,
    'reflection': _reflection.text,
    'tagsText': _tags.text,
    'date': _date.toIso8601String(),
    'mood': _mood,
    'photos': _photos.map((photo) => photo.toJson()).toList(),
  };

  void _markChanged() {
    if (_leaving || _body == null) return;
    _revision++;
    _changed = true;
    if (mounted) setState(() => _status = 'Unsaved changes…');
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      unawaited(_persistDraft());
    });
  }

  Future<bool> _persistDraft() {
    if (_body == null || _leaving) return Future.value(false);
    final snapshot = _snapshot();
    final revision = _revision;
    final result = Completer<bool>();
    _writes = _writes.then((_) async {
      try {
        await JournalDatabase.instance.saveDraft(_draftKey, snapshot);
        if (mounted && revision == _revision)
          setState(() => _status = 'Draft saved on device');
        result.complete(true);
      } catch (_) {
        if (mounted)
          setState(
            () =>
                _status = 'Draft save failed — keep this screen open and retry',
          );
        result.complete(false);
      }
    });
    return result.future;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused) &&
        _changed &&
        !_busy &&
        !_leaving) {
      _debounce?.cancel();
      unawaited(_persistDraft());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _body?.dispose();
    _title.dispose();
    _improvement.dispose();
    _reflection.dispose();
    _tags.dispose();
    super.dispose();
  }

  void _error(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _close() {
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  Future<void> _save() async {
    if (_busy || _body == null || !_form.currentState!.validate()) return;
    if (_body!.document.toPlainText().trim().isEmpty &&
        _improvement.text.trim().isEmpty &&
        _reflection.text.trim().isEmpty &&
        _photos.isEmpty) {
      _error('Add some writing, a reflection, or a photo.');
      return;
    }
    setState(() => _busy = true);
    _debounce?.cancel();
    try {
      await _writes;
      // Keep a recoverable draft even if the final transaction fails.
      if (!await _persistDraft()) {
        throw StateError('Draft not saved');
      }
      final tags = _tags.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .toList();
      await JournalDatabase.instance.commit(
        JournalEntry(
          id: widget.entry?.id,
          title: _title.text.trim(),
          content: _body!.document.toPlainText().trim(),
          improvement: _improvement.text.trim(),
          reflection: _reflection.text.trim(),
          date: _date,
          mood: _mood,
          tags: tags,
          photos: List.of(_photos),
          richText: jsonEncode(_body!.document.toDelta().toJson()),
        ),
        _draftKey,
      );
      if (mounted) _close();
    } catch (_) {
      _error('Could not save the entry. Your text is still here. Retry.');
    } finally {
      if (mounted && !_leaving) setState(() => _busy = false);
    }
  }

  Future<void> _exit() async {
    if (_busy || _leaving || _exitDialog) return;
    if (!_changed && widget.draft == null) {
      _close();
      return;
    }
    _exitDialog = true;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keep this draft?'),
        content: const Text(
          'Keep a draft to continue later, or discard these edits. '
          'Discard does not delete the previously saved entry.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue writing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard edits'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'keep'),
            child: const Text('Keep draft'),
          ),
        ],
      ),
    );
    _exitDialog = false;
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    _debounce?.cancel();
    try {
      await _writes;
      if (choice == 'keep') {
        if (!await _persistDraft()) throw StateError('Draft save failed');
      } else {
        await JournalDatabase.instance.removeDraft(_draftKey);
      }
      if (mounted) _close();
    } catch (_) {
      _error('Could not update your draft. Keep writing or retry.');
    } finally {
      if (mounted && !_leaving) setState(() => _busy = false);
    }
  }

  Future<void> _pickPhotos() async {
    if (_busy || _body == null) return;
    if (_photos.length >= 12) {
      _error('Use up to 12 photos per entry.');
      return;
    }
    setState(() => _busy = true);
    _debounce?.cancel();
    try {
      if (!await _persistDraft()) throw StateError('Draft save failed');
      await JournalDatabase.instance.setPickerDraft(_draftKey);
      final picked = await ImagePicker().pickMultiImage();
      for (final file in picked.take(12 - _photos.length)) {
        final photo = await JournalPhotos.importPhoto(file);
        if (!mounted) return; // Photo will be cleaned up when safe.
        _photos.add(photo);
        _markChanged();
        // Persist after each import so activity death loses fewer changes.
        if (!await _persistDraft()) throw StateError('Photo draft save failed');
      }
      await JournalDatabase.instance.setPickerDraft(null);
    } catch (_) {
      _error(
        'Photo import could not finish. Existing photos and text are kept.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _caption(int index) async {
    final controller = TextEditingController(text: _photos[index].caption);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Photo caption'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 300,
          decoration: const InputDecoration(labelText: 'Caption'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    // The dialog may still be animating out; dispose after its transition.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (result != null && mounted) {
      setState(
        () => _photos[index] = JournalPhoto(_photos[index].file, result),
      );
      _markChanged();
    }
  }

  Future<void> _chooseDate() async {
    final value = await showDatePicker(context: context, initialDate: _date,
      firstDate: DateTime(1900), lastDate: DateTime(2100, 12, 31));
    if (value != null && mounted) {
      setState(() => _date = value);
      _markChanged();
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: journalTheme(context), child: Builder(builder: _buildEditor));

  Widget _buildEditor(BuildContext context) {
    if (_loadError != null) return Scaffold(
      appBar: AppBar(title: const Text('Unable to open formatting')),
      body: Padding(padding: const EdgeInsets.all(24), child: Text(_loadError!)),
    );
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, result) { if (!didPop) _exit(); },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.entry == null ? 'New entry' : 'Edit entry',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          actions: [Padding(padding: const EdgeInsets.only(right: 12),
            child: FilledButton(onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save')))],
        ),
        body: AbsorbPointer(absorbing: _busy, child: Form(key: _form,
          child: ListView(padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              Row(children: [
                Expanded(child: Align(alignment: Alignment.centerLeft,
                  child: TextButton.icon(onPressed: _chooseDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 15),
                    label: Text(MaterialLocalizations.of(context).formatMediumDate(_date),
                      style: const TextStyle(fontSize: 12))))),
                PopupMenuButton<String>(tooltip: 'How are you feeling?',
                  onSelected: (m) { setState(() => _mood = m); _markChanged(); },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: '', child: Text('No mood')),
                    for (final mood in journalMoods) PopupMenuItem(value: mood, child: Text(mood)),
                  ],
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(24)),
                    child: Text(_mood.isEmpty ? 'Mood ＋' : '$_mood ▾',
                      style: TextStyle(fontSize: 12, color: colors.onSecondaryContainer))),
                ),
              ]),
              const SizedBox(height: 18),
              TextFormField(controller: _title,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 160, minLines: 1, maxLines: 3,
                style: TextStyle(fontSize: 29, height: 1.3,
                  fontWeight: FontWeight.w500, letterSpacing: -0.7, color: colors.onSurface),
                decoration: const InputDecoration(hintText: 'Give today a title…',
                  filled: false, counterText: '', contentPadding: EdgeInsets.zero,
                  border: InputBorder.none, enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none),
                validator: (v) => v == null || v.trim().isEmpty ? 'Enter a title.' : null,
              ),
              const SizedBox(height: 14),
              Text(_status, style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
              const SizedBox(height: 20),
              ConstrainedBox(constraints: const BoxConstraints(minHeight: 270),
                child: q.QuillEditor.basic(controller: _body!,
                  config: const q.QuillEditorConfig(scrollable: false, autoFocus: false,
                    padding: EdgeInsets.symmetric(vertical: 8),
                    placeholder: 'What happened today? Start anywhere. This space is yours.'))),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  IconButton(tooltip: 'Text formatting',
                    isSelected: _formatting,
                    onPressed: () => setState(() => _formatting = !_formatting),
                    icon: const Icon(Icons.text_format)),
                  IconButton(tooltip: 'Add photos',
                    onPressed: _photos.length >= 12 ? null : _pickPhotos,
                    icon: const Icon(Icons.add_photo_alternate_outlined)),
                  IconButton(tooltip: 'Tags and reflections',
                    isSelected: _details,
                    onPressed: () => setState(() => _details = !_details),
                    icon: const Icon(Icons.tune)),
                  const Spacer(),
                  Padding(padding: const EdgeInsets.only(right: 14),
                    child: Text('${_photos.length}/12 photos',
                      style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant))),
                ]),
              ),
              if (_formatting) Padding(padding: const EdgeInsets.only(top: 8),
                child: q.QuillSimpleToolbar(controller: _body!,
                  config: const q.QuillSimpleToolbarConfig(multiRowsDisplay: false,
                    showLink: false, showSearchButton: false, showCodeBlock: false,
                    showInlineCode: false, showQuote: false, showIndent: false,
                    showDirection: false, showAlignmentButtons: false))),
              const SizedBox(height: 20),
              for (var i = 0; i < _photos.length; i++) ...[
                ClipRRect(borderRadius: BorderRadius.circular(14),
                  child: InkWell(onTap: () => openJournalPhoto(context, _photos[i]),
                    child: JournalPhotoView(photo: _photos[i], height: 210))),
                if (_photos[i].caption.isNotEmpty) Padding(
                  padding: const EdgeInsets.only(top: 8), child: Text(_photos[i].caption)),
                Row(children: [
                  TextButton.icon(onPressed: () => _caption(i),
                    icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Caption')),
                  const Spacer(),
                  IconButton(tooltip: 'Remove photo', onPressed: () {
                    setState(() => _photos.removeAt(i)); _markChanged();
                  }, icon: const Icon(Icons.close, size: 18)),
                ]),
                const SizedBox(height: 10),
              ],
              if (_details) ...[
                Text('A little more reflection', style: TextStyle(fontSize: 18,
                  fontWeight: FontWeight.w500, color: colors.onSurface)),
                const SizedBox(height: 6),
                Text('Optional. Come back to these whenever you like.',
                  style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                const SizedBox(height: 16),
                TextField(controller: _tags, decoration: const InputDecoration(
                  labelText: 'Tags', hintText: 'work, family, learning')),
                const SizedBox(height: 14),
                TextField(controller: _improvement, minLines: 3, maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'What I want to improve',
                    alignLabelWithHint: true)),
                const SizedBox(height: 14),
                TextField(controller: _reflection, minLines: 3, maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'What I would do differently',
                    alignLabelWithHint: true)),
              ] else TextButton.icon(
                onPressed: () => setState(() => _details = true),
                icon: const Icon(Icons.spa_outlined, size: 18),
                label: const Text('Add tags or a reflection')),
            ],
          ),
        )),
      ),
    );
  }
}
