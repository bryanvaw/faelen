import 'package:flutter/material.dart';

/// The Vault's sections. Shots (screenshots) will be added as a fourth.
enum VaultSection {
  logins('Logins', Icons.key_rounded, Color(0xFFB99BFF), 'Password'),
  numbers('Numbers', Icons.call_rounded, Color(0xFF7BD389), 'Number'),
  ids('IDs', Icons.badge_rounded, Color(0xFFFFD166), 'ID number');

  const VaultSection(this.label, this.icon, this.color, this.defaultMain);
  final String label;
  final IconData icon;
  final Color color;

  /// Label of the field the big Copy button copies unless the entry says otherwise.
  final String defaultMain;
}

class VaultField {
  const VaultField(this.label, this.value, {this.secret = false});
  final String label;
  final String value;

  /// Masked until the eye is tapped. Copying never needs the reveal.
  final bool secret;

  Map<String, Object?> toJson() => {'l': label, 'v': value, if (secret) 'x': true};

  static VaultField? fromJson(Object? j) {
    if (j is! Map) return null;
    final l = j['l'], v = j['v'];
    if (l is! String || v is! String) return null;
    return VaultField(l, v, secret: j['x'] == true);
  }
}

class VaultItem {
  const VaultItem({
    required this.id,
    required this.section,
    required this.title,
    required this.fields,
    required this.updatedAt,
    this.main,
    this.favorite = false,
    this.expiry,
  });

  final String id;
  final VaultSection section;
  final String title;
  final List<VaultField> fields;
  final DateTime updatedAt;

  /// Label of the field the main Copy button copies; null means the section default.
  final String? main;
  final bool favorite;

  /// IDs only: when the document runs out.
  final DateTime? expiry;

  VaultField? field(String label) {
    for (final f in fields) {
      if (f.label.toLowerCase() == label.toLowerCase()) return f;
    }
    return null;
  }

  /// What the big Copy button and the Favorites chip copy.
  VaultField? get mainField => field(main ?? section.defaultMain) ?? (fields.isEmpty ? null : fields.first);

  /// The grey line under the title. Never a secret: logins show the username, IDs a masked number.
  String get subtitle {
    switch (section) {
      case VaultSection.logins:
        return field('Username')?.value ?? '';
      case VaultSection.numbers:
        return field('Number')?.value ?? '';
      case VaultSection.ids:
        return maskTail(field('ID number')?.value ?? '');
    }
  }

  /// Days until [expiry]; negative once expired; null without an expiry.
  int? daysLeft(DateTime now) {
    final e = expiry;
    if (e == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(e.year, e.month, e.day).difference(today).inDays;
  }

  VaultItem copyWith({
    String? title,
    List<VaultField>? fields,
    String? main,
    bool clearMain = false,
    bool? favorite,
    DateTime? expiry,
    bool clearExpiry = false,
    DateTime? updatedAt,
  }) =>
      VaultItem(
        id: id,
        section: section,
        title: title ?? this.title,
        fields: fields ?? this.fields,
        updatedAt: updatedAt ?? this.updatedAt,
        main: clearMain ? null : (main ?? this.main),
        favorite: favorite ?? this.favorite,
        expiry: clearExpiry ? null : (expiry ?? this.expiry),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        's': section.name,
        't': title,
        'f': [for (final f in fields) f.toJson()],
        'u': updatedAt.millisecondsSinceEpoch,
        if (main != null) 'm': main,
        if (favorite) 'fav': true,
        if (expiry != null) 'e': expiry!.millisecondsSinceEpoch,
      };

  /// Null when the entry is unreadable, so one bad entry cannot hide the rest.
  static VaultItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], s = j['s'], t = j['t'];
    if (id is! String || s is! String || t is! String) return null;
    final section = VaultSection.values.where((v) => v.name == s).firstOrNull;
    if (section == null) return null;
    final raw = j['f'];
    final fields = <VaultField>[
      if (raw is List)
        for (final f in raw) ?VaultField.fromJson(f),
    ];
    final u = j['u'], e = j['e'];
    return VaultItem(
      id: id,
      section: section,
      title: t,
      fields: fields,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(u is int ? u : 0),
      main: j['m'] is String ? j['m'] as String : null,
      favorite: j['fav'] == true,
      expiry: e is int ? DateTime.fromMillisecondsSinceEpoch(e) : null,
    );
  }
}

/// `•••••4567`: hides everything except the last [keep] characters.
String maskTail(String v, {int keep = 3}) {
  if (v.isEmpty) return '';
  if (v.length <= keep) return '•' * v.length;
  return '${'•' * (v.length - keep).clamp(3, 8)}${v.substring(v.length - keep)}';
}

/// A fixed-width mask that does not leak the length.
String maskAll(String v) => v.isEmpty ? '' : '••••••••';
