import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../models/vault_item.dart';
import '../services/password_generator.dart';
import '../state/vault_store.dart';

/// (name saved, shorter name shown on the tile, icon). Six fit a 3 x 2 grid, each in its own place.
const _idTypes = [
  ('Passport', 'Passport', Icons.flight_takeoff_rounded),
  ('Driver’s licence', 'Licence', Icons.directions_car_rounded),
  ('National ID', 'National ID', Icons.badge_rounded),
  ('TIN', 'TIN', Icons.receipt_long_rounded),
  ('SSS', 'SSS', Icons.shield_rounded),
  ('PhilHealth', 'PhilHealth', Icons.health_and_safety_rounded),
];
const _weak = Color(0xFFD93636);

/// The add/edit sheet for one entry. Returns the entry to save, or null when dismissed.
/// [newId] is only used when adding.
Future<VaultItem?> showVaultForm(
  BuildContext context, {
  required VaultSection section,
  VaultItem? item,
  required String Function() newId,
  VaultStore? store,
}) {
  return showModalBottomSheet<VaultItem>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _VaultForm(section: section, item: item, newId: newId, store: store),
  );
}

class _VaultForm extends StatefulWidget {
  const _VaultForm({required this.section, required this.item, required this.newId, this.store});
  final VaultSection section;
  final VaultItem? item;
  final String Function() newId;

  /// When given, the sheet closes itself if the Vault locks while it is open, so a half-typed
  /// password is never left on screen behind the lock.
  final VaultStore? store;

  @override
  State<_VaultForm> createState() => _VaultFormState();
}

