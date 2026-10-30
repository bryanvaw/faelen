import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../services/pin_service.dart';
import '../state/vault_store.dart';

const _lilac = Color(0xFFB99BFF);

/// The "erase the Vault" question, shared by the PIN pad and the screens shown when the Vault is
/// stuck (unreadable file, secure storage not answering). True when the user chose to erase.
Future<bool> confirmEraseVault(
  BuildContext context, {
  required String title,
  required String body,
  String keepLabel = 'Cancel',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, style: heading(20)),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(keepLabel)),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text('Erase Vault', style: TextStyle(color: Theme.of(c).colorScheme.error, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  return ok == true;
}

/// The Vault's lock screen. First run it asks for a 6-digit PIN twice; after that it asks for the
/// PIN (or the fingerprint/face, tried automatically on opening).
class VaultGate extends StatefulWidget {
  const VaultGate({super.key});

  @override
  State<VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends State<VaultGate> {
  String _entry = '';
  String? _first; // setup: the PIN typed the first time
  String? _message;
  bool _error = false;
  bool _busy = false;
  bool _useBio = true;
  Duration _wait = Duration.zero;
  Timer? _tick;

  VaultStore get _store => context.read<VaultStore>();
  bool get _setup => _store.status == VaultStatus.needsSetup;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _wait = await _store.pin.lockedFor();
      if (_wait > Duration.zero) _startTick();
      if (!_setup && _store.biometricReady && _wait == Duration.zero) {
        _tryBiometric();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {
        _wait -= const Duration(seconds: 1);
        if (_wait <= Duration.zero) {
          _wait = Duration.zero;
          _message = null;
          t.cancel();
        }
      });
    });
  }

  Future<void> _tryBiometric() async {
    await _store.unlockWithBiometric();
  }

  void _key(String d) {
    if (_busy || _wait > Duration.zero || _entry.length >= PinService.length) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _entry += d;
      _error = false;
      _message = null;
    });
    if (_entry.length == PinService.length) _submit();
  }

  void _back() {
    if (_busy || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _submit() async {
    try {
      await _submitInner();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _entry = '';
        _first = null;
        _busy = false;
        _error = true;
        _message = 'Something went wrong: $e';
      });
    }
  }

  Future<void> _submitInner() async {
    final pin = _entry;
    setState(() => _busy = true);
    await Future<void>.delayed(
      const Duration(milliseconds: 220),
    ); // let the sixth dot be seen
    if (!mounted) return;
    if (_setup) {
      if (_first == null) {
        HapticFeedback.mediumImpact();
        setState(() {
          _first = pin;
          _entry = '';
          _busy = false;
          _message = 'Good. Now type the same PIN again to confirm.';
        });
        return;
      }
      if (_first != pin) {
        HapticFeedback.heavyImpact();
        setState(() {
          _first = null;
          _entry = '';
          _error = true;
          _message = 'The two PINs did not match. Start again.';
          _busy = false;
        });
        return;
      }
      await _store.setUp(pin, useBiometric: _useBio);
      return;
    }
    final r = await _store.unlockWithPin(pin);
    if (!mounted || r.outcome == PinOutcome.ok) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _entry = '';
      _busy = false;
      _error = true;
      if (r.outcome == PinOutcome.locked) {
        _wait = r.wait;
        _startTick();
      } else {
        _message =
            'Wrong PIN. ${r.triesLeft} ${r.triesLeft == 1 ? 'try' : 'tries'} left.';
      }
    });
  }

  Future<void> _forgot() async {
    final ok = await confirmEraseVault(
      context,
      title: 'Forgot your PIN?',
      body: 'The Vault cannot be opened without the PIN, and nobody can recover it. '
          'You can erase the Vault and start again, which deletes every login, number and ID saved in it.',
      keepLabel: 'Keep trying',
    );
    if (ok && mounted) {
      await _store.eraseEverything();
      if (mounted) {
        setState(() {
          _entry = '';
          _first = null;
          _wait = Duration.zero;
          _message = null;
          _error = false;
          _busy = false;
        });
      }
    }
  }

  String get _title {
    if (!_setup) return 'Enter your PIN';
    return _first == null ? 'Choose a 6-digit PIN' : 'Confirm your PIN';
  }

  String? get _step =>
      _setup ? (_first == null ? 'Step 1 of 2' : 'Step 2 of 2') : null;

  String? get _hint {
    if (_wait > Duration.zero) {
      return 'Too many tries. Wait ${_wait.inMinutes > 0 ? '${_wait.inMinutes}m ' : ''}${_wait.inSeconds % 60}s.';
    }
    if (_message != null) return _message;
    if (_setup && _first == null) {
      return 'It cannot be recovered. If you forget it, the Vault has to be erased.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    context.watch<VaultStore>();
    final hint = _hint;
    return ColoredBox(
      color: p.bg,
      child: Scaffold(
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.maybePop(context),
                        icon: Icon(Icons.arrow_back_rounded, color: p.text),
                      ),
                    ),
                  ),
                  const Spacer(flex: 1),
                  Container(
                    width: 84,
                    height: 84,
                    padding: const EdgeInsets.all(8),
                    decoration: brutal(p, color: _lilac, radius: 22, shadow: 3),
                    child: Image.asset(
                      'assets/cats/passwords.png',
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(_title, style: heading(22, color: p.text)),
                  if (_step != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _step!,
                      style: TextStyle(
                        color: p.subText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _Dots(filled: _entry.length, error: _error),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 40,
                    child: _busy
                        ? const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: Text(
                              hint ?? '',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: TextStyle(
                                color: _error || _wait > Duration.zero
                                    ? Theme.of(context).colorScheme.error
                                    : p.subText,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                  ),
                  if (_setup && _first == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: FutureBuilder<bool>(
                        future: _store.biometrics.available(),
                        builder: (_, s) => s.data == true
                            ? SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: const Text(
                                  'Also unlock with fingerprint or face',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                value: _useBio,
                                onChanged: (v) => setState(() => _useBio = v),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  const Spacer(flex: 1),
                  _Pad(
                    onKey: _key,
                    onBack: _back,
                    onBio: !_setup && _store.biometricReady
                        ? () => _tryBiometric()
                        : null,
                  ),
                  const SizedBox(height: 8),
                  if (!_setup)
                    TextButton(
                      onPressed: _forgot,
                      child: Text(
                        'Forgot PIN?',
                        style: TextStyle(color: p.subText),
                      ),
                    ),
                  SizedBox(height: _setup ? 24 : 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.filled, required this.error});
  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      label: '$filled of ${PinService.length} digits entered',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < PinService.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                margin: const EdgeInsets.symmetric(horizontal: 7),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < filled
                      ? (error
                            ? Theme.of(context).colorScheme.error
                            : p.primary)
                      : Colors.transparent,
                  border: Border.all(
                    color: error ? Theme.of(context).colorScheme.error : p.ink,
                    width: 2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pad extends StatelessWidget {
  const _Pad({required this.onKey, required this.onBack, this.onBio});
  final void Function(String) onKey;
  final VoidCallback onBack;
  final VoidCallback? onBio;

  @override
  Widget build(BuildContext context) {
    Widget row(List<Widget> kids) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: kids),
    );
    Widget digit(String d) =>
        _PadKey(label: d, semantics: d, onTap: () => onKey(d));
    return Column(
      children: [
        row([digit('1'), digit('2'), digit('3')]),
        row([digit('4'), digit('5'), digit('6')]),
        row([digit('7'), digit('8'), digit('9')]),
        row([
          onBio == null
              ? const SizedBox(width: 92)
              : _PadKey(
                  icon: Icons.fingerprint_rounded,
                  semantics: 'Unlock with fingerprint or face',
                  onTap: onBio!,
                ),
          digit('0'),
          _PadKey(
            icon: Icons.backspace_outlined,
            semantics: 'Delete last digit',
            onTap: onBack,
            quiet: true,
          ),
        ]),
      ],
    );
  }
}

class _PadKey extends StatelessWidget {
  const _PadKey({
    this.label,
    this.icon,
    required this.semantics,
    required this.onTap,
    this.quiet = false,
  });
  final String? label;
  final IconData? icon;
  final String semantics;
  final VoidCallback onTap;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: semantics,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 92,
            height: 62,
            child: Center(
              child: Container(
                width: 74,
                height: 52,
                alignment: Alignment.center,
                decoration: quiet
                    ? null
                    : BoxDecoration(
                        color: p.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: p.ink, width: 2),
                        boxShadow: [
                          BoxShadow(color: p.ink, offset: const Offset(0, 2)),
                        ],
                      ),
                child: label != null
                    ? Text(label!, style: heading(24, color: p.text))
                    : Icon(icon, size: 26, color: p.text),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
