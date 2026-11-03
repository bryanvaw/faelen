import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../models/budget_models.dart';
import 'bank_card.dart';
import 'budget_widgets.dart';

/// The add/edit sheet for a card. Shows the card itself as a live preview at the top.
/// [onDelete] shows a Delete button when editing; the sheet closes after calling it.
Future<Account?> showAccountForm(
  BuildContext context, {
  required String Function() newId,
  Account? account,
  int usedSkins = 0,
  VoidCallback? onDelete,
}) {
  return showModalBottomSheet<Account>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AccountForm(newId: newId, account: account, usedSkins: usedSkins, onDelete: onDelete),
  );
}

class _AccountForm extends StatefulWidget {
  const _AccountForm({required this.newId, this.account, required this.usedSkins, this.onDelete});
  final String Function() newId;
  final Account? account;

  /// How many cards exist, so a new card starts on the next colour.
  final int usedSkins;
  final VoidCallback? onDelete;

  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.account?.name);
  late final _issuer = TextEditingController(text: widget.account?.issuer);
  late final _last4 = TextEditingController(text: widget.account?.last4);
  late final _opening = TextEditingController(text: widget.account == null || widget.account!.openingCents == 0 ? '' : centsToField(widget.account!.openingCents));
  late CardKind _kind = widget.account?.kind ?? CardKind.debit;
  late CardNetwork _network = widget.account?.network ?? CardNetwork.none;
  late int _skin = widget.account?.skin ?? widget.usedSkins % cardSkins.length;
  bool _negative = false;

  bool get _editing => widget.account != null;

  @override
  void initState() {
    super.initState();
    _negative = (widget.account?.openingCents ?? 0) < 0;
    for (final c in [_name, _issuer, _last4, _opening]) {
      c.addListener(() => setState(() {})); // the preview card follows typing
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _issuer, _last4, _opening]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _openingCents {
    final c = parseCents(_opening.text) ?? 0;
    return _negative ? -c : c;
  }

  Account _build() => Account(
        id: widget.account?.id ?? widget.newId(),
        name: _name.text.trim().isEmpty ? _kind.label : _name.text.trim(),
        issuer: _issuer.text.trim(),
        kind: _kind,
        network: _network,
        last4: _last4.text,
        skin: _skin,
        openingCents: _openingCents,
      );

  void _save() {
    if (!_key.currentState!.validate()) return;
    Navigator.pop(context, _build());
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final preview = _build();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _key,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_editing ? 'Edit card' : 'New card', style: heading(22, color: p.text)),
                const SizedBox(height: 16),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: BankCard(account: preview, balance: preview.openingCents),
                  ),
                ),
                const SizedBox(height: 6),
                const FieldLabel('Colour'),
                Wrap(spacing: 12, runSpacing: 10, children: [
                  for (var i = 0; i < cardSkins.length; i++)
                    Semantics(
                      button: true,
                      selected: _skin == i,
                      label: cardSkins[i].name,
                      child: ExcludeSemantics(
                        child: GestureDetector(
                          onTap: () => setState(() => _skin = i),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: cardSkins[i].face,
                              shape: BoxShape.circle,
                              border: Border.all(color: p.ink, width: _skin == i ? 3.5 : 1.5),
                              boxShadow: _skin == i ? [BoxShadow(color: p.ink, offset: const Offset(0, 3))] : null,
                            ),
                            child: _skin == i ? Icon(Icons.check_rounded, color: cardSkins[i].dark ? Colors.white : onTile, size: 22) : null,
                          ),
                        ),
                      ),
                    ),
                ]),
                const FieldLabel('Card name'),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 24,
                  decoration: const InputDecoration(hintText: 'Everyday card', counterText: ''),
                ),
                const FieldLabel('Bank or wallet'),
                TextFormField(
                  controller: _issuer,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 20,
                  decoration: const InputDecoration(hintText: 'BDO, GCash, Maya…', counterText: ''),
                ),
                const FieldLabel('Type'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final k in CardKind.values) PillChoice(label: k.label, on: _kind == k, onTap: () => setState(() => _kind = k)),
                ]),
                const FieldLabel('Network'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final n in CardNetwork.values) PillChoice(label: n.label, on: _network == n, onTap: () => setState(() => _network = n)),
                ]),
                const FieldLabel('Last 4 digits (optional)'),
                TextFormField(
                  controller: _last4,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                  decoration: const InputDecoration(hintText: '1234', helperText: 'Only the last four, never the full number', counterText: ''),
                ),
                FieldLabel(_kind == CardKind.credit ? 'Amount owed right now (optional)' : 'Balance today (optional)'),
                TextFormField(
                  controller: _opening,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: const InputDecoration(prefixText: '₱ ', hintText: '0.00'),
                  validator: (v) => (v ?? '').trim().isEmpty || parseCents(v!) != null ? null : 'Enter an amount like 5000 or 5000.50',
                ),
                if (_kind == CardKind.credit)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: PillChoice(label: _negative ? 'Counted as owed' : 'Count it as owed', on: _negative, onTap: () => setState(() => _negative = !_negative)),
                  ),
                if (_editing && widget.onDelete != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextButton.icon(
                      onPressed: () {
                        widget.onDelete!();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.delete_outline_rounded, color: budgetDanger),
                      label: const Text('Delete card and its transactions', style: TextStyle(color: budgetDanger)),
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
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _save,
                child: Text(_editing ? 'Save card' : 'Add card'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
