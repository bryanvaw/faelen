import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../models/budget_models.dart';
import 'budget_widgets.dart';

/// The add/edit sheet for one transaction. Returns the transaction to save, or null when dismissed.
/// [onDelete] shows a Delete button when editing; the sheet closes after calling it.
Future<Txn?> showTxnForm(
  BuildContext context, {
  required List<Account> accounts,
  required String Function() newId,
  Txn? txn,
  String? accountId,
  bool income = false,
  VoidCallback? onDelete,
}) {
  return showModalBottomSheet<Txn>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _TxnForm(accounts: accounts, newId: newId, txn: txn, accountId: accountId, income: income, onDelete: onDelete),
  );
}

class _TxnForm extends StatefulWidget {
  const _TxnForm({required this.accounts, required this.newId, this.txn, this.accountId, required this.income, this.onDelete});
  final List<Account> accounts;
  final String Function() newId;
  final Txn? txn;
  final String? accountId;
  final bool income;
  final VoidCallback? onDelete;

  @override
  State<_TxnForm> createState() => _TxnFormState();
}

class _TxnFormState extends State<_TxnForm> {
  final _key = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.txn == null ? '' : centsToField(widget.txn!.cents));
  late final _note = TextEditingController(text: widget.txn?.note);
  late bool _income = widget.txn?.income ?? widget.income;
  late String _category = widget.txn?.category ?? (_income ? incomeCategories.first.id : expenseCategories.first.id);
  late String _account = widget.txn?.accountId ?? widget.accountId ?? widget.accounts.first.id;
  late DateTime _day = widget.txn?.day ?? dateOnly(DateTime.now());

  bool get _editing => widget.txn != null;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _setIncome(bool v) {
    if (v == _income) return;
    setState(() {
      _income = v;
      _category = (v ? incomeCategories : expenseCategories).first.id; // the old category does not exist on the other side
    });
  }

  void _save() {
    if (!_key.currentState!.validate()) return;
    final cents = parseCents(_amount.text)!;
    final old = widget.txn;
    Navigator.pop(
      context,
      Txn(
        id: old?.id ?? widget.newId(),
        accountId: _account,
        cents: cents,
        income: _income,
        category: _category,
        day: _day,
        note: _note.text.trim(),
        createdAt: old?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 1));
    if (d != null) setState(() => _day = dateOnly(d));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final cats = _income ? incomeCategories : expenseCategories;
    final today = dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final accent = _income ? const Color(0xFF7BD389) : p.primary;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _key,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_editing ? 'Edit transaction' : 'New transaction', style: heading(22, color: p.text)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _FlowTile(label: 'Expense', icon: Icons.south_west_rounded, color: p.primary, on: !_income, onTap: () => _setIncome(false))),
                  const SizedBox(width: 12),
                  Expanded(child: _FlowTile(label: 'Income', icon: Icons.north_east_rounded, color: const Color(0xFF7BD389), on: _income, onTap: () => _setIncome(true))),
                ]),
                const FieldLabel('Amount'),
                TextFormField(
                  controller: _amount,
                  autofocus: !_editing,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  style: heading(28, color: p.text),
                  decoration: InputDecoration(
                    prefixIcon: Padding(padding: const EdgeInsets.only(left: 16, right: 6), child: Text('₱', style: heading(28, color: p.subText))),
                    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                    hintText: '0.00',
                  ),
                  validator: (v) {
                    final c = parseCents(v ?? '');
                    if (c == null) return 'Enter an amount like 250 or 250.50';
                    if (c <= 0) return 'The amount must be more than zero';
                    return null;
                  },
                ),
                const FieldLabel('Category'),
                LayoutBuilder(builder: (context, c) {
                  const gap = 10.0;
                  final w = (c.maxWidth - gap * 3) / 4;
                  return Wrap(spacing: gap, runSpacing: gap, children: [
                    for (final cat in cats)
                      SizedBox(
                        width: w,
                        child: ChoiceTile(label: cat.label, icon: cat.icon, color: cat.color, on: _category == cat.id, onTap: () => setState(() => _category = cat.id)),
                      ),
                  ]);
                }),
                if (widget.accounts.length > 1) ...[
                  const FieldLabel('Card'),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final a in widget.accounts) PillChoice(label: a.name, dot: a.skinData.face, on: _account == a.id, onTap: () => setState(() => _account = a.id)),
                  ]),
                ],
                const FieldLabel('Date'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  PillChoice(label: 'Today', on: _day == today, onTap: () => setState(() => _day = today)),
                  PillChoice(label: 'Yesterday', on: _day == yesterday, onTap: () => setState(() => _day = yesterday)),
                  PillChoice(label: _day == today || _day == yesterday ? 'Pick a date' : _longDay(_day), on: _day != today && _day != yesterday, onTap: _pickDay),
                ]),
                const FieldLabel('Note (optional)'),
                TextFormField(
                  controller: _note,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 80,
                  decoration: const InputDecoration(hintText: 'Lunch with Ana', counterText: ''),
                ),
                if (_editing && widget.onDelete != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: TextButton.icon(
                      onPressed: () {
                        widget.onDelete!();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.delete_outline_rounded, color: budgetDanger),
                      label: const Text('Delete transaction', style: TextStyle(color: budgetDanger)),
                    ),
                  ),
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: BoxDecoration(color: p.bg, border: Border(top: BorderSide(color: p.outline, width: 1.5))),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: onTile, minimumSize: const Size.fromHeight(52)),
                onPressed: _save,
                child: Text(_editing ? 'Save changes' : (_income ? 'Add income' : 'Add expense')),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _FlowTile extends StatelessWidget {
  const _FlowTile({required this.label, required this.icon, required this.color, required this.on, required this.onTap});
  final String label;
  final IconData icon;
  final Color color;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 52,
            decoration: on ? brutal(p, color: color, radius: 14, shadow: 3) : BoxDecoration(color: color.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.transparent, width: 2)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 20, color: on ? onTile : p.text),
              const SizedBox(width: 8),
              Text(label, style: heading(15, weight: on ? FontWeight.w800 : FontWeight.w600, color: on ? onTile : p.text)),
            ]),
          ),
        ),
      ),
    );
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _longDay(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
