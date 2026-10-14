import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/media_entry.dart';

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
  late final _rating = TextEditingController(text: '${widget.entry?.rating ?? 0}');
  late final _notes = TextEditingController(text: widget.entry?.notes);
  late MediaType _type = widget.entry?.type ?? MediaType.anime;
  late Status _status = widget.entry?.status ?? Status.planToWatch;

  @override
  void dispose() {
    for (final c in [_title, _current, _total, _rating, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_key.currentState!.validate()) return;
    Navigator.pop(
      context,
      MediaEntry(
        id: widget.entry?.id ?? newId(),
        title: _title.text.trim(),
        type: _type,
        status: _status,
        current: int.parse(_current.text),
        total: int.parse(_total.text),
        rating: int.parse(_rating.text),
        notes: _notes.text,
      ),
    );
  }

  Widget _num(TextEditingController c, String label, {String? Function(int)? extra}) => TextFormField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label),
        validator: (v) {
          final n = int.tryParse(v ?? '');
          return n == null ? 'Required' : extra?.call(n);
        },
      );

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.entry != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _key,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(isEdit ? 'Edit entry' : 'Add entry', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<MediaType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [for (final t in MediaType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                  onChanged: (v) => setState(() => _type = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<Status>(
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    for (final s in Status.values)
                      DropdownMenuItem(value: s, child: Text(s.label, overflow: TextOverflow.ellipsis))
                  ],
                  onChanged: (v) => setState(() => _status = v!),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _num(_current, 'Current ${_type.unit}')),
              const SizedBox(width: 12),
              Expanded(
                child: _num(_total, 'Total (0 = unknown)',
                    extra: (n) => n > 0 && (int.tryParse(_current.text) ?? 0) > n ? 'Less than current' : null),
              ),
            ]),
            const SizedBox(height: 12),
            _num(_rating, 'Rating (1–10, 0 = unrated)', extra: (n) => n > 10 ? 'Max 10' : null),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Notes', alignLabelWithHint: true),
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
