import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../models/budget_models.dart';
import '../services/statement_import.dart';
import '../state/budget_store.dart';
import '../widgets/budget_widgets.dart';
import 'budget_screen.dart' show dayLabel, incomeText;

/// Shows what Faelen found in a statement file and lets the user fix the columns, the card, the direction
/// and each row's category before anything is added. Pops with the number of transactions added.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.text, required this.fileName});
  final String text;
  final String fileName;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  late final StatementTable _table = StatementTable.parse(widget.text);
  late ColumnMap? _map = _table.guess;
  // With the overview showing no card is selected, so start from the first one (the import button needs a card).
  late String? _accountId = context.read<BudgetStore>().selected?.id ?? context.read<BudgetStore>().accounts.firstOrNull?.id;
  bool _flip = false;
  late bool _showColumns = _table.guess == null;
  List<ImportRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  void _recompute() {
    final store = context.read<BudgetStore>();
    final map = _map;
    _rows = map == null ? [] : _table.rows(map, flip: _flip, existing: store.txns, accountId: _accountId);
  }

  void _change(VoidCallback f) => setState(() {
        f();
        _recompute();
      });

  int get _selected => _rows.where((r) => r.selected).length;

  Future<void> _import() async {
    final store = context.read<BudgetStore>();
    final id = _accountId;
    if (id == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final txns = [
      for (final r in _rows)
        if (r.selected) Txn(id: store.newId(), accountId: id, cents: r.cents, income: r.income, category: r.category, day: r.day, note: r.note, createdAt: now),
    ];
    if (txns.isEmpty) return;
    await store.addTxns(txns);
    if (mounted) Navigator.pop(context, txns.length);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final store = context.watch<BudgetStore>();
    final tone = Tone.of(context);
    final now = DateTime.now();
    final dups = _rows.where((r) => r.duplicate).length;
    final days = _rows.map((r) => r.day).toList()..sort();
    final range = days.isEmpty ? '' : '${dayLabel(days.first, now)}${days.first == days.last ? '' : ' to ${dayLabel(days.last, now)}'}';

    return ColoredBox(
      color: p.bg,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: p.bg,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Import statement', style: heading(20, color: p.text)),
            Text(widget.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subText, fontSize: 12, fontWeight: FontWeight.w500)),
          ]),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(children: [
                Expanded(
                  child: CustomScrollView(slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          // One row for the three choices that shape the import: the card, the columns, swap in/out.
                          Row(children: [
                            Expanded(
                              child: _CardPicker(
                                accounts: store.accounts,
                                value: _accountId,
                                onChanged: (id) {
                                  store.select(id);
                                  _change(() => _accountId = id);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            _IconToggle(icon: Icons.view_column_rounded, tooltip: 'Columns', on: _showColumns, onTap: () => setState(() => _showColumns = !_showColumns)),
                            const SizedBox(width: 8),
                            _IconToggle(icon: Icons.swap_vert_rounded, tooltip: 'Swap in/out', on: _flip, onTap: () => _change(() => _flip = !_flip)),
                          ]),
                          const SizedBox(height: 8),
                          if (_rows.isEmpty)
                            Text(
                              _map == null
                                  ? 'Faelen could not tell which columns are the date and the amount. Pick them below.'
                                  : 'No transactions found with these columns. Check the columns below.',
                              style: TextStyle(color: budgetDanger, fontSize: 14, fontWeight: FontWeight.w700, height: 1.35),
                            )
                          else
                            Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${_rows.length} found · $range', maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(14.5, color: p.text)),
                                  if (dups > 0) Text('$dups already in this card, left unticked', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subText, fontSize: 12, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(minimumSize: const Size(44, 40), padding: const EdgeInsets.symmetric(horizontal: 8)),
                                onPressed: () => setState(() => [for (final r in _rows) r.selected = true]),
                                child: const Text('All'),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(minimumSize: const Size(44, 40), padding: const EdgeInsets.symmetric(horizontal: 8)),
                                onPressed: () => setState(() => [for (final r in _rows) r.selected = false]),
                                child: const Text('None'),
                              ),
                            ]),
                          if (_showColumns) _ColumnPanel(table: _table, map: _map, onChanged: (m) => _change(() => _map = m)),
                        ]),
                      ),
                    ),
                    SliverList.builder(
                      itemCount: _rows.length,
                      itemBuilder: (_, i) => _RowTile(
                        row: _rows[i],
                        now: now,
                        tone: tone,
                        onToggle: () => setState(() => _rows[i].selected = !_rows[i].selected),
                        onCategory: (c) => setState(() => _rows[i].category = c),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                  decoration: BoxDecoration(color: p.bg, border: Border(top: BorderSide(color: p.outline, width: 1.5))),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: toneButton(context),
                      onPressed: _selected == 0 || _accountId == null ? null : _import,
                      child: Text(_selected == 0 ? 'Nothing ticked' : 'Import $_selected ${_selected == 1 ? 'transaction' : 'transactions'}'),
                    ),
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

class _IconToggle extends StatelessWidget {
  const _IconToggle({required this.icon, required this.tooltip, required this.on, required this.onTap});
  final IconData icon;
  final String tooltip;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tone = Tone.of(context);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: on,
        label: tooltip,
        child: ExcludeSemantics(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 46,
              height: 46,
              decoration: on ? toneBox(context, tone: tone, color: tone.main, radius: 13, shadow: 2) : BoxDecoration(color: tone.soft, borderRadius: BorderRadius.circular(13), border: Border.all(color: Colors.transparent, width: 2)),
              child: Icon(icon, size: 22, color: on ? tone.on : p.text),
            ),
          ),
        ),
      ),
    );
  }
}