class _VaultFormState extends State<_VaultForm> {
  final _key = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.item?.title);
  late final _user = TextEditingController(text: widget.item?.field('Username')?.value);
  late final _pass = TextEditingController(text: widget.item?.field('Password')?.value);
  late final _link = TextEditingController(text: widget.item?.field('Link')?.value);
  late final _number = TextEditingController(text: widget.item?.field('Number')?.value);
  late final _idNumber = TextEditingController(text: widget.item?.field('ID number')?.value);
  late final _notes = TextEditingController(text: widget.item?.field('Notes')?.value);
  late DateTime? _expiry = widget.item?.expiry;
  bool _showPass = false;

  /// Link and notes are tucked away until wanted (or until the entry already has them), so the
  /// form stays one short screen.
  late bool _more = (widget.item?.field('Link')?.value.isNotEmpty ?? false) || (widget.item?.field('Notes')?.value.isNotEmpty ?? false);

  bool get _editing => widget.item != null;

  @override
  void initState() {
    super.initState();
    _pass.addListener(() => setState(() {})); // the strength bar follows typing
    _title.addListener(() => setState(() {})); // the ID type chips follow typing
    widget.store?.addListener(_onStore);
  }

  void _onStore() {
    if (widget.store!.status == VaultStatus.unlocked || !mounted) return;
    widget.store!.removeListener(_onStore);
    // Closes this sheet and anything opened from it (such as the date picker).
    Navigator.of(context).popUntil((r) => r is! PopupRoute);
  }

  @override
  void dispose() {
    widget.store?.removeListener(_onStore);
    for (final c in [_title, _user, _pass, _link, _number, _idNumber, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  VaultField? _f(String label, TextEditingController c, {bool secret = false}) {
    final v = c.text.trim();
    return v.isEmpty ? null : VaultField(label, v, secret: secret);
  }

  void _save() {
    if (!_key.currentState!.validate()) return;
    final fields = <VaultField>[
      ...switch (widget.section) {
        VaultSection.logins => [?_f('Username', _user), ?_f('Password', _pass, secret: true), ?_f('Link', _link)],
        VaultSection.numbers => [?_f('Number', _number)],
        VaultSection.ids => [?_f('ID number', _idNumber, secret: true)],
      },
      ?_f('Notes', _notes),
    ];
    final old = widget.item;
    Navigator.pop(
      context,
      VaultItem(
        id: old?.id ?? widget.newId(),
        section: widget.section,
        title: _title.text.trim(),
        fields: fields,
        updatedAt: DateTime.now(),
        main: old?.main,
        favorite: old?.favorite ?? false,
        expiry: widget.section == VaultSection.ids ? _expiry : null,
      ),
    );
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now.add(const Duration(days: 365)),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 30),
    );
    if (d != null) setState(() => _expiry = d);
  }

  /// True when the chosen expiry is exactly [years] years from today (so its shortcut shows as chosen).
  bool _isInYears(int years) {
    final e = _expiry;
    if (e == null) return false;
    final n = DateTime.now();
    return e.year == n.year + years && e.month == n.month && e.day == n.day;
  }

  String _date(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  /// A field: a bold label above, the box below tinted with the section's colour so it reads as a
  /// control on both the light and the dark sheet. Focus thickens the outline and deepens the tint.
  InputDecoration _dec(Palette p, {required String hint, required IconData icon, Widget? suffix}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.section.color;
    final fill = Color.alphaBlend(accent.withValues(alpha: dark ? 0.16 : 0.16), p.bg);
    final focusFill = Color.alphaBlend(accent.withValues(alpha: dark ? 0.30 : 0.34), p.bg);
    OutlineInputBorder border(double w) => OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.ink, width: w));
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: p.subText, fontWeight: FontWeight.w500),
      prefixIcon: Icon(icon, size: 21),
      prefixIconColor: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.focused) ? p.text : p.subText),
      suffixIcon: suffix,
      filled: true,
      fillColor: fill,
      hoverColor: focusFill,
      focusColor: focusFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: border(2),
      enabledBorder: border(2),
      focusedBorder: border(3),
      errorBorder: border(2).copyWith(borderSide: const BorderSide(color: _weak, width: 2)),
      focusedErrorBorder: border(3).copyWith(borderSide: const BorderSide(color: _weak, width: 3)),
    );
  }

  Widget _labeled(Palette p, String label, Widget field, {Widget? trailing, Widget? below}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Row(children: [
              Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.text))),
              ?trailing,
            ]),
          ),
          field,
          if (below != null) Padding(padding: const EdgeInsets.only(top: 9, left: 2, right: 2), child: below),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = widget.section;
    final what = switch (s) { VaultSection.logins => 'login', VaultSection.numbers => 'number', VaultSection.ids => 'ID' };
    final theme = Theme.of(context);
    // The cursor and text selection wear the section colour too.
    return Theme(
      data: theme.copyWith(
        textSelectionTheme: TextSelectionThemeData(cursorColor: p.ink, selectionColor: s.color.withValues(alpha: 0.45), selectionHandleColor: p.ink),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Form(
                key: _key,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.ink, width: 2)),
                      child: Icon(s.icon, size: 21, color: onTile),
                    ),
                    const SizedBox(width: 12),
                    Text('${_editing ? 'Edit' : 'Add'} $what', style: heading(22, color: p.text)),
                  ]),
                  const SizedBox(height: 18),
                  if (s == VaultSection.ids) ...[
                    _labeled(
                      p,
                      'Type',
                      Column(children: [
                        for (var r = 0; r < 2; r++)
                          Padding(
                            padding: EdgeInsets.only(top: r == 0 ? 0 : 8),
                            child: Row(children: [
                              for (var c = 0; c < 3; c++) ...[
                                if (c > 0) const SizedBox(width: 8),
                                Expanded(
                                  child: _Choice(
                                    label: _idTypes[r * 3 + c].$1,
                                    shortLabel: _idTypes[r * 3 + c].$2,
                                    icon: _idTypes[r * 3 + c].$3,
                                    stacked: true,
                                    selected: _title.text.trim() == _idTypes[r * 3 + c].$1,
                                    accent: s.color,
                                    onTap: () => setState(() => _title.text = _idTypes[r * 3 + c].$1),
                                  ),
                                ),
                              ],
                            ]),
                          ),
                      ]),
                    ),
                  ],
                  _labeled(
                    p,
                    switch (s) { VaultSection.logins => 'Site or app', VaultSection.numbers => 'Name', VaultSection.ids => 'Document name' },
                    TextFormField(
                      controller: _title,
                      autofocus: !_editing && s != VaultSection.ids,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: _dec(p,
                          hint: switch (s) { VaultSection.logins => 'Netflix', VaultSection.numbers => 'Mama, My Globe, Bank hotline', VaultSection.ids => 'Pick one above, or type your own' },
                          icon: switch (s) { VaultSection.logins => Icons.language_rounded, VaultSection.numbers => Icons.person_rounded, VaultSection.ids => Icons.badge_rounded }),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Give it a name' : null,
                    ),
                  ),
                  if (s == VaultSection.logins) ...[
                    _labeled(
                      p,
                      'Username or email',
                      TextFormField(
                        controller: _user,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: _dec(p, hint: 'you@mail.com', icon: Icons.person_outline_rounded),
                      ),
                    ),
                    _labeled(
                      p,
                      'Password',
                      TextFormField(
                        controller: _pass,
                        obscureText: !_showPass,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        decoration: _dec(
                          p,
                          hint: 'Type one, or generate',
                          icon: Icons.key_rounded,
                          suffix: IconButton(
                            tooltip: _showPass ? 'Hide password' : 'Show password',
                            icon: Icon(_showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                            onPressed: () => setState(() => _showPass = !_showPass),
                          ),
                        ),
                      ),
                      trailing: _TextAction(
                        icon: Icons.auto_awesome_rounded,
                        label: 'Generate',
                        onTap: () => setState(() {
                          _pass.text = generatePassword();
                          _showPass = true;
                        }),
                      ),
                      below: _pass.text.isEmpty ? null : _Strength(password: _pass.text),
                    ),
                  ],
                  if (s == VaultSection.numbers)
                    _labeled(
                      p,
                      'Mobile number',
                      TextFormField(
                        controller: _number,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-() ]'))],
                        decoration: _dec(p, hint: '0917 123 4567', icon: Icons.call_rounded),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the number' : null,
                      ),
                    ),
                  if (s == VaultSection.ids) ...[
                    _labeled(
                      p,
                      'ID number',
                      TextFormField(
                        controller: _idNumber,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: _dec(p, hint: 'As printed on the ID', icon: Icons.tag_rounded),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the ID number' : null,
                      ),
                    ),
                    _labeled(
                      p,
                      'Expires',
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _DateButton(
                          label: _expiry == null ? 'Pick a date (optional)' : _date(_expiry!),
                          set: _expiry != null,
                          accent: s.color,
                          onTap: _pickExpiry,
                          onClear: _expiry == null ? null : () => setState(() => _expiry = null),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          for (final y in const [3, 5, 10]) ...[
                            if (y != 3) const SizedBox(width: 8),
                            Expanded(
                              child: _Choice(
                                label: 'In $y years',
                                selected: _isInYears(y),
                                accent: s.color,
                                onTap: () {
                                  final n = DateTime.now();
                                  setState(() => _expiry = DateTime(n.year + y, n.month, n.day));
                                },
                              ),
                            ),
                          ],
                        ]),
                      ]),
                    ),
                  ],
                  if (!_more)
                    _MoreRow(label: s == VaultSection.logins ? 'Add a link or notes' : 'Add notes', onTap: () => setState(() => _more = true))
                  else ...[
                    if (s == VaultSection.logins)
                      _labeled(
                        p,
                        'Link',
                        TextFormField(
                          controller: _link,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: _dec(p, hint: 'netflix.com', icon: Icons.link_rounded),
                        ),
                      ),
                    _labeled(
                      p,
                      'Notes',
                      TextFormField(
                        controller: _notes,
                        minLines: 2,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: _dec(p, hint: 'Anything you want to remember', icon: Icons.notes_rounded),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ),
          _SaveBar(accent: s.color, onCancel: () => Navigator.pop(context), onSave: _save),
        ]),
      ),
    );
  }
}

