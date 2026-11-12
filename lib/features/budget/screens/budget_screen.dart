import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/link_opener.dart';
import '../../../core/theme.dart';
import '../models/budget_models.dart';
import '../state/budget_store.dart';
import '../services/activity_filter.dart';
import '../widgets/account_form_sheet.dart';
import '../widgets/activity_filter_sheet.dart';
import '../widgets/bank_card.dart';
import '../widgets/budget_widgets.dart';
import '../widgets/plans_sheets.dart';
import '../widgets/txn_form_sheet.dart';
import 'import_screen.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthFull = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String dayLabel(DateTime d, DateTime now) {
  final today = dateOnly(now);
  if (d == today) return 'Today';
  if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
  final year = d.year == today.year ? '' : ', ${d.year}';
  return '${_weekdays[d.weekday - 1]}, ${_monthNames[d.month - 1]} ${d.day}$year';
}

Color incomeText(Palette p) => identical(p, Palette.dark) ? const Color(0xFF5BD68A) : const Color(0xFF14793F);

enum _Tab { cards, activity, budgets, plans }

/// The Budget module: cards with balances, the transaction history and monthly limits by category.
/// Everything takes its colour from the selected card (see [Tone]).
class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> with WidgetsBindingObserver {
  _Tab _tab = _Tab.cards;

  /// Set by "See all" on a card: the Activity tab opens already filtered to it.
  String? _activityCard;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A new day may have made a bill or a subscription due.
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<BudgetStore>()
        ..postDueBills()
        ..postDueSubscriptions();
    }
  }

  BudgetStore get _store => context.read<BudgetStore>();

  Future<void> _addTxn({String? accountId, bool income = false}) async {
    final store = _store;
    if (store.accounts.isEmpty) return _addAccount();
    final t = await showTxnForm(context, accounts: store.accounts, newId: store.newId, accountId: accountId ?? store.selected?.id, income: income);
    if (t != null) await store.saveTxn(t);
  }

  Future<void> _addAccount() async {
    final store = _store;
    final a = await showAccountForm(context, newId: store.newId, usedSkins: store.accounts.length);
    if (a == null) return;
    await store.saveAccount(a);
    store.select(a.id);
  }

  Future<void> _editAccount(Account a) async {
    final store = _store;
    final messenger = ScaffoldMessenger.of(context);
    final updated = await showAccountForm(
      context,
      newId: store.newId,
      account: a,
      onDelete: () async {
        final gone = await store.deleteAccount(a.id);
        if (gone == null) return;
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('Deleted ${a.name}${gone.txns.isEmpty ? '' : ' and ${gone.txns.length} transactions'}'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(label: 'Undo', onPressed: () => store.restoreAccount(gone.account, gone.txns, bills: gone.bills, subs: gone.subs)),
          ));
      },
    );
    if (updated != null) await store.saveAccount(updated);
  }

  Future<void> _editTxn(Txn t) async {
    final store = _store;
    if (t.pair != null) {
      // A transfer is two linked entries; it can only be removed, not edited.
      final remove = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Transfer'),
          content: Text('${t.note} · ${peso(t.cents)}\n\nDeleting it puts the money back on both cards.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Keep')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete transfer')),
          ],
        ),
      );
      if (remove == true) await _deleteTxn(t);
      return;
    }
    final updated = await showTxnForm(
      context,
      accounts: store.accounts,
      newId: store.newId,
      txn: t,
      onDelete: () => _deleteTxn(t),
    );
    if (updated != null) await store.saveTxn(updated);
  }

  Future<void> _deleteTxn(Txn t) async {
    final store = _store;
    final messenger = ScaffoldMessenger.of(context);
    final gone = await store.deleteTxn(t.id);
    if (gone.isEmpty) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(gone.length > 1 ? 'Deleted transfer of ${peso(t.cents)}' : 'Deleted ${peso(t.cents)}'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: 'Undo', onPressed: () => store.restoreTxns(gone)),
      ));
  }

  Future<void> _transfer({String? from}) async {
    final store = _store;
    if (store.accounts.length < 2) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Add a second card to move money between cards')));
      return;
    }
    final r = await showTransferSheet(context, accounts: store.accounts, balances: {for (final a in store.accounts) a.id: store.balanceOf(a)}, from: from);
    if (r != null) await store.transfer(from: r.from, to: r.to, cents: r.cents, note: r.note);
  }

  Future<void> _editBill(Bill? bill) async {
    final store = _store;
    final messenger = ScaffoldMessenger.of(context);
    final result = await showBillForm(
      context,
      accounts: store.accounts,
      newId: store.newId,
      bill: bill,
      onDelete: bill == null
          ? null
          : () async {
              final gone = await store.deleteBill(bill.id);
              if (gone == null) return;
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text('Deleted ${bill.name}'),
                  duration: const Duration(seconds: 6),
                  action: SnackBarAction(label: 'Undo', onPressed: () => store.saveBill(gone)),
                ));
            },
    );
    if (result != null) await store.saveBill(result);
  }

  Future<void> _editSub(Subscription? sub) async {
    final store = _store;
    final messenger = ScaffoldMessenger.of(context);
    final result = await showSubscriptionForm(
      context,
      accounts: store.accounts,
      newId: store.newId,
      sub: sub,
      onDelete: sub == null
          ? null
          : () async {
              final gone = await store.deleteSubscription(sub.id);
              if (gone == null) return;
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text('Deleted ${sub.name}'),
                  duration: const Duration(seconds: 6),
                  action: SnackBarAction(label: 'Undo', onPressed: () => store.saveSubscription(gone)),
                ));
            },
    );
    if (result != null) await store.saveSubscription(result);
  }

  Future<void> _openSubLink(Subscription s) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(s.link);
    final ok = uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && await LinkOpener.open(uri);
    if (!ok) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Could not open the page for ${s.name}')));
    }
  }

  Future<void> _editGoal(Goal? goal) async {
    final store = _store;
    final messenger = ScaffoldMessenger.of(context);
    final result = await showGoalForm(
      context,
      newId: store.newId,
      usedSkins: store.goals.length,
      goal: goal,
      onDelete: goal == null
          ? null
          : () async {
              final gone = await store.deleteGoal(goal.id);
              if (gone == null) return;
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text('Deleted ${goal.name}'),
                  duration: const Duration(seconds: 6),
                  action: SnackBarAction(label: 'Undo', onPressed: () => store.saveGoal(gone)),
                ));
            },
    );
    if (result != null) await store.saveGoal(result);
  }

  /// Picks a statement file (CSV) and opens the preview where the user checks it before anything is added.
  Future<void> _import() async {
    final store = _store;
    final messenger = ScaffoldMessenger.of(context);
    if (store.accounts.isEmpty) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Add a card first, then import its statement')));
      return;
    }
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;
      final file = files.first;
      final bytes = await file.readAsBytes();
      if (bytes.length > 4 && String.fromCharCodes(bytes.take(4)) == '%PDF') {
        messenger.showSnackBar(const SnackBar(content: Text('PDF statements cannot be read yet. Export it as CSV if your bank offers that.')));
        return;
      }
      if (!mounted) return;
      final n = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => ImportScreen(text: utf8.decode(bytes, allowMalformed: true), fileName: file.name)));
      if (n != null) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Imported $n ${n == 1 ? 'transaction' : 'transactions'}')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open that file: $e')));
    }
  }

  Future<void> _goalMoney(Goal g, bool adding) async {
    final delta = await showGoalAmount(context, goal: g, adding: adding);
    if (delta != null) await _store.adjustGoal(g.id, delta);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final store = context.watch<BudgetStore>();
    final err = store.takeSaveError();
    if (err != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save that change. Try again.')));
      });
    }

    final body = store.loading
        ? const Center(child: CircularProgressIndicator())
        : switch (_tab) {
            _Tab.cards => _CardsTab(
                onAddCard: _addAccount,
                onTransfer: (id) => _transfer(from: id),
                onEditCard: _editAccount,
                onAddTxn: _addTxn,
                onEditTxn: _editTxn,
                onSeeAll: (id) => setState(() {
                  _activityCard = id;
                  _tab = _Tab.activity;
                }),
              ),
            _Tab.activity => _ActivityTab(
                key: ValueKey(_activityCard),
                initialCard: _activityCard,
                onAdd: () => _addTxn(),
                onEdit: _editTxn,
                onDelete: _deleteTxn,
              ),
            _Tab.budgets => const _BudgetsTab(),
            _Tab.plans => _PlansTab(onBill: _editBill, onSub: _editSub, onSubLink: _openSubLink, onGoal: _editGoal, onGoalMoney: _goalMoney),
          };

    return ColoredBox(
      color: p.bg,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(children: [
                _Header(onImport: _import),
                Expanded(child: body),
              ]),
            ),
          ),
        ),
        bottomNavigationBar: _BottomBar(
          tab: _tab,
          onSelect: (t) => setState(() {
            if (t != _Tab.activity) _activityCard = null;
            _tab = t;
          }),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onImport});
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 20, 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Row(children: [
          IconButton(tooltip: 'Back to modules', onPressed: () => Navigator.maybePop(context), icon: Icon(Icons.arrow_back_rounded, color: p.text)),
          Image.asset('assets/cats/budget.png', width: 40, height: 40, excludeFromSemantics: true),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Budget', style: heading(21, color: p.text, height: 1.1)),
              Text('Cards, spending & limits', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subText, fontSize: 12, fontWeight: FontWeight.w500)),
            ]),
          ),
          IconButton(tooltip: 'Import a statement', onPressed: onImport, icon: Icon(Icons.download_rounded, color:p.text)),
        ]),
      ),
    );
  }
}

