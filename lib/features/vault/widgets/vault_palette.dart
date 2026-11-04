import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/settings_store.dart';
import '../../../core/theme.dart';
import '../../budget/models/budget_models.dart' show CardSkin, cardSkins;
import '../../budget/widgets/budget_widgets.dart' show Tone, readableOn;
import '../models/vault_item.dart';

/// The Vault's colours: the two calico colours first (the cat's coral patch and its gold key), then the
/// Budget's 18 card colours. A saved choice is a position in this list.
const vaultSwatches = <CardSkin>[
  CardSkin('Calico', Color(0xFFF26B50)),
  CardSkin('Key gold', Color(0xFFF5B52E)),
  ...cardSkins,
];

/// The colour the Vault wears: the one picked in the palette sheet (the calico cat's colours, then the Budget's card colours),
/// or, when none is picked, each section's own colour.
Color vaultAccent(BuildContext context, VaultSection section) {
  final i = Provider.of<SettingsStore?>(context)?.vaultColor ?? 0;
  return i >= 0 && i < vaultSwatches.length
      ? vaultSwatches[i].face
      : section.color;
}

/// The full colour family (fill, text on it, wash, outline, shadow) for [section], light and dark tuned.
Tone vaultTone(BuildContext context, VaultSection section) =>
    Tone.fromColor(vaultAccent(context, section), Theme.of(context).brightness);

Future<void> showVaultPalette(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _PaletteSheet(),
    );

class _PaletteSheet extends StatelessWidget {
  const _PaletteSheet();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = context.watch<SettingsStore?>();
    final chosen = settings?.vaultColor ?? 0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // The preview follows the pick, so the sheet itself shows what the Vault will look like.
    final tone = chosen >= 0 && chosen < vaultSwatches.length
        ? Tone.fromColor(
            vaultSwatches[chosen].face,
            Theme.of(context).brightness,
          )
        : Tone.fromColor(
            VaultSection.logins.color,
            Theme.of(context).brightness,
          );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Vault colour', style: heading(20, color: p.text)),
            const SizedBox(height: 2),
            Text(
              'Pick one colour for the whole Vault, or let each section keep its own.',
              style: TextStyle(
                color: p.subText,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            // One-line preview of the family: button, wash and badge.
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tone.main,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Copy',
                      style: heading(
                        14,
                        weight: FontWeight.w800,
                        color: tone.on,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tone.soft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Edit',
                      style: heading(
                        14,
                        weight: FontWeight.w800,
                        color: p.text,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      p.ink.withValues(alpha: 0.09),
                      p.card,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Icons.key_rounded, color: p.text),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _BySection(
              on: chosen < 0,
              onTap: () => settings?.setVaultColor(-1),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, c) {
                const gap = 10.0;
                const perRow = 5;
                final size = ((c.maxWidth - gap * (perRow - 1)) / perRow)
                    .floorToDouble();
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (var i = 0; i < vaultSwatches.length; i++)
                      Semantics(
                        button: true,
                        selected: chosen == i,
                        label: vaultSwatches[i].name,
                        child: ExcludeSemantics(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => settings?.setVaultColor(i),
                            child: Container(
                              width: size,
                              height: size,
                              decoration: BoxDecoration(
                                color: vaultSwatches[i].face,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: chosen == i
                                      ? (dark ? Colors.white : p.ink)
                                      : (dark
                                            ? const Color(0x55FFFFFF)
                                            : const Color(0x33000000)),
                                  width: chosen == i ? 3 : 1.2,
                                ),
                              ),
                              child: chosen == i
                                  ? Icon(
                                      Icons.check_rounded,
                                      color: readableOn(vaultSwatches[i].face),
                                      size: size * 0.5,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// "Each section its own colour": three dots in the section colours.
class _BySection extends StatelessWidget {
  const _BySection({required this.on, required this.onTap});
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      selected: on,
      label: 'Each section its own colour',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: on ? p.card : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: on ? p.ink : p.outline,
                width: on ? 2.5 : 1.5,
              ),
            ),
            child: Row(
              children: [
                for (final s in VaultSection.values) ...[
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: p.ink.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Each section its own colour',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: p.text,
                    ),
                  ),
                ),
                if (on) Icon(Icons.check_rounded, color: p.text),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