/// An option in a fixed slot (the parent puts it in an [Expanded] cell, like the Media form's type and
/// status tiles). Unselected: the section colour as a soft tint. Selected: filled, bold outline, hard
/// shadow. [stacked] puts the icon above the label.
class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.accent, required this.onTap, this.shortLabel, this.icon, this.stacked = false});
  final String label;
  final String? shortLabel; // shown on the tile when the full name is long; [label] stays the spoken name
  final IconData? icon;
  final bool stacked;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fg = selected ? onTile : p.text;
    final text = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(shortLabel ?? label, maxLines: 1, style: TextStyle(fontSize: stacked ? 12.5 : 13.5, fontWeight: selected ? FontWeight.w800 : FontWeight.w700, color: fg)),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            constraints: BoxConstraints(minHeight: stacked ? 58 : 44),
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: stacked ? 8 : 6),
            alignment: Alignment.center,
            decoration: selected
                ? brutal(p, color: accent, radius: 14, shadow: 2)
                : BoxDecoration(color: accent.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.transparent, width: 2)),
            child: stacked && icon != null
                ? Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 22, color: fg), const SizedBox(height: 3), text])
                : text,
          ),
        ),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 17, color: p.text),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: p.text, decoration: TextDecoration.underline, decorationThickness: 2)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Four segments and a word, so strength is never shown by colour alone.
