import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../budget/widgets/budget_widgets.dart' show Tone, toneBox;
import '../models/task.dart';
import '../state/planner_store.dart';
import '../widgets/task_form_sheet.dart';

/// The Planner's one colour: the Siamese cat's cool slate blue.
const plannerColor = Color(0xFF7C9CCB);

Tone plannerTone(BuildContext context) => Tone.fromColor(plannerColor, Theme.of(context).brightness);

/// Only the word "overdue" ever wears red, and it is lifted in the dark theme so it still reads.
Color _late(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFF7A7A) : const Color(0xFFC62828);

class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  PlannerView _view = PlannerView.today;
  String? _completing; // shows the check for a moment before the row leaves the list

  void _toast(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  Future<void> _add() async {
    final store = context.read<PlannerStore>();
    final task = await showTaskForm(context, tone: plannerTone(context), newId: store.newId, today: store.today);
    if (task != null) await store.add(task);
  }

  Future<void> _edit(Task t) async {
    final store = context.read<PlannerStore>();
    final edited = await showTaskForm(
      context,
      tone: plannerTone(context),
      newId: store.newId,
      today: store.today,
      task: t,
      onDelete: () {
        store.remove(t.id);
        _toast('Deleted “${t.title}”', action: SnackBarAction(label: 'Undo', onPressed: () => store.restore(t)));
      },
    );
    if (edited != null) await store.update(edited);
  }

  Future<void> _toggle(Task t) async {
    final store = context.read<PlannerStore>();
    if (!t.isDone) {
      setState(() => _completing = t.id);
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;
    }
    final before = await store.toggle(t);
    if (!mounted) return;
    setState(() => _completing = null);
    final next = store.movedTo(t.id);
    _toast(
      before.isDone
          ? 'Back on your list'
          : next != null
          ? 'Done. Next: ${dayLabel(next, store.today)}'
          : 'Done: “${t.title}”',
      action: SnackBarAction(label: 'Undo', onPressed: () => store.restore(before)),
    );
  }

  Future<void> _clearDone() async {
    final store = context.read<PlannerStore>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Clear finished tasks?'),
        content: Text('This removes ${store.doneCount} finished ${store.doneCount == 1 ? 'task' : 'tasks'} for good.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) await store.clearDone();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final store = context.watch<PlannerStore>();
    final tone = plannerTone(context);
    final groups = store.groups(_view);
    return ColoredBox(
      color: p.bg,
      child: Scaffold(
        backgroundColor: p.bg,
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: _AddButton(tone: tone, onTap: _add),
        body: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(children: [
                _Header(store: store),
                _ViewPills(view: _view, store: store, tone: tone, onPick: (v) => setState(() => _view = v)),
                if (store.error != null) _Notice(text: store.error!),
                Expanded(
                  child: store.loading
                      ? const Center(child: CircularProgressIndicator())
                      : groups.isEmpty
                      ? _Empty(view: _view, hasOpen: store.todayCount + store.upcomingCount > 0, tone: tone, onAdd: _add)
                      : _TaskList(
                          groups: groups,
                          view: _view,
                          tone: tone,
                          completing: _completing,
                          today: store.today,
                          onToggle: _toggle,
                          onEdit: _edit,
                          onClearDone: _clearDone,
                        ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.store});
  final PlannerStore store;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final due = store.todayCount - store.overdueCount;
    final parts = <String>[
      if (due > 0) '$due due today',
      if (store.overdueCount > 0) '${store.overdueCount} overdue',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Row(children: [
          IconButton(tooltip: 'Back', onPressed: () => Navigator.maybePop(context), icon: Icon(Icons.arrow_back_rounded, color: p.text)),
          Image.asset('assets/cats/planner.png', width: 40, height: 40, excludeFromSemantics: true),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Planner', style: heading(21, color: p.text, height: 1.1)),
              Text(
                parts.isEmpty ? (store.upcomingCount > 0 ? '${store.upcomingCount} coming up' : 'No open tasks') : parts.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.subText, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Today / Upcoming / Done with counts: neutral when off, the Planner colour when on.
class _ViewPills extends StatelessWidget {
  const _ViewPills({required this.view, required this.store, required this.tone, required this.onPick});
  final PlannerView view;
  final PlannerStore store;
  final Tone tone;
  final ValueChanged<PlannerView> onPick;

  static const _names = {PlannerView.today: 'Today', PlannerView.upcoming: 'Upcoming', PlannerView.done: 'Done'};

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Row(children: [
        for (final v in PlannerView.values) ...[
          if (v != PlannerView.today) const SizedBox(width: 8),
          Expanded(
            child: Builder(builder: (context) {
              final on = v == view;
              final n = store.count(v);
              return Semantics(
                button: true,
                selected: on,
                label: '${_names[v]}, $n',
                child: ExcludeSemantics(
                  child: GestureDetector(
                    onTap: () => onPick(v),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: on ? tone.main : p.ink.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(_names[v]!, style: TextStyle(fontWeight: on ? FontWeight.w800 : FontWeight.w600, fontSize: 14, color: on ? tone.on : p.text)),
                          const SizedBox(width: 6),
                          Text('$n', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: on ? tone.on.withValues(alpha: 0.85) : p.subText)),
                        ]),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ]),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _late(context).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.error_outline_rounded, size: 20, color: _late(context)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: p.text, fontSize: 13.5))),
        ]),
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({
    required this.groups,
    required this.view,
    required this.tone,
    required this.completing,
    required this.today,
    required this.onToggle,
    required this.onEdit,
    required this.onClearDone,
  });
  final List<TaskGroup> groups;
  final PlannerView view;
  final Tone tone;
  final String? completing;
  final DateTime today;
  final void Function(Task) onToggle;
  final void Function(Task) onEdit;
  final VoidCallback onClearDone;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    // One flat list (headings and rows), so only the rows on screen are built.
    final items = <Object>[
      for (final g in groups) ...[g, ...g.tasks],
    ];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final it = items[i];
        if (it is TaskGroup) {
          final first = identical(it, groups.first);
          return Padding(
            padding: EdgeInsets.only(top: first ? 4 : 18, bottom: 8),
            child: Row(children: [
              Expanded(
                child: Text(
                  '${it.title}  ·  ${it.tasks.length}',
                  style: heading(14, color: it.overdue ? _late(context) : p.subText),
                ),
              ),
              if (view == PlannerView.done && first)
                TextButton(onPressed: onClearDone, child: Text('Clear all', style: TextStyle(color: p.subText, fontWeight: FontWeight.w700))),
            ]),
          );
        }
        final t = it as Task;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _TaskRow(
            key: ValueKey(t.id),
            task: t,
            tone: tone,
            checked: t.isDone || completing == t.id,
            today: today,
            showDay: view == PlannerView.today && groups.first.overdue && t.due != null && t.due!.isBefore(today),
            onToggle: () => onToggle(t),
            onEdit: () => onEdit(t),
          ),
        );
      },
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({super.key, required this.task, required this.tone, required this.checked, required this.today, required this.showDay, required this.onToggle, required this.onEdit});
  final Task task;
  final Tone tone;
  final bool checked, showDay;
  final DateTime today;
  final VoidCallback onToggle, onEdit;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final t = task;
    final sub = <String>[
      if (showDay) dayLabel(t.due!, today),
      if (t.hasTime) timeLabel(t.minutes) else if (!t.isDone && t.due != null && !showDay) 'Any time',
    ];
    final meta = TextStyle(color: p.subText, fontSize: 12.5, fontWeight: FontWeight.w500);
    return Semantics(
      container: true,
      label: '${t.title}${sub.isEmpty ? '' : ', ${sub.join(', ')}'}${t.priority == Priority.high ? ', high priority' : ''}',
      child: Material(
        color: p.ink.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onEdit,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Row(children: [
              Semantics(
                button: true,
                label: t.isDone ? 'Mark ${t.title} not done' : 'Mark ${t.title} done',
                child: ExcludeSemantics(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onToggle,
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: checked ? tone.main : Colors.transparent,
                            border: Border.all(color: checked ? tone.main : p.subText, width: 2),
                          ),
                          child: checked ? Icon(Icons.check_rounded, size: 18, color: tone.on) : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      t.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.isDone ? p.subText : p.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        height: 1.25,
                        decoration: t.isDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (sub.isNotEmpty || t.repeat != Repeat.none || t.remind || t.priority != Priority.normal)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          if (sub.isNotEmpty)
                            Text(sub.join(' · '), style: showDay ? meta.copyWith(color: _late(context), fontWeight: FontWeight.w700) : meta),
                          if (t.priority != Priority.normal) _Meta(icon: t.priority == Priority.high ? Icons.flag_rounded : Icons.outlined_flag_rounded, text: t.priority.label, style: meta, strong: t.priority == Priority.high),
                          if (t.repeat != Repeat.none) _Meta(icon: Icons.repeat_rounded, text: t.repeat.label, style: meta),
                          if (t.remind) _Meta(icon: Icons.notifications_none_rounded, text: 'Reminder', style: meta),
                        ]),
                      ),
                  ]),
                ),
              ),
              const SizedBox(width: 14),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, required this.style, this.strong = false});
  final IconData icon;
  final String text;
  final TextStyle style;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final color = strong ? Palette.of(context).text : style.color;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 3),
      Text(text, style: strong ? style.copyWith(color: color, fontWeight: FontWeight.w700) : style),
    ]);
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.view, required this.hasOpen, required this.tone, required this.onAdd});
  final PlannerView view;
  final bool hasOpen;
  final Tone tone;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (title, body) = switch (view) {
      PlannerView.today => hasOpen ? ('All clear today', 'Nothing is due. Your later tasks are under Upcoming.') : ('Nothing due today', 'Add a task and give it a day to see it here.'),
      PlannerView.upcoming => ('Nothing coming up', 'Tasks with a later date, or no date, wait here.'),
      PlannerView.done => ('Nothing finished yet', 'Tasks you tick off are kept here.'),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 80),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/cats/planner.png', width: 92, height: 92, excludeFromSemantics: true),
          const SizedBox(height: 14),
          Text(title, style: heading(19, color: p.text)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: TextStyle(color: p.subText, fontSize: 14, height: 1.35)),
          if (view != PlannerView.done) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onAdd,
              style: FilledButton.styleFrom(backgroundColor: tone.main, foregroundColor: tone.on, minimumSize: const Size(0, 48)),
              child: const Text('Add a task', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ]),
      ),
    );
  }
}

/// The one way to add: centred at the bottom, within thumb reach, keeping the Faelen outline.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.tone, required this.onTap});
  final Tone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.viewInsetsOf(context).bottom > 0) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: 'Add a task',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 60,
            height: 60,
            decoration: toneBox(context, tone: tone, color: tone.main, radius: 20, shadow: 4, strong: true),
            child: Icon(Icons.add_rounded, color: tone.on, size: 30),
          ),
        ),
      ),
    );
  }
}
