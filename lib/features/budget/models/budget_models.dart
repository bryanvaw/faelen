import 'package:flutter/material.dart';

/// All money is whole centavos (₱1.00 = 100); a double never touches an amount.

enum CardKind {
  debit('Debit'),
  credit('Credit'),
  ewallet('E-wallet'),
  cash('Cash');

  const CardKind(this.label);
  final String label;
}

enum CardNetwork {
  visa('Visa'),
  mastercard('Mastercard'),
  none('None');

  const CardNetwork(this.label);
  final String label;
}

/// Colour of a card face. Faces are bright, flat and always carry dark ink, except [ink].
class CardSkin {
  const CardSkin(this.name, this.face, {this.dark = false});
  final String name;
  final Color face;

  /// True for the black card: its text and chip turn light.
  final bool dark;
}

/// The first six keep their positions, so cards saved earlier keep their colour.
/// Light faces carry dark ink; deep faces carry white text. Rows of nine: light first, then deep.
const cardSkins = [
  CardSkin('Coral', Color(0xFFFF8A65)),
  CardSkin('Lilac', Color(0xFFB99BFF)),
  CardSkin('Sun', Color(0xFFFFD166)),
  CardSkin('Mint', Color(0xFF7BD389)),
  CardSkin('Sky', Color(0xFF7CC8FF)),
  CardSkin('Ink', Color(0xFF161616), dark: true),
  CardSkin('Rose', Color(0xFFFF8FB1)),
  CardSkin('Tangerine', Color(0xFFFF9F43)),
  CardSkin('Lime', Color(0xFFC6E05A)),
  CardSkin('Teal', Color(0xFF3CCFBF)),
  CardSkin('Royal blue', Color(0xFF1F6BFF), dark: true),
  CardSkin('Navy', Color(0xFF16305F), dark: true),
  CardSkin('Violet', Color(0xFF6C3FD9), dark: true),
  CardSkin('Forest', Color(0xFF11805A), dark: true),
  CardSkin('Crimson', Color(0xFFD12A3F), dark: true),
  CardSkin('Maroon', Color(0xFF7A1E2E), dark: true),
  CardSkin('Burnt orange', Color(0xFFD9560B), dark: true),
  CardSkin('Graphite', Color(0xFF3A3D46), dark: true),
];

/// Skin positions with a light face (for places that must not default to a deep colour).
final lightSkinIndexes = [for (var i = 0; i < cardSkins.length; i++) if (!cardSkins[i].dark) i];

class Account {
  const Account({
    required this.id,
    required this.name,
    this.issuer = '',
    this.kind = CardKind.debit,
    this.network = CardNetwork.none,
    this.last4 = '',
    this.skin = 0,
    this.openingCents = 0,
  });

  final String id;
  final String name;

  /// Bank or wallet name shown on the card's top-left (can be empty).
  final String issuer;
  final CardKind kind;
  final CardNetwork network;

  /// Last four digits only; the app never stores a full card number.
  final String last4;
  final int skin;

  /// Balance before the first logged transaction.
  final int openingCents;

  CardSkin get skinData => cardSkins[skin.clamp(0, cardSkins.length - 1)];

  Account copyWith({
    String? name,
    String? issuer,
    CardKind? kind,
    CardNetwork? network,
    String? last4,
    int? skin,
    int? openingCents,
  }) =>
      Account(
        id: id,
        name: name ?? this.name,
        issuer: issuer ?? this.issuer,
        kind: kind ?? this.kind,
        network: network ?? this.network,
        last4: last4 ?? this.last4,
        skin: skin ?? this.skin,
        openingCents: openingCents ?? this.openingCents,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'issuer': issuer,
        'kind': kind.name,
        'network': network.name,
        'last4': last4,
        'skin': skin,
        'opening': openingCents,
      };

  static Account? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.isEmpty || name is! String) return null;
    T pick<T extends Enum>(List<T> all, Object? v, T fallback) {
      for (final e in all) {
        if (e.name == v) return e;
      }
      return fallback;
    }

    final last4 = raw['last4'];
    final skin = raw['skin'];
    final opening = raw['opening'];
    return Account(
      id: id,
      name: name,
      issuer: raw['issuer'] is String ? raw['issuer'] as String : '',
      kind: pick(CardKind.values, raw['kind'], CardKind.debit),
      network: pick(CardNetwork.values, raw['network'], CardNetwork.none),
      last4: last4 is String ? last4.replaceAll(RegExp(r'\D'), '').characters.take(4).toString() : '',
      skin: skin is int && skin >= 0 && skin < cardSkins.length ? skin : 0,
      openingCents: opening is int ? opening : 0,
    );
  }
}

