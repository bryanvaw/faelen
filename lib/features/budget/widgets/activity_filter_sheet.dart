import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../models/budget_models.dart';
import '../services/activity_filter.dart';
import 'budget_widgets.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String shortDate(DateTime d) => '${_months[d.month - 1]} ${d.day}${d.year == DateTime.now().year ? '' : ', ${d.year}'}';

/// The narrowing choices for the Activity list: dates, categories and card. The list updates when
/// "Show results" is pressed; dismissing the sheet keeps the filter as it was. Returns the new filter.
Future<ActivityFilter?> showActivityFilters(BuildContext context, {required ActivityFilter filter, required List<Account> accounts}) {
  return showModalBottomSheet<ActivityFilter>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FilterSheet(initial: filter, accounts: accounts),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.accounts});
  final ActivityFilter initial;
  final List<Account> accounts;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ActivityFilter _f = widget.initial;

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 6),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _f.from != null && _f.to != null ? DateTimeRange(start: _f.from!, end: _f.to!) : null,
    );
    if (r != null) setState(() => _f = _f.copyWith(period: ActivityPeriod.custom, from: dateOnly(r.start), to: dateOnly(r.end)));
  }

  void _toggle(String id) {
    final next = {..._f.categories};
    next.contains(id) ? next.remove(id) : next.add(id);
    setState(() => _f = _f.copyWith(categories: next));
  }

  String _label(Category c) => c.id == 'income_other' ? 'Other income' : c.label;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Filter', style: heading(21, color: p.text))),
              if (_f.sheetCount > 0)
                TextButton(
                  onPressed: () => setState(() => _f = _f.copyWith(accountId: () => null, categories: <String>{}, period: ActivityPeriod.all)),
                  child: const Text('Clear'),
                ),
            ]),
            const FieldLabel('Dates', dense: true),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final period in ActivityPeriod.values)
                PillChoice(
                  label: period == ActivityPeriod.custom ? periodLabel(_f.copyWith(period: ActivityPeriod.custom), shortDate) : period.label,
                  on: _f.period == period,
                  onTap: () => period == ActivityPeriod.custom ? _pickDates() : setState(() => _f = _f.copyWith(period: period)),
                ),
            ]),
            if (widget.accounts.length > 1) ...[
              const FieldLabel('Card', dense: true),
              Wrap(spacing: 8, runSpacing: 8, children: [
                PillChoice(label: 'Every card', on: _f.accountId == null, onTap: () => setState(() => _f = _f.copyWith(accountId: () => null))),
                for (final a in widget.accounts) PillChoice(label: a.name, dot: a.skinData.face, on: _f.accountId == a.id, onTap: () => setState(() => _f = _f.copyWith(accountId: () => a.id))),
              ]),
            ],
            const FieldLabel('Spending categories', dense: true),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in expenseCategories) PillChoice(label: c.label, on: _f.categories.contains(c.id), onTap: () => _toggle(c.id)),
            ]),
            const FieldLabel('Income and transfers', dense: true),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in [...incomeCategories, transferCategory]) PillChoice(label: _label(c), on: _f.categories.contains(c.id), onTap: () => _toggle(c.id)),
            ]),
            const SizedBox(height: 8),
          ]),
        ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
        decoration: BoxDecoration(color: p.bg, border: Border(top: BorderSide(color: p.outline, width: 1.5))),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(style: toneButton(context), onPressed: () => Navigator.pop(context, _f), child: const Text('Show results')),
        ),
      ),
    ]);
  }
}
