import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../models/budget_models.dart';
import 'budget_widgets.dart';

final _amountFormatters = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

String? _amountError(String? v) {
  final c = parseCents(v ?? '');
  if (c == null) return 'Enter an amount like 250 or 250.50';
  if (c <= 0) return 'The amount must be more than zero';
  return null;
}

/// A bottom sheet with a title, scrolling body and a pinned action bar.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.formKey, required this.children, required this.action});
  final String title;
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: heading(22, color: p.text)),
                ...children,
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: BoxDecoration(color: p.bg, border: Border(top: BorderSide(color: p.outline, width: 1.5))),
            child: SizedBox(width: double.infinity, child: action),
          ),
        ]),
      ),
    );
  }
}

Widget _deleteButton(BuildContext context, String label, VoidCallback onDelete) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TextButton.icon(
        onPressed: () {
          onDelete();
          Navigator.pop(context);
        },
        icon: const Icon(Icons.delete_outline_rounded, color: budgetDanger),
        label: Text(label, style: const TextStyle(color: budgetDanger)),
      ),
    );

// ---------------------------------------------------------------------------------------------
// Transfer between cards

class TransferResult {
  const TransferResult(this.from, this.to, this.cents, this.note);
  final String from, to;
  final int cents;
  final String note;
}

Future<TransferResult?> showTransferSheet(BuildContext context, {required List<Account> accounts, required Map<String, int> balances, String? from}) {
  return showModalBottomSheet<TransferResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _TransferSheet(accounts: accounts, balances: balances, from: from),
  );
}

class _TransferSheet extends StatefulWidget {
  const _TransferSheet({required this.accounts, required this.balances, this.from});
  final List<Account> accounts;
  final Map<String, int> balances;
  final String? from;

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  final _key = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late String _from = widget.from ?? widget.accounts.first.id;
  late String _to = widget.accounts.firstWhere((a) => a.id != _from).id;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _pickFrom(String id) => setState(() {
        _from = id;
        if (_to == id) _to = widget.accounts.firstWhere((a) => a.id != id).id;
      });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return _Sheet(
      title: 'Move money',
      formKey: _key,
      action: FilledButton(
        style: toneButton(context),
        onPressed: () {
          if (!_key.currentState!.validate()) return;
          Navigator.pop(context, TransferResult(_from, _to, parseCents(_amount.text)!, _note.text.trim()));
        },
        child: const Text('Move money'),
      ),
      children: [
        const FieldLabel('From', dense: true),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final a in widget.accounts)
            PillChoice(label: '${a.name} · ${peso(widget.balances[a.id] ?? 0, compact: true)}', dot: a.skinData.face, on: _from == a.id, onTap: () => _pickFrom(a.id)),
        ]),
        const FieldLabel('To', dense: true),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final a in widget.accounts.where((a) => a.id != _from)) PillChoice(label: a.name, dot: a.skinData.face, on: _to == a.id, onTap: () => setState(() => _to = a.id)),
        ]),
        const FieldLabel('Amount'),
        TextFormField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _amountFormatters,
          style: heading(26, color: p.text),
          decoration: const InputDecoration(prefixText: '₱ ', hintText: '0.00'),
          validator: _amountError,
        ),
        const FieldLabel('Note (optional)'),
        TextFormField(controller: _note, maxLength: 60, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Cash in to GCash', counterText: '')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Monthly bill

Future<Bill?> showBillForm(BuildContext context, {required List<Account> accounts, required String Function() newId, Bill? bill, VoidCallback? onDelete}) {
  return showModalBottomSheet<Bill>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _BillForm(accounts: accounts, newId: newId, bill: bill, onDelete: onDelete),
  );
}

class _BillForm extends StatefulWidget {
  const _BillForm({required this.accounts, required this.newId, this.bill, this.onDelete});
  final List<Account> accounts;
  final String Function() newId;
  final Bill? bill;
  final VoidCallback? onDelete;

  @override
  State<_BillForm> createState() => _BillFormState();
}

