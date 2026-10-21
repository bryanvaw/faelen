import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/settings_store.dart';
import '../../../core/theme.dart';
import '../media_theme.dart';
import '../models/media_entry.dart';
import '../services/cover_service.dart';
import '../services/link_preview_service.dart';
import '../services/release_schedule.dart';
import '../services/url_progress.dart';
import '../state/media_store.dart';

/// Shows the add/edit sheet. Returns the saved entry, or null if dismissed.
/// Pass [entry] = null to add. Deleting is handled via [onDelete].
Future<MediaEntry?> showMediaForm(
  BuildContext context, {
  MediaEntry? entry,
  MediaType? initialType,
  required void Function(String id) onDelete,
}) {
  return showModalBottomSheet<MediaEntry>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _Form(entry: entry, initialType: initialType, onDelete: onDelete),
  );
}

class _Form extends StatefulWidget {
  const _Form({required this.entry, required this.initialType, required this.onDelete});
  final MediaEntry? entry;

  /// The type a new entry starts as (the tab the user came from); ignored when editing.
  final MediaType? initialType;
  final void Function(String id) onDelete;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _key = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.entry?.title);
  late final _current = TextEditingController(text: '${widget.entry?.current ?? 0}');
  late final _total = TextEditingController(text: '${widget.entry?.total ?? 0}');
  late final _notes = TextEditingController(text: widget.entry?.notes);
  late final _url = TextEditingController(text: widget.entry?.url);
  late final _released = TextEditingController(text: '${widget.entry?.releasedCount ?? 0}');
  late final Set<int> _days = {...?widget.entry?.releaseDays}; // weekdays 1-7; empty = no schedule
  late int _minutes = widget.entry?.releaseMinutes ?? -1; // reminder time; -1 = default
  Timer? _previewTimer;
  String? _previewedUrl; // last link we looked up, so editing other fields never repeats the request
  bool _previewBusy = false;
  LinkPreview? _offered; // found details that were not applied automatically (field already filled)
  bool _previewFailed = false;
  int? _detected; // number found in the link, offered as progress while it differs from the current one
  late MediaType _type = widget.entry?.type ?? widget.initialType ?? MediaType.anime;
  late Status _status = widget.entry?.status ?? Status.planToWatch;
  bool _typeChosen = false; // once the user taps a type, links never change it
  late int _season = widget.entry?.season ?? 0; // 0 = none; filled from the link when empty
  late int _rating = widget.entry?.rating ?? 0; // 0-10, shown as 5 stars with half steps
  late final String _id = widget.entry?.id ?? newId();
  late String? _cover = widget.entry?.cover;
  final _pickedCovers = <String>[]; // files created in this session, cleaned up unless saved
  bool _saved = false;
  late final CoverService _covers;

  @override
  void initState() {
    super.initState();
    _covers = context.read<MediaStore>().covers;
    // An entry that has a link but no cover quietly tries to find one when it is opened.
    final e = widget.entry;
    if (e != null && e.cover == null && e.url.isNotEmpty && _covers.available) {
      final uri = UrlProgress.normalize(e.url);
      if (uri != null) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _lookUp(uri, quiet: true) : null);
    }
  }

  bool get _isMovie => _type == MediaType.movie;
  bool get _canSchedule => !_isMovie;

  @override
  void dispose() {
    _previewTimer?.cancel();
    for (final c in [_title, _current, _total, _notes, _url, _released]) {
      c.dispose();
    }
    if (!_saved) {
      // Dismissed: drop any cover picked in this session.
      for (final f in _pickedCovers) {
        _covers.delete(f);
      }
    }
    super.dispose();
  }

  Future<void> _pickCover() async {
    try {
      final name = await _covers.pick(_id);
      if (name == null || !mounted) return;
      if (_cover != null && _pickedCovers.remove(_cover)) _covers.delete(_cover); // replaced a cover picked earlier
      _pickedCovers.add(name);
      setState(() => _cover = name);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not load that image')));
    }
  }

  void _submit() {
    if (!_key.currentState!.validate()) return;
    _saved = true;
    final old0 = widget.entry;
    final days = _canSchedule ? (_days.toList()..sort()) : <int>[];
    final scheduled = days.isNotEmpty;
    final releasedCount = scheduled ? int.parse(_released.text) : 0;
    // Counting restarts from today only when the schedule was just set or its numbers were edited.
    final unchanged = old0 != null &&
        listEquals(old0.releaseDays, days) &&
        old0.releasedCount == releasedCount &&
        old0.releasedOn != 0;
    final releasedOn = !scheduled
        ? 0
        : unchanged
            ? old0.releasedOn
            : DateTime.now().millisecondsSinceEpoch;
    final old = widget.entry?.cover;
    if (old != null && old != _cover) _covers.delete(old);
    for (final f in _pickedCovers) {
      if (f != _cover) _covers.delete(f);
    }
    Navigator.pop(
      context,
      MediaEntry(
        id: _id,
        title: _title.text.trim(),
        type: _type,
        status: _status,
        // Movies have no episodes/chapters.
        current: _isMovie ? 0 : int.parse(_current.text),
        total: _isMovie ? 0 : int.parse(_total.text),
        rating: _rating,
        notes: _notes.text,
        updatedAt: widget.entry?.updatedAt ?? 0,
        cover: _cover,
        url: UrlProgress.normalize(_url.text)?.toString() ?? '',
        season: _isMovie ? 0 : _season,
        releaseDays: days,
        releaseMinutes: scheduled ? _minutes : -1,
        releasedCount: releasedCount,
        releasedOn: releasedOn,
      ),
    );
  }

  void _onUrlChanged(String v) {
    _previewTimer?.cancel();
    // A reading link (chapter/manga/webtoon) on a new entry means Webtoon, unless the user already chose.
    if (widget.entry == null && !_typeChosen) {
      final guess = TypeGuess.fromUrl(v);
      if (guess != null) _type = guess;
    }
    final uri = UrlProgress.normalize(v);
    if (uri == null) {
      setState(() {
        _offered = null;
        _previewFailed = false;
      });
    } else if (uri.toString() != _previewedUrl) {
      // Wait for the typing/pasting to settle before touching the network.
      _previewTimer = Timer(const Duration(milliseconds: 800), () => _lookUp(uri));
    }
    final fromLink = _isMovie ? null : SeasonDetect.fromUrl(v);
    if (fromLink != null && _season == 0) _season = fromLink;
    final n = _isMovie ? null : UrlProgress.detect(v);
    final total = int.tryParse(_total.text) ?? 0;
    final usable = n != null && (total == 0 || n <= total);
    if (usable && context.read<SettingsStore>().autoUrlProgress) {
      _applyDetected(n);
      return;
    }
    setState(() => _detected = usable && n != (int.tryParse(_current.text) ?? 0) ? n : null);
  }

  /// Reads the page's title and cover. Empty title/cover are filled in; ones the user already
  /// has are kept and offered as buttons instead.
  Future<void> _lookUp(Uri uri, {bool quiet = false}) async {
    _previewedUrl = uri.toString();
    setState(() {
      _previewBusy = true;
      _previewFailed = false;
      _noCover = false;
      _offered = null;
    });
    try {
      final service = context.read<LinkPreviewService>();
      final found = await service.preview(uri);
      if (!mounted || _previewedUrl != uri.toString()) return;
      if (found == null) {
        setState(() {
          _previewBusy = false;
          _previewFailed = !quiet;
        });
        return;
      }
      final fromTitle = _isMovie ? null : SeasonDetect.fromText(found.title);
      if (!quiet && fromTitle != null && _season == 0) setState(() => _season = fromTitle);
      var titleKept = false, coverKept = false, needCatalog = found.imageUrl == null;
      if (_title.text.trim().isEmpty) {
        _title.text = found.title;
      } else {
        titleKept = _title.text.trim() != found.title;
      }
      if (found.imageUrl != null) {
        if (_cover == null && _covers.available) {
          // A page image that cannot be downloaded (blocked, not a picture) is not worth offering.
          needCatalog = !await _applyCover(service, found.imageUrl!);
        } else {
          coverKept = _covers.available;
        }
      }
      if (needCatalog && _cover == null && _covers.available) {
        // The page has no cover of its own (a single-page app). Try the show's catalogue entry by title.
        final match = await service.findInCatalog(found.title, _type);
        if (!mounted || _previewedUrl != uri.toString()) return;
        if (match != null) {
          if (_cover == null && match.image != null) await _applyCover(service, match.image!);
          final total = int.tryParse(_total.text) ?? 0;
          if (total == 0 && match.total > 0 && !_isMovie && mounted) _total.text = '${match.total}';
        }
      }
      if (!mounted) return;
      setState(() {
        _previewBusy = false;
        _noCover = _covers.available && _cover == null;
        _offered = (!quiet && (titleKept || coverKept)) ? found : null;
        _offeredTitle = titleKept;
        _offeredCover = coverKept;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _previewBusy = false;
          _previewFailed = !quiet;
        });
      }
    }
  }

  bool _noCover = false; // a link was read but no cover could be found for it
  bool _offeredTitle = false;
  bool _offeredCover = false;

  /// Downloads [url] as this entry's cover. Returns false if it could not be used.
  Future<bool> _applyCover(LinkPreviewService service, Uri url) async {
    final bytes = await service.downloadImage(url);
    if (bytes == null || !mounted) return false;
    final name = await _covers.saveBytes(_id, bytes);
    if (name == null || !mounted) return false;
    if (_cover != null && _pickedCovers.remove(_cover)) _covers.delete(_cover);
    _pickedCovers.add(name);
    setState(() => _cover = name);
    return true;
  }

  void _applyDetected(int n) {
    _current.text = '$n';
    // Progress from a link means you have started it.
    if (_status == Status.planToWatch) _status = Status.watching;
    setState(() => _detected = null);
  }

  void _setStatus(Status s) {
    setState(() => _status = s);
    // Completed with a known total: jump to the end.
    final total = int.tryParse(_total.text) ?? 0;
    if (s == Status.completed && total > 0 && !_isMovie) _current.text = '$total';
  }

  Future<void> _pickTime() async {
    final cur = _minutes >= 0 ? _minutes : context.read<SettingsStore>().defaultReminderMinutes;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60));
    if (t != null && mounted) setState(() => _minutes = t.hour * 60 + t.minute);
  }

  void _toggleDay(int d) => setState(() => _days.contains(d) ? _days.remove(d) : _days.add(d));

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final isEdit = widget.entry != null;
    final shownMinutes = _minutes >= 0 ? _minutes : context.read<SettingsStore>().defaultReminderMinutes;
    final timeLabel = TimeOfDay(hour: shownMinutes ~/ 60, minute: shownMinutes % 60).format(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.94),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Form(
                key: _key,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Text(isEdit ? 'Edit entry' : 'Add entry', style: heading(22, weight: FontWeight.w700, color: p.text)),
                    const Spacer(),
                    if (isEdit)
                      IconButton(
                        tooltip: 'Delete entry',
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onDelete(widget.entry!.id);
                        },
                        icon: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (_covers.available) ...[
                      _CoverPicker(
                        file: _covers.fileFor(_cover),
                        onPick: _pickCover,
                        onRemove: _cover == null ? null : () => setState(() => _cover = null),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: TextFormField(
                        controller: _title,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Title'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                      ),
                    ),
                  ]),
                  if (kIsWeb)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Covers and link lookups only work in the phone or desktop app, not in the browser.',
                          style: TextStyle(color: p.subText, fontSize: 12.5)),
                    ),
                  const SizedBox(height: 14),
                  Row(children: [
                    for (final t in MediaType.values) ...[
                      if (t != MediaType.values.first) const SizedBox(width: 6),
                      Expanded(
                        child: _ChoiceChip(
                          label: t.label,
                          icon: typeIcon(t),
                          color: typeColor(t),
                          selected: _type == t,
                          stacked: true,
                          onTap: () => setState(() {
                            _type = t;
                            _typeChosen = true;
                          }),
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    for (final s in Status.values) ...[
                      if (s != Status.values.first) const SizedBox(width: 6),
                      Expanded(
                        child: _ChoiceChip(
                          label: s.label,
                          shortLabel: _shortStatus[s],
                          icon: statusIcon(s),
                          color: statusColor(s),
                          selected: _status == s,
                          stacked: true,
                          onTap: () => _setStatus(s),
                        ),
                      ),
                    ],
                  ]),
                  if (!_isMovie) ...[
                    _Label('Progress', action: _SeasonPill(season: _season, onChanged: (v) => setState(() => _season = v))),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: _Stepper(controller: _current, label: 'Current ${_type.unit}', onChanged: () => setState(() {}))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Stepper(
                          controller: _total,
                          label: 'Total (0 = ?)',
                          onChanged: () => setState(() {}),
                          extra: (n) => n > 0 && (int.tryParse(_current.text) ?? 0) > n ? 'Less than current' : null,
                        ),
                      ),
                    ]),
                  ],
                  if (_canSchedule) ...[
                    _Label('Release days', trailing: _days.isEmpty ? 'No schedule' : describeDays(_days.toList()..sort())),
                    Row(children: [
                      for (var d = 1; d <= 7; d++) ...[
                        if (d > 1) const SizedBox(width: 6),
                        Expanded(
                          child: _DayChip(
                            letter: const ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'][d - 1],
                            name: weekdayNames[d - 1],
                            color: typeColor(_type),
                            selected: _days.contains(d),
                            onTap: () => _toggleDay(d),
                          ),
                        ),
                      ],
                    ]),
                    if (_days.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: _Stepper(
                            controller: _released,
                            label: 'Out so far',
                            onChanged: () => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TimeTile(
                            label: _minutes >= 0 ? timeLabel : '$timeLabel (default)',
                            custom: _minutes >= 0,
                            onTap: _pickTime,
                            onReset: () => setState(() => _minutes = -1),
                          ),
                        ),
                      ]),
                    ],
                  ],
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    onChanged: _onUrlChanged,
                    decoration: const InputDecoration(
                      labelText: 'Link where you read/watch (optional)',
                      prefixIcon: Icon(Icons.link_rounded),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty || UrlProgress.normalize(v) != null) ? null : 'Not a valid web link',
                  ),
                  if (_previewBusy)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(children: [
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Looking up title and cover...', style: TextStyle(color: p.subText, fontSize: 13))),
                      ]),
                    ),
                  if (_previewFailed)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text("Couldn't read details from that site. You can still fill them in yourself.",
                          style: TextStyle(color: p.subText, fontSize: 13)),
                    ),
                  if (_noCover && !_previewBusy)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text("No cover found for this link. Tap the cover box to choose a photo.",
                          style: TextStyle(color: p.subText, fontSize: 13)),
                    ),
                  if (_offered != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text('Found "${_offered!.title}"', style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w600)),
                        if (_offeredTitle)
                          TextButton(
                            onPressed: () => setState(() {
                              _title.text = _offered!.title;
                              _offeredTitle = false;
                              if (!_offeredCover) _offered = null;
                            }),
                            child: const Text('Use title'),
                          ),
                        if (_offeredCover && _offered!.imageUrl != null)
                          TextButton(
                            onPressed: () async {
                              final ok = await _applyCover(context.read<LinkPreviewService>(), _offered!.imageUrl!);
                              if (!mounted) return;
                              setState(() {
                                if (ok) _offeredCover = false;
                                if (!_offeredTitle && ok) _offered = null;
                              });
                            },
                            child: const Text('Use cover'),
                          ),
                      ]),
                    ),
                  if (_detected != null && !_isMovie)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(children: [
                        Expanded(
                          child: Text('Link says ${_type.unit} $_detected. Use it as your progress?',
                              style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        TextButton(onPressed: () => _applyDetected(_detected!), child: const Text('Use it')),
                      ]),
                    ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Rating', style: heading(14, weight: FontWeight.w700, color: p.text)),
                      Text(_rating == 0 ? 'Not rated' : '${ratingLabel(_rating)} / 5',
                          style: TextStyle(color: p.subText, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ]),
                    const Spacer(),
                    _StarRating(value: _rating, onChanged: (v) => setState(() => _rating = v)),
                    if (_rating > 0)
                      IconButton(
                        tooltip: 'Clear rating',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _rating = 0),
                        icon: Icon(Icons.close_rounded, size: 18, color: p.subText),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _notes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Notes', alignLabelWithHint: true),
                  ),
                ]),
              ),
            ),
          ),
          // Pinned so Save is always in reach, however long the form gets.
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.outline, width: 1.5))),
            child: Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: FilledButton(onPressed: _submit, child: const Text('Save'))),
            ]),
          ),
        ]),
      ),
    );
  }
}

