import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../budget/widgets/budget_widgets.dart' show ChoiceTile, FieldLabel, PillChoice, Tone;
import '../../media/services/release_reminders.dart';
import '../models/task.dart';
import '../state/planner_store.dart' show dayLabel, timeLabel;

/// The add/edit sheet for one task. Returns the task to save, or null when dismissed.
/// [onDelete] shows a delete icon when editing; the sheet closes after calling it.
Future<Task?> showTaskForm(
  BuildContext context, {
  required Tone tone,
  required String Function() newId,
  required DateTime today,
  Task? task,
  VoidCallback? onDelete,
}) {
  return showModalBottomSheet<Task>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _TaskForm(tone: tone, newId: newId, today: today, task: task, onDelete: onDelete),
  );
}

class _TaskForm extends StatefulWidget {
  const _TaskForm({required this.tone, required this.newId, required this.today, this.task, this.onDelete});
  final Tone tone;
  final String Function() newId;
  final DateTime today;
  final Task? task;
  final VoidCallback? onDelete;

  @override
  State<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<_TaskForm> {
  final _key = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.task?.title);
  late DateTime? _due = widget.task == null ? widget.today : widget.task!.due;
  late int _minutes = widget.task?.minutes ?? -1;
  late Priority _priority = widget.task?.priority ?? Priority.normal;
  late Repeat _repeat = widget.task?.repeat ?? Repeat.none;
  late bool _remind = widget.task?.remind ?? false;
  String? _permissionNote;

  bool get _editing => widget.task != null;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  DateTime get _tomorrow => DateTime(widget.today.year, widget.today.month, widget.today.day + 1);
  bool _is(DateTime? a, DateTime b) => a != null && dayOf(a) == dayOf(b);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? widget.today,
      firstDate: DateTime(widget.today.year - 1),
      lastDate: DateTime(widget.today.year + 10),
    );
    if (picked != null) setState(() => _due = dayOf(picked));
  }

  Future<void> _pickTime() async {
    final start = _minutes >= 0 ? TimeOfDay(hour: _minutes ~/ 60, minute: _minutes % 60) : const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: start);
    if (picked != null) setState(() => _minutes = picked.hour * 60 + picked.minute);
  }

  Future<void> _setRemind(bool v) async {
    setState(() {
      _remind = v;
      _permissionNote = null;
    });
    if (!v) return;
    final reminders = Provider.of<ReleaseReminders?>(context, listen: false);
    if (reminders == null || !ReleaseReminders.supported) return;
    final ok = await reminders.requestPermission();
    if (!ok && mounted) {
      setState(() => _permissionNote = 'Notifications are off for Faelen. Turn them on in your phone settings to get this reminder.');
    }
  }

  void _save() {
    if (!_key.currentState!.validate()) return;
    final old = widget.task;
    final now = DateTime.now();
    final due = _due;
    Navigator.pop(
      context,
      Task(
        id: old?.id ?? widget.newId(),
        title: _title.text.trim(),
        due: due,
        minutes: due == null ? -1 : _minutes, // a time without a day means nothing
        priority: _priority,
        repeat: due == null ? Repeat.none : _repeat, // nothing to repeat from
        remind: due != null && _remind,
        // A new date is a new day of the month; an untouched one keeps the day it belongs on.
        monthDay: old != null && old.due == due && _repeat == Repeat.monthly ? old.monthDay : 0,
        doneAt: old?.doneAt,
        createdAt: old?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final t = widget.tone;
    final hasDay = _due != null;
    final custom = hasDay && !_is(_due, widget.today) && !_is(_due, _tomorrow);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Form(
        key: _key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
              child: Row(children: [
                Expanded(child: Text(_editing ? 'Edit task' : 'New task', style: heading(20, color: p.text))),
                if (_editing && widget.onDelete != null)
                  IconButton(
                    tooltip: 'Delete task',
                    icon: Icon(Icons.delete_outline_rounded, color: p.text),
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onDelete!();
                    },
                  ),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextFormField(
                    controller: _title,
                    autofocus: !_editing,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    maxLength: 120,
                    decoration: const InputDecoration(hintText: 'What needs doing?', counterText: ''),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Give the task a name' : null,
                    onFieldSubmitted: (_) => _save(),
                  ),
                  const FieldLabel('When', dense: true),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    PillChoice(label: 'Today', tone: t, on: _is(_due, widget.today), onTap: () => setState(() => _due = widget.today)),
                    PillChoice(label: 'Tomorrow', tone: t, on: _is(_due, _tomorrow), onTap: () => setState(() => _due = _tomorrow)),
                    PillChoice(label: custom ? dayLabel(_due!, widget.today) : 'Pick a date', tone: t, on: custom, onTap: _pickDate),
                    PillChoice(label: 'No date', tone: t, on: !hasDay, onTap: () => setState(() => _due = null)),
                  ]),
                  if (hasDay) ...[
                    const FieldLabel('Time', dense: true),
                    Row(children: [
                      PillChoice(label: _minutes >= 0 ? timeLabel(_minutes) : 'Any time', tone: t, on: _minutes >= 0, onTap: _pickTime),
                      if (_minutes >= 0)
                        IconButton(
                          tooltip: 'Clear the time',
                          icon: Icon(Icons.close_rounded, color: p.subText),
                          onPressed: () => setState(() => _minutes = -1),
                        ),
                    ]),
                  ],
                  const FieldLabel('Priority', dense: true),
                  Row(children: [
                    for (final pr in Priority.values) ...[
                      if (pr != Priority.low) const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceTile(
                          label: pr.label,
                          icon: pr == Priority.high ? Icons.flag_rounded : Icons.outlined_flag_rounded,
                          on: _priority == pr,
                          tone: t,
                          height: 52,
                          onTap: () => setState(() => _priority = pr),
                        ),
                      ),
                    ],
                  ]),
                  if (hasDay) ...[
                    const FieldLabel('Repeat', dense: true),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final r in Repeat.values) PillChoice(label: r.label, tone: t, on: _repeat == r, onTap: () => setState(() => _repeat = r)),
                    ]),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Remind me', style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        _minutes >= 0 ? 'At ${timeLabel(_minutes)}' : 'At 9:00 AM, since no time is set',
                        style: TextStyle(color: p.subText),
                      ),
                      value: _remind,
                      onChanged: _setRemind,
                    ),
                    if (_permissionNote != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(_permissionNote!, style: TextStyle(color: p.subText, fontSize: 12.5, height: 1.3)),
                      ),
                  ],
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: p.text, side: BorderSide(color: p.outline, width: 1.5)),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(backgroundColor: t.main, foregroundColor: t.on, minimumSize: const Size.fromHeight(50)),
                    child: Text(_editing ? 'Save' : 'Add task', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
