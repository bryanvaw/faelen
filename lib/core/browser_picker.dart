import 'package:flutter/material.dart';

import 'link_opener.dart';
import 'theme.dart';

/// "Ask every time": Faelen's own list of the browsers installed on the phone, shown when a link is
/// about to open. Returns the browser tapped, or null when the sheet is dismissed. It does not depend
/// on Android's "Open with" list, which differs from phone to phone.
Future<Browser?> showBrowserPicker(BuildContext context, List<Browser> browsers) {
  return showModalBottomSheet<Browser>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _BrowserPicker(browsers: browsers),
  );
}

class _BrowserPicker extends StatelessWidget {
  const _BrowserPicker({required this.browsers});
  final List<Browser> browsers;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Open with', style: heading(22, weight: FontWeight.w700, color: p.text)),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 16),
          child: Text('Pick a browser for this link. To always use one, go to Settings > Open links with.',
              style: TextStyle(color: p.subText, fontSize: 13, height: 1.35)),
        ),
        for (final b in browsers)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Semantics(
              button: true,
              label: 'Open in ${b.label}',
              onTap: () => Navigator.pop(context, b),
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(context, b),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 56),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: brutal(p, color: p.card, radius: 16, shadow: 0, border: 1.5),
                    child: Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: SizedBox(
                          width: 42,
                          height: 42,
                          child: b.icon == null
                              ? ColoredBox(color: p.field, child: Icon(Icons.public_rounded, size: 22, color: p.text))
                              : Image.memory(b.icon!, fit: BoxFit.cover, gaplessPlayback: true, excludeFromSemantics: true),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Text(b.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(16, weight: FontWeight.w700, color: p.text))),
                      Icon(Icons.chevron_right_rounded, color: p.subText),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