class Category {
  const Category(this.id, this.label, this.icon, this.color, {this.income = false});
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final bool income;
}

const expenseCategories = [
  Category('food', 'Food', Icons.restaurant_rounded, Color(0xFFFF8A65)),
  Category('transport', 'Transport', Icons.directions_bus_rounded, Color(0xFF7CC8FF)),
  Category('bills', 'Bills', Icons.receipt_long_rounded, Color(0xFFFFD166)),
  Category('shopping', 'Shopping', Icons.shopping_bag_rounded, Color(0xFFB99BFF)),
  Category('health', 'Health', Icons.favorite_rounded, Color(0xFFFF8FB1)),
  Category('fun', 'Fun', Icons.sports_esports_rounded, Color(0xFF7BD389)),
  Category('other', 'Other', Icons.more_horiz_rounded, Color(0xFFD9D9D9)),
];

const incomeCategories = [
  Category('salary', 'Salary', Icons.payments_rounded, Color(0xFF7BD389), income: true),
  Category('allowance', 'Allowance', Icons.account_balance_wallet_rounded, Color(0xFFFFD166), income: true),
  Category('gift', 'Gift', Icons.card_giftcard_rounded, Color(0xFFFF8FB1), income: true),
  Category('income_other', 'Other', Icons.more_horiz_rounded, Color(0xFFD9D9D9), income: true),
];

/// Used by both halves of a transfer between two cards. Not offered in the forms, and left out of
/// income, spending and budgets because the money only moved.
const transferCategory = Category('transfer', 'Transfer', Icons.swap_horiz_rounded, Color(0xFF7CC8FF));

Category categoryById(String id) {
  for (final c in [...expenseCategories, ...incomeCategories, transferCategory]) {
    if (c.id == id) return c;
  }
  return expenseCategories.last;
}

class Txn {
  const Txn({
    required this.id,
    required this.accountId,
    required this.cents,
    required this.income,
    required this.category,
    required this.day,
    this.note = '',
    required this.createdAt,
    this.pair,
  });

  final String id;
  final String accountId;

  /// Set on both halves of a transfer (the same value), so deleting one removes the other.
  final String? pair;

  /// Always positive; [income] says which way the money moved.
  final int cents;
  final bool income;
  final String category;

  /// Calendar day only (midnight, local).
  final DateTime day;
  final String note;
  final int createdAt;

  int get signed => income ? cents : -cents;

  Txn copyWith({String? accountId, int? cents, bool? income, String? category, DateTime? day, String? note}) => Txn(
        id: id,
        accountId: accountId ?? this.accountId,
        cents: cents ?? this.cents,
        income: income ?? this.income,
        category: category ?? this.category,
        day: day ?? this.day,
        note: note ?? this.note,
        createdAt: createdAt,
        pair: pair,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        if (pair != null) 'pair': pair,
        'account': accountId,
        'cents': cents,
        'income': income,
        'category': category,
        'day': dayKey(day),
        'note': note,
        'created': createdAt,
      };

  static Txn? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final account = raw['account'];
    final cents = raw['cents'];
    final day = raw['day'];
    if (id is! String || account is! String || cents is! int || cents <= 0 || day is! int) return null;
    final d = dayFromKey(day);
    if (d == null) return null;
    return Txn(
      id: id,
      accountId: account,
      cents: cents,
      income: raw['income'] == true,
      category: raw['category'] is String ? raw['category'] as String : 'other',
      day: d,
      note: raw['note'] is String ? raw['note'] as String : '',
      createdAt: raw['created'] is int ? raw['created'] as int : 0,
      pair: raw['pair'] is String && (raw['pair'] as String).isNotEmpty ? raw['pair'] as String : null,
    );
  }
}

/// A bill that repeats every month. On its due day the app adds the expense by itself.
class Bill {
  const Bill({required this.id, required this.name, required this.cents, required this.category, required this.accountId, required this.day, this.lastPosted = 0});
  final String id;
  final String name;
  final int cents;
  final String category;
  final String accountId;

