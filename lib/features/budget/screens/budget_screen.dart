import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../models/budget_models.dart';
import '../state/budget_store.dart';
import '../widgets/account_form_sheet.dart';
import '../widgets/bank_card.dart';
import '../widgets/budget_widgets.dart';
import '../widgets/plans_sheets.dart';
import '../widgets/txn_form_sheet.dart';

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
class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> with WidgetsBindingObserver {
  _Tab _tab = _Tab.cards;

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
    // A new day may have made a monthly bill due.
    if (state == AppLifecycleState.resumed && mounted) context.read<BudgetStore>().postDueBills();
  }

  /// Set by "See all" on a card: the Activity tab opens already filtered to it.
  String? _activityCard;
  int _cardPage = 0;

  BudgetStore get _store => context.read<BudgetStore>();

  Future<void> _addTxn({String? accountId, bool income = false}) async {
    final store = _store;
    if (store.accounts.isEmpty) return _addAccount();
    final t = await showTxnForm(context, accounts: store.accounts, newId: store.newId, accountId: accountId, income: income);
    if (t != null) await store.saveTxn(t);
  }

  Future<void> _addAccount() async {
    final store = _store;
    final a = await showAccountForm(context, newId: store.newId, usedSkins: store.accounts.length);
    if (a == null) return;
    await store.saveAccount(a);
    if (mounted) setState(() => _cardPage = store.accounts.indexWhere((x) => x.id == a.id).clamp(0, 99));
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
            action: SnackBarAction(label: 'Undo', onPressed: () => store.restoreAccount(gone.account, gone.txns)),
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
                page: _cardPage,
                onPage: (i) => setState(() => _cardPage = i),
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
                onEdit: _editTxn,
                onDelete: _deleteTxn,
              ),
            _Tab.budgets => const _BudgetsTab(),
            _Tab.plans => _PlansTab(onBill: _editBill, onGoal: _editGoal, onGoalMoney: _goalMoney),
          };

    return ColoredBox(
      color: p.bg,
      child: Scaffold(
        floatingActionButton: store.loading || store.accounts.isEmpty || _tab == _Tab.budgets || _tab == _Tab.plans ? null : _AddFab(hasCards: store.accounts.isNotEmpty, onTap: () => _addTxn(accountId: _selectedCardId(store))),
        body: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(children: [
                const _Header(),
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

  String? _selectedCardId(BudgetStore s) => _tab == _Tab.cards && _cardPage < s.accounts.length ? s.accounts[_cardPage].id : null;
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 20, 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Row(children: [
          IconButton(tooltip: 'Back to modules', onPressed: () => Navigator.maybePop(context), icon: Icon(Icons.arrow_back_rounded, color: p.text)),
          Image.asset('assets/cats/budget.png', width: 44, height: 44, excludeFromSemantics: true),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Budget', style: heading(22, color: p.text, height: 1.1)),
              Text('Cards, spending & limits', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subText, fontSize: 12, fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _AddFab extends StatelessWidget {
  const _AddFab({required this.hasCards, required this.onTap});
  final bool hasCards;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final label = hasCards ? 'Add transaction' : 'Add card';
    return Pressable(
      label: label,
      onTap: onTap,
      builder: (pressed) => Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: brutal(p, color: p.primary, radius: 18, shadow: pressed ? 0 : 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add_rounded, color: p.onPrimary, size: 26),
          const SizedBox(width: 8),
          Text(hasCards ? 'Add' : 'Add card', style: heading(16, weight: FontWeight.w800, color: p.onPrimary)),
        ]),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.tab, required this.onSelect});
  final _Tab tab;
  final ValueChanged<_Tab> onSelect;

  static const _items = [
    (_Tab.cards, 'Cards', Icons.credit_card_rounded, Color(0xFFB99BFF)),
    (_Tab.activity, 'Activity', Icons.swap_vert_rounded, Color(0xFF7CC8FF)),
    (_Tab.budgets, 'Budgets', Icons.donut_small_rounded, Color(0xFFFFD166)),
    (_Tab.plans, 'Plans', Icons.event_repeat_rounded, Color(0xFF7BD389)),
  ];

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.ink, width: 2))),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 70),
          child: Row(children: [
            for (final (t, label, icon, color) in _items)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: tab == t,
                  label: label,
                  child: ExcludeSemantics(
                    child: InkResponse(
                      onTap: () => onSelect(t),
                      radius: 36,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 52,
                          height: 32,
                          decoration: tab == t ? brutal(p, color: color, radius: 12, shadow: 2) : BoxDecoration(color: color.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(12)),
                          child: Icon(icon, size: 22, color: tab == t ? onTile : p.text),
                        ),
                        const SizedBox(height: 4),
                        Text(label, style: TextStyle(fontSize: 11, fontWeight: tab == t ? FontWeight.w800 : FontWeight.w600, color: p.text)),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Cards tab

class _CardsTab extends StatefulWidget {
  const _CardsTab({
    required this.page,
    required this.onPage,
    required this.onAddCard,
    required this.onTransfer,
    required this.onEditCard,
    required this.onAddTxn,
    required this.onEditTxn,
    required this.onSeeAll,
  });
  final int page;
  final ValueChanged<int> onPage;
  final VoidCallback onAddCard;
  final ValueChanged<String> onTransfer;
  final ValueChanged<Account> onEditCard;
  final Future<void> Function({String? accountId, bool income}) onAddTxn;
  final ValueChanged<Txn> onEditTxn;
  final ValueChanged<String> onSeeAll;

  @override
  State<_CardsTab> createState() => _CardsTabState();
}

class _CardsTabState extends State<_CardsTab> {
  PageController? _controller;
  double _fraction = 0;
  bool _hidden = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  PageController _controllerFor(double fraction) {
    if (_controller == null || _fraction != fraction) {
      _controller?.dispose();
      _fraction = fraction;
      _controller = PageController(viewportFraction: fraction, initialPage: widget.page);
    }
    return _controller!;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final store = context.watch<BudgetStore>();
    final accounts = store.accounts;

    if (accounts.isEmpty) return _NoCards(onAdd: widget.onAddCard);

    final page = widget.page.clamp(0, accounts.length);
    final selected = page < accounts.length ? accounts[page] : null;
    final recent = store.recent(accountId: selected?.id, limit: 5);
    final month = store.summary(of: DateTime.now(), accountId: selected?.id);
    final now = DateTime.now();

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 110),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Total across ${accounts.length} ${accounts.length == 1 ? 'card' : 'cards'}', style: TextStyle(color: p.subText, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(_hidden ? '₱ ••••••' : peso(store.totalBalance), style: heading(30, weight: FontWeight.w800, color: p.text, height: 1.1)),
              ]),
            ),
            Semantics(
              button: true,
              label: _hidden ? 'Show balances' : 'Hide balances',
              child: ExcludeSemantics(
                child: GestureDetector(
                  onTap: () => setState(() => _hidden = !_hidden),
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: brutal(p, color: p.field, radius: 14, shadow: 3),
                    child: Icon(_hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: p.text),
                  ),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          final fraction = w < 460 ? 0.88 : 400 / w;
          final cardW = w * fraction - 16;
          return SizedBox(
            height: cardW / BankCard.aspect + 14,
            child: PageView.builder(
              controller: _controllerFor(fraction),
              itemCount: accounts.length + 1,
              onPageChanged: widget.onPage,
              clipBehavior: Clip.none,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: i == accounts.length
                      ? AddCardSlot(onTap: widget.onAddCard)
                      : GestureDetector(
                          onTap: () => widget.onEditCard(accounts[i]),
                          child: BankCard(account: accounts[i], balance: store.balanceOf(accounts[i]), hidden: _hidden),
                        ),
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i <= accounts.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == page ? 20 : 7,
              height: 7,
              decoration: BoxDecoration(color: i == page ? p.ink : p.outline, borderRadius: BorderRadius.circular(4)),
            ),
        ]),
        if (selected != null) ...[
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Expanded(child: _ActionButton(icon: Icons.south_west_rounded, label: 'Expense', color: p.primary, onTap: () => widget.onAddTxn(accountId: selected.id))),
              const SizedBox(width: 10),
              Expanded(child: _ActionButton(icon: Icons.north_east_rounded, label: 'Income', color: const Color(0xFF7BD389), onTap: () => widget.onAddTxn(accountId: selected.id, income: true))),
              const SizedBox(width: 10),
              Expanded(child: _ActionButton(icon: Icons.swap_horiz_rounded, label: 'Move', color: const Color(0xFF7CC8FF), onTap: () => widget.onTransfer(selected.id))),
              const SizedBox(width: 10),
              Expanded(child: _ActionButton(icon: Icons.tune_rounded, label: 'Edit', color: const Color(0xFFB99BFF), onTap: () => widget.onEditCard(selected))),
            ]),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Expanded(child: _FlowStat(label: 'In this month', cents: month.income, income: true, hidden: _hidden)),
              const SizedBox(width: 12),
              Expanded(child: _FlowStat(label: 'Out this month', cents: month.expense, income: false, hidden: _hidden)),
            ]),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Expanded(child: Text('Recent', style: heading(17, color: p.text))),
              if (recent.isNotEmpty)
                TextButton(onPressed: () => widget.onSeeAll(selected.id), child: const Text('See all')),
            ]),
          ),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text('Nothing on ${selected.name} yet. Tap Add to log a purchase.', style: TextStyle(color: p.subText, fontSize: 14, fontWeight: FontWeight.w500)),
            )
          else
            for (final t in recent)
              TxnRow(txn: t, account: selected, showCard: false, hidden: _hidden, now: now, onTap: () => widget.onEditTxn(t)),
        ] else
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Text('Swipe back to your cards, or add another one here.', textAlign: TextAlign.center, style: TextStyle(color: p.subText, fontSize: 14, fontWeight: FontWeight.w500)),
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Pressable(
      label: label,
      onTap: onTap,
      builder: (pressed) => Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: brutal(p, color: color, radius: 16, shadow: pressed ? 0 : 3),
        child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 22, color: onTile),
          const SizedBox(height: 4),
          Text(label, style: heading(13, weight: FontWeight.w800, color: onTile)),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.outline, width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(income ? Icons.north_east_rounded : Icons.south_west_rounded, size: 15, color: income ? incomeText(p) : p.subText),
          const SizedBox(width: 5),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subText, fontSize: 12, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(hidden ? '₱ ••••' : peso(cents, compact: true), maxLines: 1, style: heading(19, weight: FontWeight.w800, color: income ? incomeText(p) : p.text)),
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
            child: Row(children: [
              CategoryBadge(icon: cat.icon, color: cat.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(15.5, weight: FontWeight.w700, color: p.text)),
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

enum _Flow { all, expense, income }

class _ActivityTab extends StatefulWidget {
  const _ActivityTab({super.key, this.initialCard, required this.onEdit, required this.onDelete});
  final String? initialCard;
  final ValueChanged<Txn> onEdit;
  final ValueChanged<Txn> onDelete;

  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab> {
  _Flow _flow = _Flow.all;
  late String? _card = widget.initialCard;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final store = context.watch<BudgetStore>();
    final now = DateTime.now();
    final card = _card != null && store.account(_card!) != null ? _card : null;
    final list = [
      for (final t in store.recent(accountId: card))
        if (_flow == _Flow.all || (_flow == _Flow.income) == t.income) t,
    ];

    // Flatten to day headers and rows so the list builds lazily.
    final rows = <Object>[];
    DateTime? last;
    for (final t in list) {
      if (t.day != last) {
        last = t.day;
        rows.add(t.day);
      }
      rows.add(t);
    }
    int dayNet(DateTime d) => list.where((t) => t.day == d).fold(0, (s, t) => s + t.signed);

    return Column(children: [
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
          children: [
            PillChoice(label: 'All', on: _flow == _Flow.all, onTap: () => setState(() => _flow = _Flow.all)),
            const SizedBox(width: 8),
            PillChoice(label: 'Expenses', on: _flow == _Flow.expense, onTap: () => setState(() => _flow = _Flow.expense)),
            const SizedBox(width: 8),
            PillChoice(label: 'Income', on: _flow == _Flow.income, onTap: () => setState(() => _flow = _Flow.income)),
            if (store.accounts.length > 1) ...[
              Container(width: 1.5, margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: p.outline),
              PillChoice(label: 'Every card', on: card == null, onTap: () => setState(() => _card = null)),
              for (final a in store.accounts) ...[
                const SizedBox(width: 8),
                PillChoice(label: a.name, dot: a.skinData.face, on: card == a.id, onTap: () => setState(() => _card = a.id)),
              ],
            ],
          ],
        ),
      ),
      Expanded(
        child: rows.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    store.txns.isEmpty ? 'No transactions yet. Tap Add to log your first one.' : 'Nothing matches those filters.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.subText, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 110),
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final r = rows[i];
                  if (r is DateTime) {
                    final net = dayNet(r);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                      child: Row(children: [
                        Expanded(child: Text(dayLabel(r, now), style: heading(13.5, weight: FontWeight.w700, color: p.subText))),
                        Text(peso(net, sign: true), style: TextStyle(color: p.subText, fontSize: 13, fontWeight: FontWeight.w700)),
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
    final store = context.watch<BudgetStore>();
    final sum = store.summary();
    final rows = store.spending();
    final budgeted = store.totalLimit;
    final limitedSpend = rows.where((r) => r.limit > 0).fold(0, (s, r) => s + r.spent);
    final overs = rows.where((r) => r.over).toList();
    final m = store.month;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        Row(children: [
          _MonthArrow(icon: Icons.chevron_left_rounded, label: 'Previous month', onTap: () => store.shiftMonth(-1)),
          Expanded(
            child: Column(children: [
              Text('${_monthFull[m.month - 1]} ${m.year}', style: heading(19, color: p.text)),
              if (store.isCurrentMonth) Text('This month', style: TextStyle(color: p.subText, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
          _MonthArrow(icon: Icons.chevron_right_rounded, label: 'Next month', onTap: () => store.shiftMonth(1)),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: brutal(p, color: p.card, radius: 20, shadow: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Spent', style: TextStyle(color: p.subText, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(peso(sum.expense), maxLines: 1, style: heading(32, weight: FontWeight.w800, color: p.text, height: 1.1)))),
              if (budgeted > 0) ...[
                const SizedBox(width: 8),
                Flexible(child: Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('of ${peso(budgeted, compact: true)} budgeted', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subText, fontSize: 13, fontWeight: FontWeight.w600)))),
              ],
            ]),
            if (budgeted > 0) ...[
              const SizedBox(height: 12),
              LimitBar(spent: limitedSpend, limit: budgeted, height: 14),
              const SizedBox(height: 8),
              Text(
                limitedSpend > budgeted ? '${peso(limitedSpend - budgeted, compact: true)} over your limits' : '${peso(budgeted - limitedSpend, compact: true)} left in your limits',
                style: TextStyle(color: limitedSpend > budgeted ? budgetDanger : p.subText, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _MiniFlow(label: 'In', value: peso(sum.income, compact: true), color: incomeText(p))),
              Expanded(child: _MiniFlow(label: 'Out', value: peso(sum.expense, compact: true), color: p.text)),
              Expanded(child: _MiniFlow(label: sum.net >= 0 ? 'Kept' : 'Short', value: peso(sum.net.abs(), compact: true), color: sum.net >= 0 ? p.text : budgetDanger)),
            ]),
          ]),
        ),
        const SizedBox(height: 22),
        Text('By category', style: heading(17, color: p.text)),
        const SizedBox(height: 4),
        Text(overs.isEmpty ? 'Tap a category to set a monthly limit.' : '${overs.map((o) => o.category.label).join(', ')} ${overs.length == 1 ? 'is' : 'are'} over the limit.',
            style: TextStyle(color: overs.isEmpty ? p.subText : budgetDanger, fontSize: 13.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
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
    return Pressable(
      label: label,
      lift: 2,
      onTap: onTap,
      builder: (pressed) => Container(
        width: 44,
        height: 44,
        decoration: brutal(p, color: p.field, radius: 14, shadow: pressed ? 0 : 2),
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
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, maxLines: 1, style: heading(16.5, weight: FontWeight.w800, color: color))),
    ]);
  }
}

/// A thick outlined bar: fills with the accent, and turns red past 100%.
class LimitBar extends StatelessWidget {
  const LimitBar({super.key, required this.spent, required this.limit, this.height = 10, this.calm = false});
  final int spent, limit;
  final double height;

  /// A savings bar: filling up is good news, so it never turns amber or red.
  final bool calm;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final f = limit <= 0 ? 0.0 : (spent / limit).clamp(0.0, 1.0);
    final over = !calm && limit > 0 && spent > limit;
    final warn = !calm && !over && limit > 0 && spent / limit >= 0.85;
    return Container(
      height: height,
      decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(height), border: Border.all(color: p.ink, width: 1.5)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(widthFactor: f, heightFactor: 1, child: ColoredBox(color: over ? budgetDanger : (warn ? const Color(0xFFFFB020) : const Color(0xFF7BD389)))),
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
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              CategoryBadge(icon: c.icon, color: c.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(c.label, style: heading(15.5, weight: FontWeight.w700, color: p.text))),
                    Text(right, style: TextStyle(color: row.over ? budgetDanger : (hasLimit || row.spent > 0 ? p.text : p.subText), fontSize: 13.5, fontWeight: FontWeight.w800)),
                  ]),
                  if (hasLimit) ...[
                    const SizedBox(height: 6),
                    LimitBar(spent: row.spent, limit: row.limit),
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
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _key,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CategoryBadge(icon: widget.category.icon, color: widget.category.color),
            const SizedBox(width: 12),
            Expanded(child: Text('${widget.category.label} limit', style: heading(21, color: p.text))),
          ]),
          const SizedBox(height: 6),
          Text('Spent so far this month: ${peso(widget.spent)}', style: TextStyle(color: p.subText, fontSize: 13.5, fontWeight: FontWeight.w600)),
          const FieldLabel('Monthly limit'),
          TextFormField(
            controller: _c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: '₱ ', hintText: '5000'),
            validator: (v) => parseCents(v ?? '') == null ? 'Enter an amount like 5000' : null,
          ),
          const SizedBox(height: 16),
          Row(children: [
            if (widget.current > 0) ...[
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, 0), child: const Text('Remove limit'))),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
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
  const _PlansTab({required this.onBill, required this.onGoal, required this.onGoalMoney});
  final ValueChanged<Bill?> onBill;
  final ValueChanged<Goal?> onGoal;
  final void Function(Goal goal, bool adding) onGoalMoney;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final store = context.watch<BudgetStore>();
    final bills = [...store.bills]..sort((a, b) => store.nextDue(a).compareTo(store.nextDue(b)));
    final now = DateTime.now();
    final monthly = bills.fold(0, (s, b) => s + b.cents);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        _SectionHead(title: 'Monthly bills', addLabel: 'Add bill', onAdd: store.accounts.isEmpty ? null : () => onBill(null)),
        if (store.accounts.isEmpty)
          _Hint('Add a card first, then set up the bills it pays.')
        else if (bills.isEmpty)
          _Hint('Rent, internet, subscriptions: add them once and Faelen logs each one on its due day.')
        else ...[
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('${peso(monthly, compact: true)} a month in total', style: TextStyle(color: p.subText, fontSize: 13.5, fontWeight: FontWeight.w600))),
          for (final b in bills)
            _BillRow(bill: b, account: store.account(b.accountId), next: store.nextDue(b), showCard: store.accounts.length > 1, now: now, onTap: () => onBill(b)),
        ],
        const SizedBox(height: 26),
        _SectionHead(title: 'Savings goals', addLabel: 'Add goal', onAdd: () => onGoal(null)),
        if (store.goals.isEmpty)
          _Hint('Set a target, then add money as you save. Goals are separate jars: they do not change any card balance.')
        else
          for (final g in store.goals) ...[
            _GoalCard(goal: g, onEdit: () => onGoal(g), onAdd: () => onGoalMoney(g, true), onTake: () => onGoalMoney(g, false)),
            const SizedBox(height: 14),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(child: Text(title, style: heading(18, color: p.text))),
        if (onAdd != null)
          Pressable(
            label: addLabel,
            lift: 2,
            onTap: onAdd,
            builder: (pressed) => Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: brutal(p, color: p.primary, radius: 12, shadow: pressed ? 0 : 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_rounded, size: 20, color: p.onPrimary),
                const SizedBox(width: 4),
                Text('Add', style: heading(14, weight: FontWeight.w800, color: p.onPrimary)),
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
    final when = days <= 0 ? 'Due today' : (days == 1 ? 'Due tomorrow' : 'Next ${dayLabel(next, now)}');
    return Semantics(
      button: true,
      label: '${bill.name}, ${peso(bill.cents)} every month on the ${ordinal(bill.day)}. $when',
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(children: [
              CategoryBadge(icon: cat.icon, color: cat.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(bill.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(15.5, weight: FontWeight.w700, color: p.text)),
                  Text('$when · every ${ordinal(bill.day)}${showCard && account != null ? ' · ${account!.name}' : ''}',
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

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.onEdit, required this.onAdd, required this.onTake});
  final Goal goal;
  final VoidCallback onEdit, onAdd, onTake;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final skin = cardSkins[goal.skin.clamp(0, cardSkins.length - 1)];
    final pct = goal.targetCents == 0 ? 0 : (goal.savedCents * 100 ~/ goal.targetCents);
    return Container(
      decoration: brutal(p, color: p.card, radius: 20, shadow: 4),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
          button: true,
          label: 'Edit ${goal.name}',
          child: ExcludeSemantics(
            child: InkWell(
              onTap: onEdit,
              child: Container(
                color: skin.face,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(children: [
                  Expanded(child: Text(goal.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(17, weight: FontWeight.w800, color: skin.dark ? Colors.white : onTile))),
                  if (goal.reached)
                    const Icon(Icons.check_circle_rounded, color: onTile, size: 22)
                  else
                    Text('$pct%', style: heading(15, weight: FontWeight.w800, color: skin.dark ? Colors.white : onTile)),
                ]),
              ),
            ),
          ),
        ),
        Container(height: 2, color: p.ink),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(peso(goal.savedCents, compact: true), maxLines: 1, style: heading(26, weight: FontWeight.w800, color: p.text, height: 1.1)))),
              const SizedBox(width: 8),
              Flexible(child: Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('of ${peso(goal.targetCents, compact: true)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subText, fontSize: 13.5, fontWeight: FontWeight.w600)))),
            ]),
            const SizedBox(height: 10),
            LimitBar(spent: goal.savedCents, limit: goal.targetCents, height: 12, calm: true),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _GoalButton(label: 'Add money', icon: Icons.add_rounded, filled: true, onTap: onAdd)),
              if (goal.savedCents > 0) ...[
                const SizedBox(width: 10),
                Expanded(child: _GoalButton(label: 'Take out', icon: Icons.remove_rounded, filled: false, onTap: onTake)),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _GoalButton extends StatelessWidget {
  const _GoalButton({required this.label, required this.icon, required this.filled, required this.onTap});
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Pressable(
      label: label,
      lift: 2,
      onTap: onTap,
      builder: (pressed) => Container(
        constraints: const BoxConstraints(minHeight: 44),
        decoration: brutal(p, color: filled ? p.primary : p.field, radius: 12, shadow: pressed ? 0 : 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 19, color: filled ? p.onPrimary : p.text),
          const SizedBox(width: 5),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(14, weight: FontWeight.w800, color: filled ? p.onPrimary : p.text))),
        ]),
      ),
    );
  }
}