/// The four destinations as a floating dock. Every tab shows its icon and its name (an icon alone
/// had to be remembered); the current one sits in a filled pill in the card colour's family.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.tab, required this.onSelect});
  final _Tab tab;
  final ValueChanged<_Tab> onSelect;

  static const _items = [
    (_Tab.cards, 'Cards', Icons.credit_card_rounded),
    (_Tab.activity, 'Activity', Icons.swap_vert_rounded),
    (_Tab.budgets, 'Budgets', Icons.donut_small_rounded),
    (_Tab.plans, 'Plans', Icons.event_repeat_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tone = Tone.of(context);
    return SafeArea(
      top: false,
      child: Align(
        heightFactor: 1,
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Container(
              height: 62,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: toneBox(context, tone: tone, color: p.card, radius: 24, shadow: 3),
              child: Row(children: [
                for (final (t, label, icon) in _items)
                  Expanded(
                    child: Tooltip(
                      message: label,
                      child: Semantics(
                        button: true,
                        selected: tab == t,
                        label: label,
                        child: ExcludeSemantics(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onSelect(t),
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                height: 50,
                                width: double.infinity,
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(color: tab == t ? tone.main : Colors.transparent, borderRadius: BorderRadius.circular(16)),
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Icon(icon, size: 21, color: tab == t ? tone.on : p.subText),
                                  const SizedBox(height: 2),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(label, maxLines: 1, style: TextStyle(fontSize: 11.5, height: 1.1, fontWeight: tab == t ? FontWeight.w800 : FontWeight.w600, color: tab == t ? tone.on : p.subText)),
                                  ),
                                ]),
                              ),
                            ),
                          ),
                        ),
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

// ---------------------------------------------------------------------------------------------
// Cards tab: the selected card, quick actions and this month, all above the fold.

class _CardsTab extends StatefulWidget {
  const _CardsTab({
    required this.onAddCard,
    required this.onTransfer,
    required this.onEditCard,
    required this.onAddTxn,
    required this.onEditTxn,
    required this.onSeeAll,
  });
  final VoidCallback onAddCard;
  final ValueChanged<String?> onTransfer;
  final ValueChanged<Account> onEditCard;
  final Future<void> Function({String? accountId, bool income}) onAddTxn;
  final ValueChanged<Txn> onEditTxn;
  final ValueChanged<String?> onSeeAll;

  @override
  State<_CardsTab> createState() => _CardsTabState();
}

class _CardsTabState extends State<_CardsTab> {
  bool _hidden = false;

  Future<void> _pick() async {
    final store = context.read<BudgetStore>();
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CardPickerSheet(hidden: _hidden),
    );
    if (choice == null) return;
    if (choice == _CardPickerSheet.addCard) {
      widget.onAddCard();
    } else if (choice == _CardPickerSheet.all) {
      store.selectAll();
    } else {
      store.select(choice);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final store = context.watch<BudgetStore>();
    final accounts = store.accounts;
    if (accounts.isEmpty) return _NoCards(onAdd: widget.onAddCard);

    final selected = store.selected; // null = every card together
    final tone = Tone.of(context);
    final recent = store.recent(accountId: selected?.id, limit: 4);
    final now = DateTime.now();

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Expanded(child: _CardSelector(account: selected, count: accounts.length, onTap: accounts.length > 1 ? _pick : widget.onAddCard)),
            const SizedBox(width: 10),
            Semantics(
              button: true,
              label: _hidden ? 'Show balances' : 'Hide balances',
              child: ExcludeSemantics(
                child: GestureDetector(
                  onTap: () => setState(() => _hidden = !_hidden),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: toneBox(context, tone: tone, color: tone.soft, radius: 14, shadow: 2),
                    child: Icon(_hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: p.text),
                  ),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        if (selected == null)
          _Overview(hidden: _hidden, onOpenCard: store.select, onAddTxn: widget.onAddTxn, onTransfer: () => widget.onTransfer(null), onAddCard: widget.onAddCard)
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: GestureDetector(
                  onTap: () => widget.onEditCard(selected),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOutCubic,
                    child: KeyedSubtree(
                      key: ValueKey(selected.id),
                      child: Padding(padding: const EdgeInsets.only(bottom: 4), child: BankCard(account: selected, balance: store.balanceOf(selected), hidden: _hidden)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Expanded(child: _ActionButton(icon: Icons.south_west_rounded, label: 'Expense', filled: true, onTap: () => widget.onAddTxn(accountId: selected.id))),
              const SizedBox(width: 10),
              Expanded(child: _ActionButton(icon: Icons.north_east_rounded, label: 'Income', filled: false, onTap: () => widget.onAddTxn(accountId: selected.id, income: true))),
              const SizedBox(width: 10),
              Expanded(child: _ActionButton(icon: Icons.swap_horiz_rounded, label: 'Move', filled: false, onTap: () => widget.onTransfer(selected.id))),
              const SizedBox(width: 10),
              Expanded(child: _ActionButton(icon: Icons.tune_rounded, label: 'Edit', filled: false, onTap: () => widget.onEditCard(selected))),
            ]),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Builder(builder: (context) {
              final month = store.summary(of: DateTime.now(), accountId: selected.id);
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.outline, width: 1.5)),
                child: Row(children: [
                  Expanded(child: _FlowStat(label: 'In this month', cents: month.income, income: true, hidden: _hidden)),
                  Container(width: 1.5, height: 34, color: p.outline),
                  Expanded(child: _FlowStat(label: 'Out this month', cents: month.expense, income: false, hidden: _hidden)),
                ]),
              );
            }),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
          child: Row(children: [
            Expanded(child: Text('Recent', style: heading(16, color: p.text))),
            if (recent.isNotEmpty) TextButton(onPressed: () => widget.onSeeAll(selected?.id), child: const Text('See all')),
          ]),
        ),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
            child: Text(selected == null ? 'Nothing logged yet. Tap Expense or Income to start.' : 'Nothing on ${selected.name} yet. Tap Expense or Income to log one.', style: TextStyle(color: p.subText, fontSize: 14, fontWeight: FontWeight.w500)),
          )
        else
          for (final t in recent) TxnRow(txn: t, account: store.account(t.accountId), showCard: selected == null, hidden: _hidden, now: now, onTap: () => widget.onEditTxn(t)),
      ],
    );
  }
}