  /// Day of the month, 1 to 31. In a shorter month it falls on the last day.
  final int day;

  /// The month (yyyymm) it was last added to the history; 0 = never.
  final int lastPosted;

  Bill copyWith({String? name, int? cents, String? category, String? accountId, int? day, int? lastPosted}) => Bill(
        id: id,
        name: name ?? this.name,
        cents: cents ?? this.cents,
        category: category ?? this.category,
        accountId: accountId ?? this.accountId,
        day: day ?? this.day,
        lastPosted: lastPosted ?? this.lastPosted,
      );

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'cents': cents, 'category': category, 'account': accountId, 'day': day, 'last': lastPosted};

  static Bill? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], name = raw['name'], cents = raw['cents'], account = raw['account'], day = raw['day'];
    if (id is! String || id.isEmpty || name is! String || cents is! int || cents <= 0 || account is! String || day is! int || day < 1 || day > 31) return null;
    return Bill(
      id: id,
      name: name,
      cents: cents,
      category: raw['category'] is String ? raw['category'] as String : 'bills',
      accountId: account,
      day: day,
      lastPosted: raw['last'] is int ? raw['last'] as int : 0,
    );
  }
}

/// Money set aside for something. It is a jar of its own, not taken from any card's balance.
class Goal {
  const Goal({required this.id, required this.name, required this.targetCents, this.savedCents = 0, this.skin = 3});
  final String id;
  final String name;
  final int targetCents;
  final int savedCents;
  final int skin;

  bool get reached => targetCents > 0 && savedCents >= targetCents;

  Goal copyWith({String? name, int? targetCents, int? savedCents, int? skin}) =>
      Goal(id: id, name: name ?? this.name, targetCents: targetCents ?? this.targetCents, savedCents: savedCents ?? this.savedCents, skin: skin ?? this.skin);

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'target': targetCents, 'saved': savedCents, 'skin': skin};

  static Goal? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], name = raw['name'], target = raw['target'];
    if (id is! String || id.isEmpty || name is! String || target is! int || target <= 0) return null;
    final saved = raw['saved'], skin = raw['skin'];
    return Goal(
      id: id,
      name: name,
      targetCents: target,
      savedCents: saved is int && saved > 0 ? saved : 0,
      skin: skin is int && skin >= 0 && skin < cardSkins.length ? skin : 3,
    );
  }
}

/// yyyymmdd as an int: sortable, indexable, and free of time zones.
int dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

DateTime? dayFromKey(int k) {
  final y = k ~/ 10000, m = (k ~/ 100) % 100, d = k % 100;
  if (y < 1970 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime(y, m, d);
}

int monthKey(DateTime d) => d.year * 100 + d.month;

/// The due date of a monthly bill in [year]/[month]: [day], or the month's last day if it is shorter.
DateTime dueDate(int year, int month, int day) {
  final last = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > last ? last : day);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// ₱12,345.67 ; negative as -₱12,345.67. Cents are dropped from whole-peso figures when [compact].
String peso(int cents, {bool sign = false, bool compact = false}) {
  final neg = cents < 0;
  final abs = cents.abs();
  final whole = (abs ~/ 100).toString();
  final grouped = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final frac = abs % 100;
  final body = compact && frac == 0 ? grouped : '$grouped.${frac.toString().padLeft(2, '0')}';
  final lead = neg ? '-' : (sign && cents > 0 ? '+' : '');
  return '$lead₱$body';
}

/// "1,250.5" -> 125050 ; null when it is not a clean amount. Up to two decimals, no exponent, no sign.
int? parseCents(String text) {
  final t = text.replaceAll(',', '').replaceAll('₱', '').trim();
  final m = RegExp(r'^(\d{1,10})(?:\.(\d{0,2}))?$').firstMatch(t);
  if (m == null) return null;
  final whole = int.parse(m.group(1)!);
  final frac = (m.group(2) ?? '').padRight(2, '0');
  return whole * 100 + int.parse(frac);
}

/// The text a field shows for [cents] when editing ("1250.5" -> "1250.50"; whole pesos without decimals).
String centsToField(int cents) {
  final abs = cents.abs();
  return abs % 100 == 0 ? '${abs ~/ 100}' : '${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}