class _BillFormState extends State<_BillForm> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.bill?.name);
  late final _amount = TextEditingController(text: widget.bill == null ? '' : centsToField(widget.bill!.cents));
  late final _day = TextEditingController(text: '${widget.bill?.day ?? DateTime.now().day}');
  late String _category = widget.bill?.category ?? 'bills';
  late String _account = widget.bill?.accountId ?? widget.accounts.first.id;

  bool get _editing => widget.bill != null;

  @override
  void dispose() {
    for (final c in [_name, _amount, _day]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return _Sheet(
      title: _editing ? 'Edit monthly bill' : 'New monthly bill',
      formKey: _key,
      action: FilledButton(
        style: toneButton(context),
        onPressed: () {
          if (!_key.currentState!.validate()) return;
          final old = widget.bill;
          Navigator.pop(
            context,
            Bill(
              id: old?.id ?? widget.newId(),
              name: _name.text.trim(),
              cents: parseCents(_amount.text)!,
              category: _category,
              accountId: _account,
              day: int.parse(_day.text),
              lastPosted: old?.lastPosted ?? 0,
            ),
          );
        },
        child: Text(_editing ? 'Save bill' : 'Add bill'),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Faelen adds it to your history by itself on its due day each month.', style: TextStyle(color: p.subText, fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.35)),
        ),
        const FieldLabel('Name'),
        TextFormField(
          controller: _name,
          autofocus: !_editing,
          textCapitalization: TextCapitalization.words,
          maxLength: 30,
          decoration: const InputDecoration(hintText: 'Internet, Rent, Netflix…', counterText: ''),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Give the bill a name' : null,
        ),
        const FieldLabel('Amount'),
        TextFormField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _amountFormatters,
          decoration: const InputDecoration(prefixText: '₱ ', hintText: '0.00'),
          validator: _amountError,
        ),
        const FieldLabel('Due on day of the month'),
        TextFormField(
          controller: _day,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
          decoration: const InputDecoration(hintText: '1 to 31', helperText: 'In a shorter month it falls on the last day'),
          validator: (v) {
            final d = int.tryParse(v ?? '');
            return d == null || d < 1 || d > 31 ? 'Enter a day from 1 to 31' : null;
          },
        ),
        const FieldLabel('Category'),
        LayoutBuilder(builder: (context, c) {
          const gap = 10.0;
          final w = (c.maxWidth - gap * 3) / 4;
          return Wrap(spacing: gap, runSpacing: gap, children: [
            for (final cat in expenseCategories)
              SizedBox(width: w, child: ChoiceTile(label: cat.label, icon: cat.icon, on: _category == cat.id, onTap: () => setState(() => _category = cat.id))),
          ]);
        }),
        if (widget.accounts.length > 1) ...[
          const FieldLabel('Paid from'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in widget.accounts) PillChoice(label: a.name, dot: a.skinData.face, on: _account == a.id, onTap: () => setState(() => _account = a.id)),
          ]),
        ],
        if (_editing && widget.onDelete != null) _deleteButton(context, 'Delete bill', widget.onDelete!),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Savings goal

Future<Goal?> showGoalForm(BuildContext context, {required String Function() newId, int usedSkins = 0, Goal? goal, VoidCallback? onDelete}) {
  return showModalBottomSheet<Goal>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _GoalForm(newId: newId, usedSkins: usedSkins, goal: goal, onDelete: onDelete),
  );
}

class _GoalForm extends StatefulWidget {
  const _GoalForm({required this.newId, required this.usedSkins, this.goal, this.onDelete});
  final String Function() newId;
  final int usedSkins;
  final Goal? goal;
  final VoidCallback? onDelete;

  @override
  State<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<_GoalForm> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.goal?.name);
  late final _target = TextEditingController(text: widget.goal == null ? '' : centsToField(widget.goal!.targetCents));
  late final int _skin = widget.goal?.skin ?? 3; // kept in the data; goals are drawn in the screen's colour family

  bool get _editing => widget.goal != null;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: _editing ? 'Edit goal' : 'New savings goal',
      formKey: _key,
      action: FilledButton(
        style: toneButton(context),
        onPressed: () {
          if (!_key.currentState!.validate()) return;
          final old = widget.goal;
          Navigator.pop(context, Goal(id: old?.id ?? widget.newId(), name: _name.text.trim(), targetCents: parseCents(_target.text)!, savedCents: old?.savedCents ?? 0, skin: _skin));
        },
        child: Text(_editing ? 'Save goal' : 'Add goal'),
      ),
      children: [
        const FieldLabel('What are you saving for?'),
        TextFormField(
          controller: _name,
          autofocus: !_editing,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 30,
          decoration: const InputDecoration(hintText: 'New phone, Trip to Cebu…', counterText: ''),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Give the goal a name' : null,
        ),
        const FieldLabel('Target'),
        TextFormField(
          controller: _target,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _amountFormatters,
          decoration: const InputDecoration(prefixText: '₱ ', hintText: '0.00'),
          validator: _amountError,
        ),
        if (_editing && widget.onDelete != null) _deleteButton(context, 'Delete goal', widget.onDelete!),
      ],
    );
  }
}

/// Add money to a goal, or take it out. Returns the signed change in centavos.
Future<int?> showGoalAmount(BuildContext context, {required Goal goal, required bool adding}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _GoalAmount(goal: goal, adding: adding),
  );
}

class _GoalAmount extends StatefulWidget {
  const _GoalAmount({required this.goal, required this.adding});
  final Goal goal;
  final bool adding;

  @override
  State<_GoalAmount> createState() => _GoalAmountState();
}

class _GoalAmountState extends State<_GoalAmount> {
  final _key = GlobalKey<FormState>();
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final g = widget.goal;
    final left = (g.targetCents - g.savedCents).clamp(0, 1 << 52);
    return _Sheet(
      title: widget.adding ? 'Add to ${g.name}' : 'Take out of ${g.name}',
      formKey: _key,
      action: FilledButton(
        style: toneButton(context),
        onPressed: () {
          if (!_key.currentState!.validate()) return;
          final c = parseCents(_amount.text)!;
          Navigator.pop(context, widget.adding ? c : -c);
        },
        child: Text(widget.adding ? 'Add money' : 'Take out'),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            widget.adding ? (left > 0 ? '${peso(left, compact: true)} to go.' : 'You already reached this goal.') : '${peso(g.savedCents, compact: true)} saved so far.',
            style: TextStyle(color: p.subText, fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ),
        const FieldLabel('Amount'),
        TextFormField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _amountFormatters,
          style: heading(26, color: p.text),
          decoration: const InputDecoration(prefixText: '₱ ', hintText: '0.00'),
          validator: (v) {
            final e = _amountError(v);
            if (e != null) return e;
            if (!widget.adding && parseCents(v!)! > g.savedCents) return 'Only ${peso(g.savedCents, compact: true)} is saved';
            return null;
          },
        ),
      ],
    );
  }
}