const _shortStatus = {
  Status.planToWatch: 'Planned',
  Status.watching: 'Watching',
  Status.completed: 'Done',
  Status.onHold: 'On Hold',
  Status.dropped: 'Dropped',
};

/// "+ Season" until one is set, then a small [-] Season N [+] stepper. Stepping below 1 clears it.
class _SeasonPill extends StatelessWidget {
  const _SeasonPill({required this.season, required this.onChanged});
  final int season;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (season == 0) {
      return Semantics(
        button: true,
        label: 'Add a season number',
        child: ExcludeSemantics(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onChanged(1),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: p.outline, width: 1.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_rounded, size: 16, color: p.text),
                const SizedBox(width: 4),
                Text('Season', style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      );
    }
    Widget btn(IconData i, String tip, int next) => IconButton(
          tooltip: tip,
          onPressed: () => onChanged(next),
          icon: Icon(i, size: 18, color: p.text),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      btn(Icons.remove_rounded, season == 1 ? 'Remove season' : 'Previous season', season - 1),
      Text('Season $season', style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w800)),
      btn(Icons.add_rounded, 'Next season', (season + 1).clamp(1, 99)),
    ]);
  }
}

/// One weekday toggle (Mo Tu We Th Fr Sa Su). Several can be on, for shows that air twice a week.
class _DayChip extends StatelessWidget {
  const _DayChip({required this.letter, required this.name, required this.color, required this.selected, required this.onTap});
  final String letter;
  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 44,
            alignment: Alignment.center,
            decoration: selected
                ? brutal(p, color: color, radius: 14, shadow: 2)
                : BoxDecoration(
                    color: color.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.transparent, width: 2),
                  ),
            child: Text(letter,
                style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? onTile : p.text)),
          ),
        ),
      ),
    );
  }
}