class _Strength extends StatelessWidget {
  const _Strength({required this.password});
  final String password;

  static int score(String v) {
    var n = 0;
    if (v.length >= 10) n++;
    if (v.length >= 14) n++;
    if (RegExp(r'[a-z]').hasMatch(v) && RegExp(r'[A-Z]').hasMatch(v)) n++;
    if (RegExp(r'[0-9]').hasMatch(v) && RegExp(r'[^A-Za-z0-9]').hasMatch(v)) n++;
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final n = score(password);
    final (word, color) = switch (n) {
      0 || 1 => ('Weak', _weak),
      2 => ('Fair', const Color(0xFFFF8A65)),
      3 => ('Good', const Color(0xFFFFD166)),
      _ => ('Strong', const Color(0xFF7BD389)),
    };
    return Semantics(
      label: 'Password strength: $word',
      child: ExcludeSemantics(
        child: Row(children: [
          for (var i = 0; i < 4; i++)
            Expanded(
              child: Container(
                height: 8,
                margin: EdgeInsets.only(right: i == 3 ? 0 : 5),
                decoration: BoxDecoration(
                  color: i < (n == 0 ? 1 : n) ? color : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: p.ink, width: 1.5),
                ),
              ),
            ),
          const SizedBox(width: 10),
          SizedBox(width: 52, child: Text(word, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: p.text))),
        ]),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({required this.label, required this.set, required this.accent, required this.onTap, this.onClear});
  final String label;
  final bool set;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(children: [
      Expanded(
        child: Semantics(
          button: true,
          label: set ? 'Expiry date $label. Change' : 'Pick an expiry date',
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: set ? Color.alphaBlend(accent.withValues(alpha: 0.34), p.bg) : Color.alphaBlend(accent.withValues(alpha: 0.16), p.bg),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.ink, width: 2),
                ),
                child: Row(children: [
                  Icon(Icons.event_rounded, size: 21, color: set ? p.text : p.subText),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label, style: TextStyle(fontSize: 15.5, fontWeight: set ? FontWeight.w800 : FontWeight.w500, color: set ? p.text : p.subText))),
                ]),
              ),
            ),
          ),
        ),
      ),
      if (onClear != null) IconButton(tooltip: 'Clear expiry date', onPressed: onClear, icon: const Icon(Icons.close_rounded)),
    ]);
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 48,
            margin: const EdgeInsets.only(bottom: 8),
            alignment: Alignment.centerLeft,
            child: Row(children: [
              Icon(Icons.add_circle_outline_rounded, size: 21, color: p.text),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: p.text)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Pinned bottom bar: a quiet Cancel and a bold Save in the section colour that sinks when pressed.
class _SaveBar extends StatefulWidget {
  const _SaveBar({required this.accent, required this.onCancel, required this.onSave});
  final Color accent;
  final VoidCallback onCancel, onSave;

  @override
  State<_SaveBar> createState() => _SaveBarState();
}

class _SaveBarState extends State<_SaveBar> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(color: p.bg, border: Border(top: BorderSide(color: p.outline, width: 1.5))),
      child: Row(children: [
        Semantics(
          button: true,
          label: 'Cancel',
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onCancel,
              child: Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                alignment: Alignment.center,
                child: Text('Cancel', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: p.text, decoration: TextDecoration.underline, decorationThickness: 2)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            button: true,
            label: 'Save',
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => setState(() => _down = true),
                onTapCancel: () => setState(() => _down = false),
                onTapUp: (_) => setState(() => _down = false),
                onTap: widget.onSave,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 90),
                    transform: Matrix4.translationValues(0, _down ? 4 : 0, 0),
                    height: 54,
                    alignment: Alignment.center,
                    decoration: brutal(p, color: widget.accent, radius: 16, shadow: _down ? 0 : 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.check_rounded, size: 22, color: onTile),
                      const SizedBox(width: 8),
                      Text('Save', style: heading(18, weight: FontWeight.w700, color: onTile)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