/// One button that says what is on screen ("All cards" or a card) and opens the list of every card.
/// It is always the same size, however many cards there are.
class _CardSelector extends StatelessWidget {
  const _CardSelector({required this.account, required this.count, required this.onTap});
  final Account? account;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tone = Tone.of(context);
    final a = account;
    final title = a == null ? 'All cards' : a.name;
    final sub = a == null ? '$count cards' : [a.kind.label, if (a.last4.isNotEmpty) '•••• ${a.last4}'].join(' · ');
    return Semantics(
      button: true,
      label: 'Showing $title. Choose a card',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            decoration: toneBox(context, tone: tone, color: tone.soft, radius: 14, shadow: 2),
            child: Row(children: [
              if (a == null)
                Icon(Icons.layers_rounded, size: 22, color: p.text)
              else
                Container(width: 16, height: 16, decoration: BoxDecoration(color: a.skinData.face, shape: BoxShape.circle, border: Border.all(color: p.text.withValues(alpha: 0.55), width: 1.5))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(15.5, weight: FontWeight.w800, color: p.text, height: 1.15)),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subText, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ]),
              ),
              if (count > 1) Icon(Icons.unfold_more_rounded, color: p.text),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Every card in one list, with its balance: "All cards" first, then each card, then "Add a card".
class _CardPickerSheet extends StatelessWidget {
  const _CardPickerSheet({required this.hidden});
  final bool hidden;

  static const all = '*all';
  static const addCard = '*add';

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final store = context.watch<BudgetStore>();
    final selectedId = store.selected?.id;
    Widget row({required Widget leading, required String title, required String sub, required String amount, required bool on, required String value}) {
      final tone = Tone.of(context);
      return Semantics(
        button: true,
        selected: on,
        label: '$title, $amount',
        child: ExcludeSemantics(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pop(context, value),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
              decoration: BoxDecoration(color: on ? tone.soft : Colors.transparent, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.transparent, width: 1.5)),
              child: Row(children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(15.5, weight: FontWeight.w700, color: p.text)),
                    if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subText, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(width: 10),
                Text(amount, style: heading(15, weight: FontWeight.w800, color: p.text)),
                if (on) ...[const SizedBox(width: 6), Icon(Icons.check_rounded, color: p.text, size: 20)],
              ]),
            ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 10), child: Text('Cards', style: heading(21, color: p.text))),
          row(
            leading: _MiniCard(color: null),
            title: 'All cards',
            sub: '${store.accounts.length} cards together',
            amount: hidden ? '₱ ••••' : peso(store.totalBalance, compact: true),
            on: selectedId == null,
            value: all,
          ),
          for (final a in store.accounts)
            row(
              leading: _MiniCard(color: a.skinData),
              title: a.name,
              sub: [if (a.issuer.isNotEmpty && a.issuer.toLowerCase() != a.name.toLowerCase()) a.issuer, if (a.last4.isNotEmpty) '•••• ${a.last4}' else a.kind.label].join(' · '),
              amount: hidden ? '₱ ••••' : peso(store.balanceOf(a), compact: true),
              on: selectedId == a.id,
              value: a.id,
            ),
          row(leading: Container(width: 40, height: 28, alignment: Alignment.center, child: Icon(Icons.add_rounded, color: p.text)), title: 'Add a card', sub: '', amount: '', on: false, value: addCard),
        ],
      ),
    );
  }
}