/// Tap to choose the reminder time; shows the default until one is picked, with a reset once it is.
class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.label, required this.custom, required this.onTap, required this.onReset});
  final String label;
  final bool custom;
  final VoidCallback onTap;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: 'Reminder time, $label',
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Remind at',
              contentPadding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
              suffixIcon: custom
                  ? IconButton(
                      tooltip: 'Use default time',
                      visualDensity: VisualDensity.compact,
                      onPressed: onReset,
                      icon: Icon(Icons.close_rounded, size: 18, color: p.subText),
                    )
                  : Icon(Icons.schedule_rounded, color: p.subText),
            ),
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: custom ? p.text : p.subText, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ),
      ),
    );
  }
}

/// Poster-shaped tile: tap to choose a cover, with a small remove button when one is set.
class _CoverPicker extends StatelessWidget {
  const _CoverPicker({required this.file, required this.onPick, required this.onRemove});
  final File? file;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: file == null ? 'Add cover image' : 'Change cover image',
      child: GestureDetector(
        onTap: onPick,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 56,
            height: 76,
            decoration: brutal(p, color: p.field, radius: 12, shadow: 2),
            clipBehavior: Clip.antiAlias,
            child: file == null
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_photo_alternate_rounded, color: p.text, size: 26),
                    const SizedBox(height: 2),
                    Text('Cover', style: TextStyle(color: p.subText, fontSize: 11, fontWeight: FontWeight.w700)),
                  ])
                : Image.file(file!, fit: BoxFit.cover, cacheWidth: 168),
          ),
          if (onRemove != null)
            Positioned(
              top: -10,
              right: -10,
              child: Tooltip(
                message: 'Remove cover',
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: brutal(p, color: p.card, radius: 14, shadow: 1),
                    child: Icon(Icons.close_rounded, size: 16, color: p.text),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing, this.action});
  final String text;
  final String? trailing;
  final Widget? action; // replaces [trailing] with a control

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(children: [
        Text(text, style: heading(14, weight: FontWeight.w700, color: p.text)),
        const SizedBox(width: 12),
        if (action != null) Expanded(child: Align(alignment: Alignment.centerRight, child: action!)),
        if (trailing != null && action == null)
          Expanded(
            child: Text(trailing!,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.subText, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }
}

/// Tappable option in the outlined style. Selected = filled with [color], bold outline, hard shadow.
class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
    this.stacked = false,
    this.shortLabel,
  });
  final String label;
  final String? shortLabel; // shown instead of [label] when space is tight; [label] stays the accessible name
  final IconData icon;
  final Color color;
  final bool selected;
  final bool stacked; // icon above label (used for the 4 media types)
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fg = selected ? onTile : p.text;
    final text = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(shortLabel ?? label,
          maxLines: 1,
          style: TextStyle(fontSize: stacked ? 12 : 13, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: fg)),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            constraints: const BoxConstraints(minHeight: 44),
            padding: EdgeInsets.symmetric(horizontal: stacked ? 4 : 12, vertical: stacked ? 8 : 8),
            decoration: selected
                ? brutal(p, color: color, radius: 14, shadow: 2)
                : BoxDecoration(
                    color: color.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.transparent, width: 2),
                  ),
            child: stacked
                ? Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 22, color: fg), const SizedBox(height: 2), text])
                : Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 18, color: fg), const SizedBox(width: 6), Flexible(child: text)]),
          ),
        ),
      ),
    );
  }
}

