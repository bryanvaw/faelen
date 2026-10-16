import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/settings_store.dart';
import '../../../core/theme.dart';
import '../media_theme.dart';
import '../models/media_entry.dart';
import '../services/cover_service.dart';
import '../services/link_preview_service.dart';
import '../services/url_progress.dart';
import '../state/media_store.dart';

/// Shows the add/edit sheet. Returns the saved entry, or null if dismissed.
/// Pass [entry] = null to add. Deleting is handled via [onDelete].
Future<MediaEntry?> showMediaForm(
  BuildContext context, {
  MediaEntry? entry,
  required void Function(String id) onDelete,
}) {
  return showModalBottomSheet<MediaEntry>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _Form(entry: entry, onDelete: onDelete),
  );
}

class _Form extends StatefulWidget {
  const _Form({required this.entry, required this.onDelete});
  final MediaEntry? entry;
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
  Timer? _previewTimer;
  String? _previewedUrl; // last link we looked up, so editing other fields never repeats the request
  bool _previewBusy = false;
  LinkPreview? _offered; // found details that were not applied automatically (field already filled)
  bool _previewFailed = false;
  int? _detected; // number found in the link, offered as progress while it differs from the current one
  late MediaType _type = widget.entry?.type ?? MediaType.anime;
  late Status _status = widget.entry?.status ?? Status.planToWatch;
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
  }

  bool get _isMovie => _type == MediaType.movie;

  @override
  void dispose() {
    _previewTimer?.cancel();
    for (final c in [_title, _current, _total, _notes, _url]) {
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
      ),
    );
  }

  void _onUrlChanged(String v) {
    _previewTimer?.cancel();
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
  Future<void> _lookUp(Uri uri) async {
    _previewedUrl = uri.toString();
    setState(() {
      _previewBusy = true;
      _previewFailed = false;
      _offered = null;
    });
    try {
      final service = context.read<LinkPreviewService>();
      final found = await service.preview(uri);
      if (!mounted || _previewedUrl != uri.toString()) return;
      if (found == null) {
        setState(() {
          _previewBusy = false;
          _previewFailed = true;
        });
        return;
      }
      var titleKept = false, coverKept = false;
      if (_title.text.trim().isEmpty) {
        _title.text = found.title;
      } else {
        titleKept = _title.text.trim() != found.title;
      }
      if (found.imageUrl != null) {
        if (_cover == null && _covers.available) {
          coverKept = !await _applyCover(service, found.imageUrl!);
        } else {
          coverKept = _covers.available;
        }
      }
      if (!mounted) return;
      setState(() {
        _previewBusy = false;
        _offered = (titleKept || coverKept) ? found : null;
        _offeredTitle = titleKept;
        _offeredCover = coverKept;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _previewBusy = false;
          _previewFailed = true;
        });
      }
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final isEdit = widget.entry != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _key,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: brutal(p, color: typeColor(_type), radius: 14, shadow: 2),
                child: Icon(typeIcon(_type), color: onTile, size: 24),
              ),
              const SizedBox(width: 12),
              Text(isEdit ? 'Edit entry' : 'Add entry', style: heading(24, weight: FontWeight.w700, color: p.text)),
            ]),
            const SizedBox(height: 18),
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
            const _Label('Type'),
            Row(children: [
              for (final t in MediaType.values) ...[
                if (t != MediaType.values.first) const SizedBox(width: 8),
                Expanded(
                  child: _ChoiceChip(
                    label: t.label,
                    icon: typeIcon(t),
                    color: typeColor(t),
                    selected: _type == t,
                    stacked: true,
                    onTap: () => setState(() => _type = t),
                  ),
                ),
              ],
            ]),
            const _Label('Status'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in Status.values)
                _ChoiceChip(
                  label: s.label,
                  icon: statusIcon(s),
                  color: statusColor(s),
                  selected: _status == s,
                  onTap: () => _setStatus(s),
                ),
            ]),
            if (!_isMovie) ...[
              const _Label('Progress'),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _Stepper(controller: _current, label: 'Current ${_type.unit}', onChanged: () => setState(() {}))),
                const SizedBox(width: 12),
                Expanded(
                  child: _Stepper(
                    controller: _total,
                    label: 'Total',
                    helper: '0 = unknown',
                    onChanged: () => setState(() {}),
                    extra: (n) => n > 0 && (int.tryParse(_current.text) ?? 0) > n ? 'Less than current' : null,
                  ),
                ),
              ]),
            ],
            const _Label('Link'),
            TextFormField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: _onUrlChanged,
              decoration: const InputDecoration(
                labelText: 'Where you read/watch (optional)',
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
                  Text('Looking up title and cover...', style: TextStyle(color: p.subText, fontSize: 13)),
                ]),
              ),
            if (_previewFailed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text("Couldn't read details from that site. You can still fill them in yourself.",
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
            _Label('Rating', trailing: _rating == 0 ? 'Not rated' : '${ratingLabel(_rating)} / 5'),
            Row(children: [
              _StarRating(value: _rating, onChanged: (v) => setState(() => _rating = v)),
              const Spacer(),
              if (_rating > 0) TextButton(onPressed: () => setState(() => _rating = 0), child: const Text('Clear')),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes', alignLabelWithHint: true),
            ),
            const SizedBox(height: 16),
            Row(children: [
              if (isEdit)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onDelete(widget.entry!.id);
                  },
                  style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                  child: const Text('Delete'),
                ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _submit, child: const Text('Save')),
            ]),
          ]),
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
            width: 64,
            height: 92,
            decoration: brutal(p, color: p.field, radius: 12, shadow: 2),
            clipBehavior: Clip.antiAlias,
            child: file == null
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_photo_alternate_rounded, color: p.text, size: 26),
                    const SizedBox(height: 2),
                    Text('Cover', style: TextStyle(color: p.subText, fontSize: 11, fontWeight: FontWeight.w700)),
                  ])
                : Image.file(file!, fit: BoxFit.cover, cacheWidth: 192),
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
  const _Label(this.text, {this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Row(children: [
        Text(text, style: heading(14, weight: FontWeight.w700, color: p.text)),
        const Spacer(),
        if (trailing != null) Text(trailing!, style: TextStyle(color: p.subText, fontSize: 13, fontWeight: FontWeight.w600)),
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
  });
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final bool stacked; // icon above label (used for the 4 media types)
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fg = selected ? onTile : p.text;
    final text = Text(label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: stacked ? 12 : 13, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: fg));
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
  const _Stepper({required this.controller, required this.label, required this.onChanged, this.helper, this.extra});
  final TextEditingController controller;
  final String label;
  final String? helper;
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
        helperText: helper,
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

  static const _size = 44.0;
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
                    size: 38,
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