/// The card the transactions go on, as one button that opens a short menu (one line however many cards).
class _CardPicker extends StatelessWidget {
  const _CardPicker({required this.accounts, required this.value, required this.onChanged});
  final List<Account> accounts;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tone = Tone.of(context);
    final a = accounts.where((x) => x.id == value).firstOrNull ?? accounts.first;
    final menu = accounts.length > 1;
    final body = Container(
      constraints: const BoxConstraints(minHeight: 46),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      decoration: toneBox(context, tone: tone, color: tone.soft, radius: 13, shadow: 2),
      child: Row(children: [
        Container(width: 16, height: 16, decoration: BoxDecoration(color: a.skinData.face, shape: BoxShape.circle, border: Border.all(color: p.text.withValues(alpha: 0.55), width: 1.5))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Add to', style: TextStyle(color: p.subText, fontSize: 11, fontWeight: FontWeight.w700, height: 1.1)),
            Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(14.5, weight: FontWeight.w800, color: p.text, height: 1.15)),
          ]),
        ),
        if (menu) Icon(Icons.unfold_more_rounded, color: p.text),
      ]),
    );
    if (!menu) return body;
    return PopupMenuButton<String>(
      tooltip: 'Choose a card',
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final c in accounts)
          PopupMenuItem(
            value: c.id,
            child: Row(children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: c.skinData.face, shape: BoxShape.circle, border: Border.all(color: p.ink.withValues(alpha: 0.5), width: 1.5))),
              const SizedBox(width: 10),
              Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis)),
            ]),
          ),
      ],
      child: body,
    );
  }
}

/// Which column is the date, the description and the amount (or money in and money out).
class _ColumnPanel extends StatelessWidget {
  const _ColumnPanel({required this.table, required this.map, required this.onChanged});
  final StatementTable table;
  final ColumnMap? map;
  final ValueChanged<ColumnMap> onChanged;

  @override
  Widget build(BuildContext context) {
    final m = map;
    final two = m?.moneyIn != null;

    Widget pick(String label, int? value, {required ValueChanged<int?> onPick, bool optional = false}) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FieldLabel(label, dense: true),
          DropdownButtonFormField<int?>(
            initialValue: value,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
            items: [
              if (optional) const DropdownMenuItem<int?>(value: null, child: Text('None')),
              for (var i = 0; i < table.columns; i++) DropdownMenuItem<int?>(value: i, child: Text(table.headers[i], maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onPick,
          ),
        ]),
      );
    }

    // Until the three required columns are chosen, start from the first columns so the lists are usable.
    final base = m ?? ColumnMap(date: 0, desc: table.columns > 1 ? 1 : 0, amount: table.columns - 1);
    return Column(children: [
      pick('Date', base.date, onPick: (v) => onChanged(base.copyWith(date: v))),
      pick('Description', base.desc, onPick: (v) => onChanged(base.copyWith(desc: v))),
      pick(two ? 'Money out' : 'Amount', base.amount, onPick: (v) => onChanged(base.copyWith(amount: v))),
      pick('Money in (if it has its own column)', base.moneyIn, optional: true, onPick: (v) => onChanged(base.copyWith(moneyIn: () => v))),
      if (!two) pick('Type, like Debit or Credit (optional)', base.type, optional: true, onPick: (v) => onChanged(base.copyWith(type: () => v))),
    ]);
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row, required this.now, required this.tone, required this.onToggle, required this.onCategory});
  final ImportRow row;
  final DateTime now;
  final Tone tone;
  final VoidCallback onToggle;
  final ValueChanged<String> onCategory;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final cat = categoryById(row.category);
    final cats = row.income ? incomeCategories : expenseCategories;
    final amount = '${row.income ? '+' : '-'}${peso(row.cents)}';
    return Opacity(
      opacity: row.selected ? 1 : 0.55,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 20, 4),
          child: Row(children: [
            Semantics(
              label: row.selected ? 'Included' : 'Left out',
              child: Checkbox(
                value: row.selected,
                onChanged: (_) => onToggle(),
                activeColor: tone.main,
                checkColor: tone.on,
                side: BorderSide(color: p.text, width: 2),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Category',
              onSelected: onCategory,
              itemBuilder: (_) => [
                for (final c in cats)
                  PopupMenuItem(value: c.id, child: Row(children: [Icon(c.icon, size: 20, color: p.text), const SizedBox(width: 10), Text(c.label)])),
              ],
              child: Padding(padding: const EdgeInsets.all(4), child: CategoryBadge(icon: cat.icon, size: 38)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(row.note.isEmpty ? cat.label : row.note, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(14.5, weight: FontWeight.w700, color: p.text)),
                Text(
                  '${dayLabel(row.day, now)} · ${cat.label}${row.duplicate ? ' · Already added' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: row.duplicate ? budgetDanger : p.subText, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 118),
              child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(amount, maxLines: 1, style: heading(15, weight: FontWeight.w800, color: row.income ? incomeText(p) : p.text))),
            ),
          ]),
        ),
      ),
    );
  }
}