/// A tiny card shape in a card's colour (or stacked cards for "All cards").
class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.color});
  final CardSkin? color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final line = dark ? const Color(0x66FFFFFF) : p.ink;
    if (color == null) {
      return SizedBox(
        width: 40,
        height: 28,
        child: Stack(children: [
          Positioned(left: 0, top: 0, child: _tile(cardSkins[1].face, line)),
          Positioned(left: 8, top: 4, child: _tile(cardSkins[0].face, line)),
        ]),
      );
    }
    return SizedBox(width: 40, height: 28, child: _tile(color!.face, line, big: true));
  }

  Widget _tile(Color face, Color line, {bool big = false}) => Container(
        width: big ? 40 : 30,
        height: big ? 28 : 22,
        decoration: BoxDecoration(color: face, borderRadius: BorderRadius.circular(6), border: Border.all(color: line, width: 1.5)),
      );
}

/// The picture across every card: total, this month, each card's balance, where the money went, what happened lately.
class _Overview extends StatelessWidget {
  const _Overview({required this.hidden, required this.onOpenCard, required this.onAddTxn, required this.onTransfer, required this.onAddCard});
  final bool hidden;
  final ValueChanged<String> onOpenCard;
  final Future<void> Function({String? accountId, bool income}) onAddTxn;
  final VoidCallback onTransfer;
  final VoidCallback onAddCard;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tone = Tone.of(context);
    final store = context.watch<BudgetStore>();
    final month = store.summary(of: DateTime.now());
    final top = store.spendingFor(DateTime.now()).where((r) => r.spent > 0).take(3).toList();
    final biggest = top.isEmpty ? 1 : top.first.spent;
    final soft = tone.on.withValues(alpha: 0.78);

    Widget stat(String label, int cents, IconData icon) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 14, color: soft),
              const SizedBox(width: 4),
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: soft, fontSize: 11.5, fontWeight: FontWeight.w700))),
            ]),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(hidden ? '₱ ••••' : peso(cents.abs(), compact: true), maxLines: 1, style: heading(17, weight: FontWeight.w800, color: tone.on))),
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          decoration: toneBox(context, tone: tone, color: tone.main, radius: 22, shadow: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Total across ${store.accounts.length} cards', style: TextStyle(color: soft, fontSize: 12.5, fontWeight: FontWeight.w700)),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(hidden ? '₱ ••••••' : peso(store.totalBalance), maxLines: 1, style: heading(32, weight: FontWeight.w800, color: tone.on, height: 1.15))),
            const SizedBox(height: 10),
            Row(children: [
              stat('In this month', month.income, Icons.north_east_rounded),
              stat('Out this month', month.expense, Icons.south_west_rounded),
              stat(month.net >= 0 ? 'Kept' : 'Short', month.net, Icons.savings_rounded),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          Expanded(child: _ActionButton(icon: Icons.south_west_rounded, label: 'Expense', filled: true, onTap: () => onAddTxn())),
          const SizedBox(width: 10),
          Expanded(child: _ActionButton(icon: Icons.north_east_rounded, label: 'Income', filled: false, onTap: () => onAddTxn(income: true))),
          const SizedBox(width: 10),
          Expanded(child: _ActionButton(icon: Icons.swap_horiz_rounded, label: 'Move', filled: false, onTap: onTransfer)),
          const SizedBox(width: 10),
          Expanded(child: _ActionButton(icon: Icons.add_card_rounded, label: 'Card', filled: false, onTap: onAddCard)),
        ]),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 4), child: Text('Your cards', style: heading(16, color: p.text))),
      for (final a in store.accounts)
        Semantics(
          button: true,
          label: '${a.name}, ${hidden ? 'hidden' : peso(store.balanceOf(a))}. Open',
          child: ExcludeSemantics(
            child: InkWell(
              onTap: () => onOpenCard(a.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                child: Row(children: [
                  _MiniCard(color: a.skinData),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(15, weight: FontWeight.w700, color: p.text)),
                      Text([if (a.issuer.isNotEmpty && a.issuer.toLowerCase() != a.name.toLowerCase()) a.issuer, if (a.last4.isNotEmpty) '•••• ${a.last4}' else a.kind.label].join(' · '),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subText, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(hidden ? '₱ ••••' : peso(store.balanceOf(a)), maxLines: 1, style: heading(15.5, weight: FontWeight.w800, color: store.balanceOf(a) < 0 ? budgetDanger : p.text))),
                  ),
                  Icon(Icons.chevron_right_rounded, color: p.subText),
                ]),
              ),
            ),
          ),
        ),
      if (top.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 6), child: Text('Where it went this month', style: heading(16, color: p.text))),
        for (final r in top)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(children: [
              CategoryBadge(icon: r.category.icon, size: 32),
              const SizedBox(width: 10),
              SizedBox(width: 78, child: Text(r.category.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w700))),
              Expanded(child: LimitBar(spent: r.spent, limit: biggest, height: 9, calm: true)),
              const SizedBox(width: 10),
              Text(hidden ? '₱ ••••' : peso(r.spent, compact: true), style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w800)),
            ]),
          ),
      ],
    ]);
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.filled, required this.onTap});
  final IconData icon;
  final String label;

  /// The main action is filled in the card's colour; the others are a wash of it.
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tone = Tone.of(context);
    final fg = filled ? tone.on : p.text;
    return Pressable(
      label: label,
      onTap: onTap,
      builder: (pressed) => Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: toneBox(context, tone: tone, color: filled ? tone.main : tone.soft, radius: 16, shadow: pressed ? 0 : 3),
        child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 21, color: fg),
          const SizedBox(height: 3),
          Text(label, maxLines: 1, style: heading(12.5, weight: FontWeight.w800, color: fg)),
        ]),
      ),
    );
  }
}

