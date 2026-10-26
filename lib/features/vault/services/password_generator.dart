import 'dart:math';

/// A random password with at least one lower-case letter, capital, digit and symbol.
/// Look-alike characters (O/0, l/1/I) are left out so it can be read off a screen.
String generatePassword({int length = 16, Random? random}) {
  final r = random ?? Random.secure();
  const lower = 'abcdefghijkmnopqrstuvwxyz';
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const digits = '23456789';
  const symbols = '!@#\$%^&*-_=+?';
  const all = lower + upper + digits + symbols;
  final chars = <String>[
    lower[r.nextInt(lower.length)],
    upper[r.nextInt(upper.length)],
    digits[r.nextInt(digits.length)],
    symbols[r.nextInt(symbols.length)],
    for (var i = 4; i < length; i++) all[r.nextInt(all.length)],
  ]..shuffle(r);
  return chars.join();
}