/// Number field with − / + buttons.
class _Stepper extends StatelessWidget {
  const _Stepper({required this.controller, required this.label, required this.onChanged, this.extra});
  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;
  final String? Function(int)? extra;

  void _bump(int d) {
    final n = ((int.tryParse(controller.text) ?? 0) + d).clamp(0, 99999);
    controller.text = '$n';
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget btn(IconData i, String tip, int d) => IconButton(
          tooltip: tip,
          onPressed: () => _bump(d),
          icon: Icon(i, color: p.text),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        );
    return TextFormField(
      controller: controller,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: btn(Icons.remove_rounded, 'Decrease $label', -1),
        suffixIcon: btn(Icons.add_rounded, 'Increase $label', 1),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
      validator: (v) {
        final n = int.tryParse(v ?? '');
        return n == null ? 'Required' : extra?.call(n);
      },
    );
  }
}

/// 5 stars, half-star steps. Tap or drag; value is 0-10 (each star = 2).
class _StarRating extends StatelessWidget {
  const _StarRating({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  static const _size = 36.0;
  static const _gold = Color(0xFFF5A623);

  void _update(double dx) => onChanged(((dx / (_size / 2)).ceil()).clamp(0, 10));

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      slider: true,
      label: 'Rating',
      value: value == 0 ? 'Not rated' : '${ratingLabel(value)} of 5 stars',
      increasedValue: '${ratingLabel((value + 1).clamp(0, 10))} of 5 stars',
      decreasedValue: (value - 1) <= 0 ? 'Not rated' : '${ratingLabel(value - 1)} of 5 stars',
      onIncrease: () => onChanged((value + 1).clamp(0, 10)),
      onDecrease: () => onChanged((value - 1).clamp(0, 10)),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            // Tapping the current value again clears it.
            final v = ((d.localPosition.dx / (_size / 2)).ceil()).clamp(1, 10);
            onChanged(v == value ? 0 : v);
          },
          onHorizontalDragUpdate: (d) => _update(d.localPosition.dx),
          child: SizedBox(
            width: _size * 5,
            height: _size,
            child: Row(children: [
              for (var i = 0; i < 5; i++)
                SizedBox(
                  width: _size,
                  height: _size,
                  child: Icon(
                    value >= 2 * (i + 1)
                        ? Icons.star_rounded
                        : value == 2 * i + 1
                            ? Icons.star_half_rounded
                            : Icons.star_outline_rounded,
                    size: 32,
                    color: value > 2 * i ? _gold : p.subText,
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
