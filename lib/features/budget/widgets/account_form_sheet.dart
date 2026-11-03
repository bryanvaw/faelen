import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../models/budget_models.dart';
import 'bank_card.dart';
import 'budget_widgets.dart';

/// The add/edit sheet for a card. Compact on purpose: the live card, every colour, and all the fields fit a
/// phone screen without scrolling (names side by side, one row each for type and network).
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
  late final _opening = TextEditingController(text: widget.account == null || widget.account!.openingCents == 0 ? '' : centsToField(widget.account!.openingCents.abs()));
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

  Widget _field(String label, TextEditingController c, {String? hint, int? max, TextCapitalization caps = TextCapitalization.none, TextInputType? type, List<TextInputFormatter>? formatters, String? prefix, String? Function(String?)? validator}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FieldLabel(label, dense: true),
      TextFormField(
        controller: c,
        textCapitalization: caps,
        keyboardType: type,
        inputFormatters: formatters,
        maxLength: max,
        validator: validator,
        decoration: InputDecoration(hintText: hint, prefixText: prefix, counterText: '', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13)),
      ),
    ]);
  }

  /// Equal-width options in one row (so they never wrap onto a second line).
  Widget _segmented(List<Widget> pills) => Row(children: [
        for (var i = 0; i < pills.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: pills[i]),
        ],
      ]);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final preview = _build();
    final tone = Tone.from(cardSkins[_skin], Theme.of(context).brightness);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _key,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(_editing ? 'Edit card' : 'New card', style: heading(21, color: p.text))),
                  if (_editing && widget.onDelete != null)
                    IconButton(
                      tooltip: 'Delete card and its transactions',
                      onPressed: () {
                        widget.onDelete!();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.delete_outline_rounded, color: budgetDanger),
                    ),
                ]),
                const SizedBox(height: 8),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: BankCard(account: preview, balance: preview.openingCents, shadow: 3),
                  ),
                ),
                const FieldLabel('Colour', dense: true),
                LayoutBuilder(builder: (context, c) {
                  const gap = 5.0;
                  const perRow = 9;
                  final size = ((c.maxWidth - gap * (perRow - 1)) / perRow).floorToDouble();
                  return Wrap(spacing: gap, runSpacing: gap, children: [
                    for (var i = 0; i < cardSkins.length; i++)
                      Semantics(
                        button: true,
                        selected: _skin == i,
                        label: cardSkins[i].name,
                        child: ExcludeSemantics(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() => _skin = i),
                            child: Container(
                              width: size,
                              height: size,
                              decoration: BoxDecoration(
                                color: cardSkins[i].face,
                                shape: BoxShape.circle,
                                border: Border.all(color: _skin == i ? (dark ? Colors.white : p.ink) : (dark ? const Color(0x55FFFFFF) : const Color(0x33000000)), width: _skin == i ? 3 : 1.2),
                              ),
                              child: _skin == i ? Icon(Icons.check_rounded, color: cardSkins[i].dark ? Colors.white : onTile, size: size * 0.6) : null,
                            ),
                          ),
                        ),
                      ),
                  ]);
                }),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: _field('Card name', _name, hint: 'Everyday card', max: 24, caps: TextCapitalization.words)),
                  const SizedBox(width: 12),
                  Expanded(child: _field('Bank or wallet', _issuer, hint: 'BDO, GCash…', max: 20, caps: TextCapitalization.words)),
                ]),
                const FieldLabel('Type', dense: true),
                _segmented([for (final k in CardKind.values) PillChoice(compact: true, tone: tone, label: k.label, on: _kind == k, onTap: () => setState(() => _kind = k))]),
                const FieldLabel('Network', dense: true),
                _segmented([for (final n in CardNetwork.values) PillChoice(compact: true, tone: tone, label: n.label, on: _network == n, onTap: () => setState(() => _network = n))]),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: _field('Last 4 digits', _last4, hint: '1234', type: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _field(
                      _kind == CardKind.credit ? 'Owed right now' : 'Balance today',
                      _opening,
                      hint: '0.00',
                      prefix: '₱ ',
                      type: const TextInputType.numberWithOptions(decimal: true),
                      formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      validator: (v) => (v ?? '').trim().isEmpty || parseCents(v!) != null ? null : 'Use an amount like 5000.50',
                    ),
                  ),
                ]),
                if (_kind == CardKind.credit)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: PillChoice(tone: tone, label: _negative ? 'Counted as owed' : 'Count it as owed', on: _negative, onTap: () => setState(() => _negative = !_negative)),
                  ),
                const SizedBox(height: 8),
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            decoration: BoxDecoration(color: p.bg, border: Border(top: BorderSide(color: p.outline, width: 1.5))),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: tone.main,
                  foregroundColor: tone.on,
                  minimumSize: const Size.fromHeight(50),
                  side: BorderSide(color: tone.line, width: 2),
                ),
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
