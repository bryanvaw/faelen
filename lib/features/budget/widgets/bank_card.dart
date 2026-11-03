import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../models/budget_models.dart';

/// A bank-style card face in the Faelen outlined style: flat colour, bold ink outline, a hard
/// shadow, two big flat discs for depth (no gradients), chip, network mark, balance and last four.
/// Shaped like a real card (85.6 x 54 mm). The balance can be hidden.
class BankCard extends StatelessWidget {
  const BankCard({
    super.key,
    required this.account,
    required this.balance,
    this.hidden = false,
    this.shadow = 4,
  });

  final Account account;
  final int balance;
  final bool hidden;
  final double shadow;

  static const aspect = 1.586;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final skin = account.skinData;
    final fg = skin.dark ? const Color(0xFFF5F5F5) : onTile;
    final softFg = fg.withValues(alpha: 0.72);
    final disc = (skin.dark ? Colors.white : Colors.black).withValues(
      alpha: skin.dark ? 0.07 : 0.09,
    );
    final balanceText = hidden ? '₱ ••••••' : peso(balance);
    final over = balance < 0;

    return Semantics(
      container: true,
      label:
          '${account.name}, ${account.kind.label}${account.last4.isEmpty ? '' : ', ending ${account.last4}'}. '
          'Balance ${hidden ? 'hidden' : peso(balance)}',
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: aspect,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final u = w / 340; // everything scales from a 340dp wide card
              // A card is a picture of a card: its text scales with the card's width, so the phone's
              // text size is only allowed to nudge it (it would not fit the fixed card shape otherwise).
              return MediaQuery.withClampedTextScaling(
                minScaleFactor: 1,
                maxScaleFactor: 1.1,
                child: Container(
                  decoration: brutal(
                    p,
                    color: skin.face,
                    radius: 22 * u.clamp(0.8, 1.2),
                    shadow: shadow,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Positioned(
                        right: -w * 0.16,
                        bottom: -w * 0.30,
                        child: _Disc(size: w * 0.62, color: disc),
                      ),
                      Positioned(
                        right: w * 0.14,
                        bottom: -w * 0.40,
                        child: _Disc(size: w * 0.56, color: disc),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          20 * u,
                          16 * u,
                          20 * u,
                          16 * u,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    account.issuer.isEmpty
                                        ? account.kind.label
                                        : account.issuer,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: heading(
                                      17 * u,
                                      weight: FontWeight.w800,
                                      color: fg,
                                    ),
                                  ),
                                ),
                                _NetworkMark(
                                  network: account.network,
                                  u: u,
                                  fg: fg,
                                  dark: skin.dark,
                                ),
                              ],
                            ),
                            SizedBox(height: 10 * u),
                            if (account.kind == CardKind.debit ||
                                account.kind == CardKind.credit)
                              _Chip(u: u, ink: skin.dark ? fg : onTile),
                            const Spacer(),
                            Text(
                              'Balance',
                              style: TextStyle(
                                color: softFg,
                                fontSize: 11.5 * u,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                balanceText,
                                maxLines: 1,
                                style: heading(
                                  31 * u,
                                  weight: FontWeight.w800,
                                  color: over && !skin.dark
                                      ? const Color(0xFF8A1212)
                                      : fg,
                                  height: 1.1,
                                ),
                              ),
                            ),
                            SizedBox(height: 8 * u),
                            Row(
                              children: [
                                Text(
                                  account.last4.isEmpty
                                      ? account.kind.label
                                      : '•••• ${account.last4}',
                                  style: heading(
                                    13.5 * u,
                                    weight: FontWeight.w700,
                                    color: fg,
                                  ),
                                ),
                                const Spacer(),
                                Flexible(
                                  child: Text(
                                    account.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: softFg,
                                      fontSize: 12.5 * u,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// The EMV chip, flat: a rounded plate with the contact lines cut in.
class _Chip extends StatelessWidget {
  const _Chip({required this.u, required this.ink});
  final double u;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40 * u,
      height: 30 * u,
      decoration: BoxDecoration(
        color: const Color(0xFFFFE9A8),
        borderRadius: BorderRadius.circular(7 * u),
        border: Border.all(color: ink, width: 1.6),
      ),
      child: CustomPaint(painter: _ChipLines(ink)),
    );
  }
}

class _ChipLines extends CustomPainter {
  _ChipLines(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(0, s.height / 2),
      Offset(s.width, s.height / 2),
      paint,
    );
    canvas.drawLine(
      Offset(s.width * 0.36, 0),
      Offset(s.width * 0.36, s.height),
      paint,
    );
    canvas.drawLine(
      Offset(s.width * 0.64, 0),
      Offset(s.width * 0.64, s.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ChipLines old) => old.color != color;
}

class _NetworkMark extends StatelessWidget {
  const _NetworkMark({
    required this.network,
    required this.u,
    required this.fg,
    required this.dark,
  });
  final CardNetwork network;
  final double u;
  final Color fg;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    switch (network) {
      case CardNetwork.none:
        return const SizedBox.shrink();
      case CardNetwork.visa:
        return Text(
          'VISA',
          style: heading(
            20 * u,
            weight: FontWeight.w900,
            color: fg,
          ).copyWith(fontStyle: FontStyle.italic, letterSpacing: 0.5),
        );
      case CardNetwork.mastercard:
        final r = 13 * u;
        return SizedBox(
          width: r * 3.1,
          height: r * 2,
          child: Stack(
            children: [
              Positioned(left: 0, child: _ring(r, const Color(0xFFEB001B))),
              Positioned(
                right: 0,
                child: _ring(
                  r,
                  const Color(0xFFF79E1B).withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _ring(double r, Color c) => Container(
    width: r * 2,
    height: r * 2,
    decoration: BoxDecoration(
      color: c,
      shape: BoxShape.circle,
      border: Border.all(color: dark ? Colors.white : onTile, width: 1.6),
    ),
  );
}

/// The dashed "Add a card" placeholder at the end of the carousel.
class AddCardSlot extends StatelessWidget {
  const AddCardSlot({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: 'Add a card',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: AspectRatio(
            aspectRatio: BankCard.aspect,
            child: CustomPaint(
              painter: _Dashed(p.ink, p.field),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: brutal(
                        p,
                        color: p.primary,
                        radius: 16,
                        shadow: 3,
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        color: p.onPrimary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Add a card',
                      style: heading(
                        17,
                        weight: FontWeight.w700,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Debit, credit, e-wallet or cash',
                      style: TextStyle(
                        color: p.subText,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dashed extends CustomPainter {
  _Dashed(this.color, this.fill);
  final Color color, fill;

  @override
  void paint(Canvas canvas, Size s) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & s,
      const Radius.circular(22),
    ).deflate(1.5);
    canvas.drawRRect(r, Paint()..color = fill);
    final path = Path()..addRRect(r);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 14) {
        canvas.drawPath(m.extractPath(d, (d + 8).clamp(0, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Dashed old) => old.color != color || old.fill != fill;
}