class _FlowStat extends StatelessWidget {
  const _FlowStat({required this.label, required this.cents, required this.income, required this.hidden});
  final String label;
  final int cents;
  final bool income;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(income ? Icons.north_east_rounded : Icons.south_west_rounded, size: 14, color: income ? incomeText(p) : p.subText),
          const SizedBox(width: 4),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subText, fontSize: 11.5, fontWeight: FontWeight.w700))),
        ]),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(hidden ? '₱ ••••' : peso(cents, compact: true), maxLines: 1, style: heading(18, weight: FontWeight.w800, color: income ? incomeText(p) : p.text)),
        ),
      ]),
    );
  }
}

class _NoCards extends StatelessWidget {
  const _NoCards({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/cats/budget.png', width: 120, height: 120, excludeFromSemantics: true),
          const SizedBox(height: 14),
          Text('Add your first card', style: heading(22, color: p.text)),
          const SizedBox(height: 8),
          Text(
            'A card can be a debit or credit card, an e-wallet like GCash, or plain cash. Everything stays on this phone.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.subText, fontSize: 14.5, height: 1.4, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded), label: const Text('Add a card')),
        ]),
      ),
    );
  }
}

/// One transaction as a list row: category badge, title, small detail line, signed amount.
class TxnRow extends StatelessWidget {
  const TxnRow({super.key, required this.txn, required this.account, required this.showCard, required this.hidden, required this.now, required this.onTap});
  final Txn txn;
  final Account? account;
  final bool showCard;
  final bool hidden;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final cat = categoryById(txn.category);
    final title = txn.note.isEmpty ? cat.label : txn.note;
    final detail = [
      if (txn.note.isNotEmpty) cat.label,
      if (showCard && account != null) account!.name,
      if (!showCard) dayLabel(txn.day, now),
    ].join(' · ');
    final amount = hidden ? '₱ ••••' : '${txn.income ? '+' : '-'}${peso(txn.cents)}';
    return Semantics(
      button: true,
      label: '${txn.income ? 'Income' : 'Expense'} $title, ${peso(txn.cents)}, ${dayLabel(txn.day, now)}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
            child: Row(children: [
              CategoryBadge(icon: cat.icon, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(15, weight: FontWeight.w700, color: p.text)),
                  if (detail.isNotEmpty) Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subText, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(amount, maxLines: 1, style: heading(16, weight: FontWeight.w800, color: txn.income ? incomeText(p) : p.text))),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Activity tab

class _ActivityTab extends StatefulWidget {
  const _ActivityTab({super.key, this.initialCard, required this.onAdd, required this.onEdit, required this.onDelete});
  final String? initialCard;
  final VoidCallback onAdd;
  final ValueChanged<Txn> onEdit;
  final ValueChanged<Txn> onDelete;

  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab> {
  late ActivityFilter _filter = ActivityFilter(accountId: widget.initialCard);
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openFilters(List<Account> accounts) async {
    final f = await showActivityFilters(context, filter: _filter, accounts: accounts);
    if (f != null) setState(() => _filter = f);
  }

  void _clearAll() {
    _search.clear();
    setState(() => _filter = const ActivityFilter());
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tone = Tone.of(context);
    final store = context.watch<BudgetStore>();
    final now = DateTime.now();

    // A card that was deleted while it was the filter no longer narrows anything.
    final filter = _filter.accountId != null && store.account(_filter.accountId!) == null ? _filter.copyWith(accountId: () => null) : _filter;
    final list = filter.apply(store.txns, accountOf: store.account, now: now);

    // Flatten to day headers and rows so the list builds lazily; day totals are worked out in one pass.
    final rows = <Object>[];
    final dayNet = <DateTime, int>{};
    var income = 0, expense = 0;
    DateTime? last;
    for (final t in list) {
      if (t.day != last) {
        last = t.day;
        rows.add(t.day);
      }
      rows.add(t);
      dayNet[t.day] = (dayNet[t.day] ?? 0) + t.signed;
      if (t.pair == null) t.income ? income += t.cents : expense += t.cents;
    }

    final narrowed = filter.active;
    final badge = filter.sheetCount;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (v) => setState(() => _filter = _filter.copyWith(query: v)),
              decoration: InputDecoration(
                hintText: 'Search',
                isDense: true,
                prefixIcon: Icon(Icons.search_rounded, color: p.subText),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          setState(() => _filter = _filter.copyWith(query: ''));
                        },
                      ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: badge == 0 ? 'Filter' : 'Filter, $badge on',
            child: ExcludeSemantics(
              child: GestureDetector(
                onTap: () => _openFilters(store.accounts),
                child: Stack(clipBehavior: Clip.none, children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: badge == 0 ? toneBox(context, tone: tone, color: tone.soft, radius: 14, shadow: 2) : toneBox(context, tone: tone, color: tone.main, radius: 14, shadow: 2),
                    child: Icon(Icons.tune_rounded, color: badge == 0 ? p.text : tone.on),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: p.ink, shape: BoxShape.circle, border: Border.all(color: p.bg, width: 2)),
                        child: Text('$badge', style: TextStyle(color: p.bg, fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    ),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Add transaction',
            child: ExcludeSemantics(
              child: GestureDetector(
                onTap: widget.onAdd,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: toneBox(context, tone: tone, color: tone.main, radius: 14, shadow: 3),
                  child: Icon(Icons.add_rounded, color: tone.on, size: 26),
                ),
              ),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Row(children: [
          Expanded(child: PillChoice(compact: true, label: 'All', on: filter.flow == ActivityFlow.all, onTap: () => setState(() => _filter = _filter.copyWith(flow: ActivityFlow.all)))),
          const SizedBox(width: 6),
          Expanded(flex: 2, child: PillChoice(compact: true, label: 'Expenses', on: filter.flow == ActivityFlow.expense, onTap: () => setState(() => _filter = _filter.copyWith(flow: ActivityFlow.expense)))),
          const SizedBox(width: 6),
          Expanded(flex: 2, child: PillChoice(compact: true, label: 'Income', on: filter.flow == ActivityFlow.income, onTap: () => setState(() => _filter = _filter.copyWith(flow: ActivityFlow.income)))),
        ]),
      ),
      if (narrowed)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
          child: Row(children: [
            Expanded(
              child: Text(
                list.isEmpty ? 'No matches' : '${list.length} ${list.length == 1 ? 'transaction' : 'transactions'} · In ${peso(income, compact: true)} · Out ${peso(expense, compact: true)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.subText, fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(onPressed: _clearAll, child: const Text('Clear')),
          ]),
        ),
      Expanded(
        child: rows.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      store.txns.isEmpty ? 'No transactions yet. Tap Add to log your first one.' : 'Nothing matches those filters.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.subText, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    if (store.txns.isNotEmpty && narrowed) TextButton(onPressed: _clearAll, child: const Text('Clear search and filters')),
                  ]),
                ),
              )
            // Only the rows on screen are built, so thousands of transactions scroll as smoothly as ten.
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final r = rows[i];
                  if (r is DateTime) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
                      child: Row(children: [
                        Expanded(child: Text(dayLabel(r, now), style: heading(13, weight: FontWeight.w700, color: p.subText))),
                        Text(peso(dayNet[r] ?? 0, sign: true), style: TextStyle(color: p.subText, fontSize: 13, fontWeight: FontWeight.w700)),
                      ]),
                    );
                  }
                  final t = r as Txn;
                  return Dismissible(
                    key: ValueKey(t.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      color: budgetDanger,
                      child: const Icon(Icons.delete_rounded, color: Colors.white),
                    ),
                    onDismissed: (_) => widget.onDelete(t),
                    child: ColoredBox(
                      color: p.bg,
                      child: TxnRow(txn: t, account: store.account(t.accountId), showCard: store.accounts.length > 1, hidden: false, now: now, onTap: () => widget.onEdit(t)),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------
// Budgets tab

class _BudgetsTab extends StatelessWidget {
  const _BudgetsTab();

  Future<void> _editLimit(BuildContext context, CategorySpend row) async {
    final store = context.read<BudgetStore>();
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LimitSheet(category: row.category, current: row.limit, spent: row.spent),
    );
    if (result != null) await store.setLimit(row.category.id, result);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tone = Tone.of(context);
    final store = context.watch<BudgetStore>();
    final sum = store.summary();
    final rows = store.spending();
    final budgeted = store.totalLimit;
    final limitedSpend = rows.where((r) => r.limit > 0).fold(0, (s, r) => s + r.spent);
    final overs = rows.where((r) => r.over).toList();
    final m = store.month;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 28),
      children: [
        Row(children: [
          _MonthArrow(icon: Icons.chevron_left_rounded, label: 'Previous month', onTap: () => store.shiftMonth(-1)),
          Expanded(
            child: Column(children: [
              Text('${_monthFull[m.month - 1]} ${m.year}', style: heading(18, color: p.text)),
              if (store.isCurrentMonth) Text('This month', style: TextStyle(color: p.subText, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
          _MonthArrow(icon: Icons.chevron_right_rounded, label: 'Next month', onTap: () => store.shiftMonth(1)),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: toneBox(context, tone: tone, color: p.card, radius: 20, shadow: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Spent', style: TextStyle(color: p.subText, fontSize: 12.5, fontWeight: FontWeight.w700)),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(peso(sum.expense), maxLines: 1, style: heading(30, weight: FontWeight.w800, color: p.text, height: 1.1)))),
              if (budgeted > 0) ...[
                const SizedBox(width: 8),
                Flexible(child: Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('of ${peso(budgeted, compact: true)} budgeted', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subText, fontSize: 13, fontWeight: FontWeight.w600)))),
              ],
            ]),
            if (budgeted > 0) ...[
              const SizedBox(height: 8),
              LimitBar(spent: limitedSpend, limit: budgeted, height: 12),
              const SizedBox(height: 6),
              Text(
                limitedSpend > budgeted ? '${peso(limitedSpend - budgeted, compact: true)} over your limits' : '${peso(budgeted - limitedSpend, compact: true)} left in your limits',
                style: TextStyle(color: limitedSpend > budgeted ? budgetDanger : p.subText, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _MiniFlow(label: 'In', value: peso(sum.income, compact: true), color: incomeText(p))),
              Expanded(child: _MiniFlow(label: 'Out', value: peso(sum.expense, compact: true), color: p.text)),
              Expanded(child: _MiniFlow(label: sum.net >= 0 ? 'Kept' : 'Short', value: peso(sum.net.abs(), compact: true), color: sum.net >= 0 ? p.text : budgetDanger)),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        Text('By category', style: heading(16, color: p.text)),
        Text(overs.isEmpty ? 'Tap a category to set a monthly limit.' : '${overs.map((o) => o.category.label).join(', ')} ${overs.length == 1 ? 'is' : 'are'} over the limit.',
            style: TextStyle(color: overs.isEmpty ? p.subText : budgetDanger, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        for (final r in rows) _CategoryRow(row: r, onTap: () => _editLimit(context, r)),
      ],
    );
  }
}

class _MonthArrow extends StatelessWidget {
  const _MonthArrow({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tone = Tone.of(context);
    return Pressable(
      label: label,
      lift: 2,
      onTap: onTap,
      builder: (pressed) => Container(
        width: 44,
        height: 44,
        decoration: toneBox(context, tone: tone, color: tone.soft, radius: 14, shadow: pressed ? 0 : 2),
        child: Icon(icon, color: p.text, size: 28),
      ),
    );
  }
}

class _MiniFlow extends StatelessWidget {
  const _MiniFlow({required this.label, required this.value, required this.color});
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: p.subText, fontSize: 12, fontWeight: FontWeight.w700)),
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, maxLines: 1, style: heading(16, weight: FontWeight.w800, color: color))),
    ]);
  }
}

/// A thick outlined bar: filled in the card's colour, red only once the limit is passed.
class LimitBar extends StatelessWidget {
  const LimitBar({super.key, required this.spent, required this.limit, this.height = 10, this.calm = false});
  final int spent, limit;
  final double height;

  /// A savings bar: filling up is good news, so it never turns red.
  final bool calm;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tone = Tone.of(context);
    final f = limit <= 0 ? 0.0 : (spent / limit).clamp(0.0, 1.0);
    final over = !calm && limit > 0 && spent > limit;
    return Container(
      height: height,
      // A soft track with no outline; it sits on the page and on the quiet cards alike.
      decoration: BoxDecoration(color: p.ink.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(height)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(widthFactor: f, heightFactor: 1, child: ColoredBox(color: over ? budgetDanger : tone.main)),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.row, required this.onTap});
  final CategorySpend row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = row.category;
    final hasLimit = row.limit > 0;
    final right = hasLimit ? '${peso(row.spent, compact: true)} / ${peso(row.limit, compact: true)}' : (row.spent > 0 ? peso(row.spent, compact: true) : 'Set limit');
    return Semantics(
      button: true,
      label: '${c.label}, spent ${peso(row.spent)}${hasLimit ? ' of ${peso(row.limit)}' : ', no limit'}',
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              CategoryBadge(icon: c.icon, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(c.label, style: heading(15, weight: FontWeight.w700, color: p.text))),
                    Text(right, style: TextStyle(color: row.over ? budgetDanger : (hasLimit || row.spent > 0 ? p.text : p.subText), fontSize: 13.5, fontWeight: FontWeight.w800)),
                  ]),
                  if (hasLimit) ...[
                    const SizedBox(height: 5),
                    LimitBar(spent: row.spent, limit: row.limit, height: 9),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _LimitSheet extends StatefulWidget {
  const _LimitSheet({required this.category, required this.current, required this.spent});
  final Category category;
  final int current, spent;

  @override
  State<_LimitSheet> createState() => _LimitSheetState();
}

class _LimitSheetState extends State<_LimitSheet> {
  final _key = GlobalKey<FormState>();
  late final _c = TextEditingController(text: widget.current > 0 ? centsToField(widget.current) : '');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 18 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _key,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CategoryBadge(icon: widget.category.icon),
            const SizedBox(width: 12),
            Expanded(child: Text('${widget.category.label} limit', style: heading(21, color: p.text))),
          ]),
          const SizedBox(height: 6),
          Text('Spent so far this month: ${peso(widget.spent)}', style: TextStyle(color: p.subText, fontSize: 13.5, fontWeight: FontWeight.w600)),
          const FieldLabel('Monthly limit', dense: true),
          TextFormField(
            controller: _c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: '₱ ', hintText: '5000'),
            validator: (v) => parseCents(v ?? '') == null ? 'Enter an amount like 5000' : null,
          ),
          const SizedBox(height: 14),
          Row(children: [
            if (widget.current > 0) ...[
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, 0), child: const Text('Remove limit'))),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: FilledButton(
                style: toneButton(context),
                onPressed: () {
                  if (_key.currentState!.validate()) Navigator.pop(context, parseCents(_c.text));
                },
                child: const Text('Save limit'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Plans tab: monthly bills and savings goals

const _ordinalSuffix = ['th', 'st', 'nd', 'rd'];
String ordinal(int n) {
  final v = n % 100;
  final suffix = (v >= 11 && v <= 13) ? 'th' : _ordinalSuffix[(n % 10) < 4 ? n % 10 : 0];
  return '$n$suffix';
}

class _PlansTab extends StatelessWidget {
  const _PlansTab({required this.onBill, required this.onSub, required this.onSubLink, required this.onGoal, required this.onGoalMoney});
  final ValueChanged<Bill?> onBill;
  final ValueChanged<Subscription?> onSub;
  final ValueChanged<Subscription> onSubLink;
  final ValueChanged<Goal?> onGoal;
  final void Function(Goal goal, bool adding) onGoalMoney;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final store = context.watch<BudgetStore>();
    final bills = [...store.bills]..sort((a, b) => store.nextDue(a).compareTo(store.nextDue(b)));
    final now = DateTime.now();
    final monthly = bills.fold(0, (s, b) => s + b.cents);
    // Active ones by next charge, then paused, then cancelled.
    final subs = [...store.subscriptions]..sort((a, b) {
        final byStatus = a.status.index.compareTo(b.status.index);
        return byStatus != 0 ? byStatus : a.next.compareTo(b.next);
      });
    final saved = store.subscriptionsSavedYearly;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 32),
      children: [
        _SectionHead(title: 'Monthly bills', addLabel: 'Add bill', onAdd: store.accounts.isEmpty ? null : () => onBill(null)),
        if (store.accounts.isEmpty)
          const _Hint('Add a card first, then set up the bills it pays.')
        else if (bills.isEmpty)
          const _Hint('Rent, internet, subscriptions: add them once and Faelen logs each one on its due day.')
        else ...[
          Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${peso(monthly, compact: true)} a month in total', style: TextStyle(color: p.subText, fontSize: 13.5, fontWeight: FontWeight.w600))),
          for (final b in bills) _BillRow(bill: b, account: store.account(b.accountId), next: store.nextDue(b), showCard: store.accounts.length > 1, now: now, onTap: () => onBill(b)),
        ],
        const SizedBox(height: 20),
        _SectionHead(title: 'Subscriptions', addLabel: 'Add subscription', onAdd: store.accounts.isEmpty ? null : () => onSub(null)),
        if (store.accounts.isEmpty)
          const _Hint('Add a card first, then add the subscriptions it pays.')
        else if (subs.isEmpty)
          const _Hint('Netflix, Spotify, iCloud: add each one and Faelen logs every charge, warns you before it renews and keeps its cancel page one tap away.')
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              store.subscriptionsMonthly == 0 && subs.every((s) => !s.active)
                  ? 'Nothing is charging right now'
                  : '${peso(store.subscriptionsMonthly, compact: true)} a month · ${peso(store.subscriptionsYearly, compact: true)} a year',
              style: TextStyle(color: p.subText, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
          if (saved > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('Cancelled ones save you ${peso(saved, compact: true)} a year', style: TextStyle(color: incomeText(p), fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
          for (final sub in subs)
            _SubRow(sub: sub, account: store.account(sub.accountId), showCard: store.accounts.length > 1, now: now, onTap: () => onSub(sub), onLink: sub.link.isEmpty ? null : () => onSubLink(sub)),
        ],
        const SizedBox(height: 20),
        _SectionHead(title: 'Savings goals', addLabel: 'Add goal', onAdd: () => onGoal(null)),
        if (store.goals.isEmpty)
          const _Hint('Set a target, then add money as you save. Goals are separate jars: they do not change any card balance.')
        else
          for (final g in store.goals) ...[
            _GoalCard(goal: g, onEdit: () => onGoal(g), onAdd: () => onGoalMoney(g, true), onTake: () => onGoalMoney(g, false)),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, required this.addLabel, required this.onAdd});
  final String title, addLabel;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tone = Tone.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(child: Text(title, style: heading(17, color: p.text))),
        if (onAdd != null)
          Pressable(
            label: addLabel,
            lift: 2,
            onTap: onAdd,
            builder: (pressed) => Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: toneBox(context, tone: tone, color: tone.main, radius: 12, shadow: pressed ? 0 : 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_rounded, size: 20, color: tone.on),
                const SizedBox(width: 4),
                Text('Add', style: heading(14, weight: FontWeight.w800, color: tone.on)),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(color: Palette.of(context).subText, fontSize: 14, height: 1.4, fontWeight: FontWeight.w500));
}

class _BillRow extends StatelessWidget {
  const _BillRow({required this.bill, required this.account, required this.next, required this.showCard, required this.now, required this.onTap});
  final Bill bill;
  final Account? account;
  final DateTime next;
  final bool showCard;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final cat = categoryById(bill.category);
    final days = next.difference(dateOnly(now)).inDays;
    final when = days <= 0 ? 'Due today' : (days == 1 ? 'Due tomorrow' : dayLabel(next, now));
    return Semantics(
      button: true,
      label: '${bill.name}, ${peso(bill.cents)} every month on the ${ordinal(bill.day)}. $when',
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              CategoryBadge(icon: cat.icon, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(bill.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(15, weight: FontWeight.w700, color: p.text)),
                  Text('$when · monthly on the ${ordinal(bill.day)}${showCard && account != null ? ' · ${account!.name}' : ''}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subText, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(peso(bill.cents, compact: true), maxLines: 1, style: heading(16, weight: FontWeight.w800, color: p.text))),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "Tomorrow", "in 5 days" or the date; [trial] says the charge is the end of a free trial.
String _renewText(DateTime next, DateTime now, {required bool trial}) {
  final days = next.difference(dateOnly(now)).inDays;
  final when = days <= 0 ? 'today' : (days == 1 ? 'tomorrow' : (days <= 30 ? 'in $days days' : 'on ${dayLabel(next, now)}'));
  return trial ? 'Trial ends $when' : (days <= 0 ? 'Renews today' : (days == 1 ? 'Renews tomorrow' : 'Renews $when'));
}

class _SubRow extends StatelessWidget {
  const _SubRow({required this.sub, required this.account, required this.showCard, required this.now, required this.onTap, required this.onLink});
  final Subscription sub;
  final Account? account;
  final bool showCard;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tone = Tone.of(context);
    final cat = categoryById(sub.category);
    final days = sub.next.difference(dateOnly(now)).inDays;
    final soon = sub.active && days <= 3;
    final chipText = switch (sub.status) {
      SubStatus.active => _renewText(sub.next, now, trial: sub.trial),
      SubStatus.paused => 'Paused',
      SubStatus.cancelled => 'Cancelled',
    };
    final per = sub.cycle == BillingCycle.monthly ? 'every month' : (sub.cycle == BillingCycle.weekly ? 'every week' : 'every ${sub.cycle.unit}');
    final chipFg = soon ? (identical(p, Palette.dark) ? const Color(0xFFFF8A8A) : budgetDanger) : p.text;
    final chipBg = soon ? budgetDanger.withValues(alpha: 0.12) : tone.soft;
    return Opacity(
      opacity: sub.active ? 1 : 0.62,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
            child: Semantics(
              button: true,
              label: '${sub.name}, ${peso(sub.cents)} $per. $chipText',
              child: ExcludeSemantics(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onTap,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Row(children: [
                      CategoryBadge(icon: cat.icon, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(sub.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(15, weight: FontWeight.w700, color: p.text)),
                          const SizedBox(height: 3),
                          Row(children: [
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(8)),
                                child: Text(chipText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: chipFg, fontSize: 12, fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ]),
                        ]),
                      ),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 104),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(peso(sub.cents, compact: true), maxLines: 1, style: heading(16, weight: FontWeight.w800, color: p.text))),
                          Text('${sub.cycle.label}${showCard && account != null ? ' · ${account!.name}' : ''}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subText, fontSize: 12, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          if (onLink != null)
            IconButton(
              tooltip: 'Open the page for ${sub.name}',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(Icons.open_in_new_rounded, size: 20, color: p.subText),
              onPressed: onLink,
            ),
        ]),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.onEdit, required this.onAdd, required this.onTake});
  final Goal goal;
  final VoidCallback onEdit, onAdd, onTake;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tone = Tone.of(context); // goals share the screen's colour family
    final pct = goal.targetCents == 0 ? 0 : (goal.savedCents * 100 ~/ goal.targetCents);
    return Container(
      decoration: toneBox(context, tone: tone, color: p.card, radius: 20, shadow: 4),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
          button: true,
          label: 'Edit ${goal.name}',
          child: ExcludeSemantics(
            child: InkWell(
              onTap: onEdit,
              child: Container(
                color: tone.main,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(children: [
                  Expanded(child: Text(goal.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(16, weight: FontWeight.w800, color: tone.on))),
                  if (goal.reached) Icon(Icons.check_circle_rounded, color: tone.on, size: 22) else Text('$pct%', style: heading(15, weight: FontWeight.w800, color: tone.on)),
                ]),
              ),
            ),
          ),
        ),
        Container(height: 2, color: tone.line),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(peso(goal.savedCents, compact: true), maxLines: 1, style: heading(25, weight: FontWeight.w800, color: p.text, height: 1.1)))),
              const SizedBox(width: 8),
              Flexible(child: Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('of ${peso(goal.targetCents, compact: true)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subText, fontSize: 13.5, fontWeight: FontWeight.w600)))),
            ]),
            const SizedBox(height: 8),
            LimitBar(spent: goal.savedCents, limit: goal.targetCents, height: 12, calm: true),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _GoalButton(tone: tone, label: 'Add money', icon: Icons.add_rounded, filled: true, onTap: onAdd)),
              if (goal.savedCents > 0) ...[
                const SizedBox(width: 10),
                Expanded(child: _GoalButton(tone: tone, label: 'Take out', icon: Icons.remove_rounded, filled: false, onTap: onTake)),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _GoalButton extends StatelessWidget {
  const _GoalButton({required this.tone, required this.label, required this.icon, required this.filled, required this.onTap});
  final Tone tone;
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fg = filled ? tone.on : p.text;
    return Pressable(
      label: label,
      lift: 2,
      onTap: onTap,
      builder: (pressed) => Container(
        constraints: const BoxConstraints(minHeight: 44),
        decoration: toneBox(context, tone: tone, color: filled ? tone.main : tone.soft, radius: 12, shadow: pressed ? 0 : 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 19, color: fg),
          const SizedBox(width: 5),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(14, weight: FontWeight.w800, color: fg))),
        ]),
      ),
    );
  }
}
