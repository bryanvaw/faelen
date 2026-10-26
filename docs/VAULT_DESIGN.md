# Vault — UI/UX design

Extends the existing Faelen world (outlined style: ink outline, hard offset shadow, coral accent, Outfit headings, DM Sans body, light and dark). No new visual identity. Prototype: `docs/vault_prototype.html` (synthetic demo data, open through a local web server such as `python -m http.server`).

**Mode:** Operate. The job is "find it and paste it in two taps". Speed and scanability beat decoration.

**Scene:** a phone in one hand, in a queue or on a form, with an app open that needs a number. The Vault has to come up, copy, and get out of the way.

## Structure

- **Gate:** the lock screen shows the calico-with-key cat on its lilac tile, a PIN pad, and a biometric button. Biometric is attempted automatically on open. Only the Vault is locked; Media stays instant.
- **Vault screen:** header (back, lilac key mark, "Vault", search, **Lock**), Favorites strip, list, add button, bottom bar with 4 sections: **Logins, Numbers, IDs, Shots**. Same bottom bar / side rail pattern as Media (rail at 720dp and wider).
- **Section colours:** Logins lilac (the old Passwords colour), Numbers green, IDs yellow, Shots coral. Text on these tiles is always ink (`onTile`), as elsewhere.

## Space budget (360x800)

Header 60 + Favorites 56 + bottom bar 72 leaves about 600dp for the list: **8 rows at 64dp** (plus 10dp gaps) before any scrolling.

## The row (collapsed, 64dp)

`[tile 44] title / subtitle ............ [Copy 48]` (Numbers add a Call button before Copy).

- **Copy** is the coral button on the right, in thumb reach. It copies the entry's *main field*: password for Logins, number for Numbers, ID number for IDs. The main field can be changed per entry in the edit form.
- Tapping the rest of the row **expands it in place**. There is no detail screen to open and come back from. Only one row is open at a time.
- Subtitles never show secrets. Logins show the username, Numbers the number (not secret), IDs the number masked to its last 2 to 4 characters.
- IDs carry an expiry chip: yellow under 60 days, red once expired.

## The row (expanded)

One 52dp line per field: small label above the value, then **eye** (secret fields only) and **copy** (all fields), both 44dp touch targets. Below: **Pin to top** (adds or removes the Favorites strip), **Edit**, and a red **Delete** (Undo snackbar, same as Media).

- Secret fields start masked (`••••••••`). **Copy never needs a reveal.** The eye is only for reading, and it re-hides itself after 10 seconds.
- Passwords are never shown in lists, favourites or notifications.

## Favorites strip

Horizontal chips, 48dp high: section tile + title + a tiny label naming what a tap copies ("password", "number"). One tap copies the main field. Pin from the expanded row. Not shown while searching.

## Copy feedback (the one authored moment)

No snackbar (it would cover the bottom bar and the list). The tapped button changes itself:

1. Icon becomes a check and the button turns green.
2. For secret values a 4dp ink bar along its bottom edge **drains over the auto-clear time** (default 30s), so the clipboard timer is visible without any text.
3. When the bar ends, the button returns to normal and the clipboard is cleared (only if it still holds our value).

Numbers and plain fields reset after about 2 seconds with no timer. A Favorites chip shows "copied · clears in 30s" in its label line. The confirmation is also announced to screen readers ("Copied password for Netflix").

## Numbers

Call button (opens the dialler, never calls directly) next to Copy. Copy gives digits as displayed; the expanded view offers raw digits (`09170000001`) as a second copy action if the formatted one is wrong for a form. A WhatsApp/SMS shortcut is deferred.

## Shots

3-column grid, 3:4 thumbnails, 2dp ink outline, title under each, tag chips on top for filtering. Tap opens a full-screen zoomable viewer with Share, Rename/Tag and Delete. Search covers titles and tags only. Images are copied *into* the app (encrypted), then the user is offered to delete the gallery original.

## Add / edit

Bottom sheet with a pinned Save bar, same as the Media form. It opens for the current section. Login: title, username, password (generator button inside the field, show/hide), link, notes, main field. Number: title, number, note. ID: type, title, number, expiry, optional photo. Shot: pick image, title, tag. The add button is a 56dp coral square at bottom right above the bar.

## Search

Same header behaviour as Media (icon turns the row into a field). **Titles and tags only**, never usernames, passwords or ID numbers.

## States

- **Empty section:** the calico cat, a one-line explanation, an Add button.
- **No search match:** "No match. Search looks at titles only."
- **Wrong PIN:** shake, then delays after repeated failures (5 tries, then 30s, 1 min, 5 min).
- **Biometric cancelled or unavailable:** PIN pad stays; nothing else changes.
- **Locked while copying:** copying stops working the moment the Vault locks, and the clipboard is cleared.
- **Auto-lock:** after the app is in the background for 30s (setting: immediately, 30s, 1 min, 5 min), and the Lock button locks now.
- **Large text (up to 1.3x):** rows grow, titles ellipsis, buttons keep 48dp.

## Accessibility

All touch targets 48dp (44dp for in-row secondary icons); every icon button has a spoken label that names the field and the entry; no information by colour alone (the expiry chip carries text); reduced-motion makes the drain bar a static check; 4.5:1 text contrast in both themes (same palette as Media).

## Security touches that shape the UI

- `FLAG_SECURE` on Vault screens: blank in recent apps, no screenshots.
- Copy marks the clipboard item as sensitive on Android 13+ (hides the preview toast) through a small platform channel.
- **Risks to verify on a real phone:** whether the clear still runs reliably after the app goes to the background, and whether keyboard clipboard history (Gboard, Samsung) keeps a copy we cannot remove.

## Prototype fixes after one inspection pass

Numbers rows showed two phone icons side by side (tile and Call button); the tile now uses the first letter like Logins. Everything else in the pass (row, expanded fields, copy state, Numbers, Shots grid, dark mode) read correctly at phone width.
