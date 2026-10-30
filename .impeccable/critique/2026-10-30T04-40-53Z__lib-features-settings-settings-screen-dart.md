---
target: "new Settings rows: Open links with, Block Vault screenshots"
total_score: 27
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 1
timestamp: 2026-10-30T04-40-53Z
slug: lib-features-settings-settings-screen-dart
---
⚠️ DEGRADED: single-context (agent spawning is restricted to explicit user requests in this session; Assessment B detector reads web markup and cannot parse Dart, so it returned [] and is not meaningful)

Target: Settings rows "Open links with" (row + bottom sheet) and "Block Vault screenshots" (switch), lib/features/settings/settings_screen.dart. Mode: Operate. Source-only review; no on-device render available.

Score 27/40 (Acceptable).

Heuristics: 1 Status 3 · 2 Real world 3 · 3 Control 3 · 4 Consistency 3 · 5 Error prevention 2 · 6 Recognition 3 · 7 Flexibility 2 · 8 Minimalist 3 · 9 Error recovery 2 · 10 Help 3.

Priority issues
- [P1] Screenshot switch: off-state copy is a developer note ("Turn on again when you finish testing"), states no risk; security downgrade is one tap; sits among media preferences.
- [P2] Browser list failure is reported as "No other browsers were found" (wrong when the query fails).
- [P2] Sheet rows have no onTap on their Semantics node and no mutually-exclusive group; screen-reader activation unverified (pattern is inherited from Appearance sheet and Vault).
- [P2] Preferences card is now 5 always-visible rows (7 with reminders on); tile colours repeat with no meaning (movie colour on two rows, drama on two).
- [P3] No way to try the chosen browser from the sheet; it closes straight away.

Strengths: row shows current value; real browser icons with compact rows; modes separated from browsers; safe fallback to default browser when the chosen one is gone.
