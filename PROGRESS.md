# Faelen — Project Overview & Progress

> App name: **Faelen** (package `faelen`, Android id `com.faelen.app`). Started as a media tracker; now being grown into a multi-module personal app (see "Direction"). The project folder is still named `media_tracker_flutter`.
>
> **Status (2026-10-21):** installed on the author's phone: 1.4.1 (released). In the repo: **1.6.0+13**, not yet released: SQLite storage, a lazy list for big libraries, schedule pause, safer saves and backups, pinned notifications with +1/Done buttons, tap a reminder to open the link, Mo Tu We Th Fr Sa Su release days, hub redesign, Appearance sheet, restyled Settings buttons, softer empty status tiles, new entries start as the current tab. If 1.4.1 was built with a build number above 11, raise the `+12` in `pubspec.yaml` above it. Release 1.3.1 was published with the wrong APK and then deleted, so it never shipped; see "Release lessons". 156 tests pass, `flutter analyze` is clean.

## What the project is

A personal, local-first mobile app for tracking a watch/read list across four media types:

- **Webtoon** (tracked in chapters; called Manhwa in the code, `MediaType.manhwa`)
- **Anime** (episodes)
- **Movies**
- **K-Dramas** (episodes)

Everything is stored on the device. There is no account, no server and no CSV file. The app is built with **Flutter** (Material 3), so it runs on Android, iOS, web and desktop from one codebase. Covers, link lookups and notifications only work on Android/iOS/desktop builds, not in the browser build.

### Entry fields

| Field | Notes |
|---|---|
| ID | Generated automatically |
| Title | Required |
| Media type | Webtoon, Anime, Movie, Drama. A new entry starts as the tab it was added from; a reading link on a new entry switches it to Webtoon |
| Status | Plan to Watch, Currently Watching, Completed, On Hold, Dropped |
| Current episode/chapter | Cannot exceed the total |
| Total | 0 means unknown |
| Season | Optional (0 = none). Detected from the link or page title; shown as `S2 · Ep 3 / 12` |
| Rating | Stored 1–10 (0 = unrated); shown as 5 stars with half steps |
| Notes | Free text |
| Link | Optional web address to continue reading/watching; also used to read the chapter/episode number and season |
| Cover | Optional photo (stored as a file; the entry keeps the file name). Can be fetched from the link or by title |
| Release days | Optional weekdays (1 = Mon ... 7 = Sun, several allowed) when new chapters/episodes come out; not for movies |
| Out so far / as of | `releasedCount` on the day `releasedOn`; the count then grows by one on each release day |
| Reminder time | Optional minutes after midnight for that entry's notification; default 9:00 |
| Updated at | Set automatically on every save; drives "Recently updated" sorting and backup merging |

### Features

- Add, edit and delete entries (bottom sheet form with validation and a pinned Save bar).
- Compact header row (back, brand mark, "My List", and a search button that turns the row into a search field; on 600dp+ the field stays open beside the title).
- Filter by status (compact colored 3x2 tiles with counts) and by type (bottom bar or side rail).
- Sort by title, recently updated, highest rated or most unread releases (remembered).
- Cards: title, type and status, `Ch 74 / 120` label, rating, release chip, a slim progress bar when the total is known, the cover on the right (a type-colored icon tile when there is none), and full-width **Continue** and **+1** actions.
- Release tracker: pick release days, say how many are out today, and the card shows `N new` or `Caught up · Next Sat`. Capped at the total; only for Watching/On Hold entries.
- Release reminders (Settings, off by default): a weekly notification on each release day at 9:00, or the entry's own time.
- Link features: **Continue** opens the link; the chapter/episode number and season in the address can set your progress (Ask first or Automatic); pasting a link fills an empty title and cover (page Open Graph tags, address slug as a fallback), and when the page has no usable cover the show is looked up by title (AniList for anime/manhwa, TVmaze for dramas) for cover and total.
- Hub home screen with module cards (Media now; Planner, Budget and Passwords are "coming soon") and a Settings screen.
- Settings: two grouped cards. Preferences (Appearance sheet: System default/Light/Dark, Progress from links switch, Release reminders switch with default time and test notification) and App and data (version row with Check for updates, Backup Export/Import as a JSON file, merge or replace).
- In-app updates from GitHub releases.
- Responsive layout: bottom bar on phones, `NavigationRail` at 720px and wider, card grid of 1, 2 or 3 columns, content capped at 1100px.
- Design: flat "outlined" style (bold black outlines, hard offset shadows, bright status colors, coral accent, no gradients). Fonts are Outfit for headings and DM Sans for body text. Light and dark palettes.

## Tech stack

| Area | Choice |
|---|---|
| Framework | Flutter 3.47.7 / Dart 3.13.5 |
| State | `provider` (`ChangeNotifier`) |
| Storage | The media list is a SQLite file (`sqflite`; `sqflite_common_ffi` on Windows/Linux), one row per entry; saving writes only changed rows. Settings and the sort choice stay in `shared_preferences`. The browser build and the tests fall back to the old JSON string under `media_entries_v1`. Cover images are files via `path_provider`, picked with `image_picker` |
| Updates | `package_info_plus` (installed version); `UpdateService` calls the GitHub releases API with `dart:io` |
| Links | `url_launcher` opens the saved link; `LinkPreviewService` reads page tags with `dart:io` |
| Catalogues | AniList GraphQL (anime/webtoon) and TVmaze (dramas), no keys; TMDB for movie covers (free v3 key in the git-ignored `lib/core/secrets.dart`; template in `secrets.example.dart`; empty key turns it off) |
| Notifications | `flutter_local_notifications` + `timezone` + `flutter_timezone`; inexact alarms (no exact-alarm permission); Android needs desugaring, `POST_NOTIFICATIONS` and boot receivers (already in the manifest/gradle) |
| Backup | `share_plus` (export) and `file_picker` (import) |
| Icon/splash | `flutter_launcher_icons`, `flutter_native_splash` (config at the bottom of `pubspec.yaml`; rerun `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create` after changing `assets/icon/`) |
| Fonts | `google_fonts` pinned to `>=8.0.0 <9.0.0` (v9 and v6.3 have build problems) |

## Project structure

```
lib/
  main.dart                          App entry, theme, provider setup, keeps reminders in sync, opens the hub
  core/
    secrets.dart                     TMDB key (git-ignored; copy secrets.example.dart and paste the key)
    theme.dart                       Palette, brutal() decoration, fonts (shared by all modules)
    settings_store.dart              Theme mode, link progress mode, release reminders switch
    update_service.dart              GitHub release check
  features/
    hub/hub_screen.dart              Home: module cards (Media; others "coming soon")
    settings/                        Settings screen and BackupService
    media/
      media_theme.dart               Status/type colors and icons, rating label
      models/media_entry.dart        MediaEntry, MediaType, Status (release and season fields)
      services/cover_service.dart    Cover image files in the app documents folder
      services/url_progress.dart     UrlProgress (chapter/episode in a link), SeasonDetect, TypeGuess
      services/link_preview_service.dart  Page title/cover, address-slug fallback, AniList/TVmaze lookup
      services/release_schedule.dart Release counting per weekday ("N new", next release)
      services/release_reminders.dart Weekly local notifications per release day
      services/storage_service.dart  Load/save; SQLite in the app (diffed per row, one-time import of the old JSON list), JSON string without a database
      services/entry_database.dart   The SQLite file: schema, read all, write changed rows
      state/media_store.dart         Items, filters, search, sort, CRUD, backup data
      screens/media_screen.dart      Header with search, status tiles, list, bottom bar / rail
      widgets/media_card.dart        Entry card (cover right, progress bar, actions)
      widgets/media_form_sheet.dart  Add/edit form
test/
  sqlite_storage_test.dart           SQLite persistence, per-row writes, JSON migration, cached list, lazy list with 1000 entries
  safety_test.dart                   Damaged data recovery, undo delete, queued saves, new sorts, reminder default time
  stats_layout_test.dart             Stats screen fits 360x740 in light and dark
  storage_test.dart                  Persistence and filter tests
  responsive_test.dart               No-overflow checks at 4 screen sizes, light and dark
  hub_test.dart                      Hub lists modules, opens Media, back works
  form_test.dart                     Add form: chips, stepper, star rating, movie hides progress
  backup_sort_test.dart              Sorting, backup export/import (incl. covers, merge, bad files), theme persistence
  link_preview_test.dart             Open Graph parsing, title cleanup, catalogue fallback, form autofill, type switching
  update_service_test.dart           Version compare, GitHub release parsing, once-a-day throttle
  url_progress_test.dart             Number detection on many URL shapes, normalize, url JSON round trip
  season_test.dart                   Season detection, type guess from links, season JSON
  release_schedule_test.dart         Weekly counting (incl. several days), reminders plan, old backups
  card_layout_test.dart              Busiest card fits 320dp at large text; progress bar; actions
  header_search_test.dart            Search button opens/closes the field; wide screens keep it open
  settings_ui_test.dart              Settings switches theme; labels stay on one line; sort menu
  settings_layout_test.dart          Settings fits a 360x800 phone; links switch
```

## Progress

### Done
- [x] Switched from React Native/Expo to Flutter, dropped CSV for on-device storage, removed the old project, set up the Windows toolchain (Flutter SDK, JDK 17, Android SDK).
- [x] Core media list: CRUD, search, status and type filters, sorting, +1 button, responsive layout, outlined design (2026-10-15).
- [x] Renamed to Faelen; refactored into `core/` + `features/`; added the module hub and a Passwords "coming soon" card (2026-10-15/16). Folder not renamed yet.
- [x] Dark mode (System/Light/Dark), backup export/import with covers, cover images, app icon and splash, bottom bar restyle (2026-10-15).
- [x] Links: Continue button, chapter/episode read from the address (no network), Ask first / Automatic (2026-10-15).
- [x] In-app updates from GitHub releases; release builds signed with a real key; INTERNET permission added (2026-10-16). Releases 1.1.0, 1.2.0 and 1.2.1 shipped; the phone's update check works against the real GitHub API.
- [x] Auto title and cover from a pasted link, hardened for JavaScript sites and blocked pages (address-slug fallback). Verified against MangaDex, Wikipedia, Anikoto, KissKH, Moviesjoy and Asura Scans (2026-10-16).
- [x] Release tracker + reminders (2026-10-19): release days (several per week, so a drama can air Sat + Sun), "out so far" count, "N new" / "Caught up" chip, sort by unread releases, optional per-entry reminder time, weekly local notifications (off by default). Old single-day backups still load.
- [x] Seasons and smarter links (2026-10-19): season detected from the link or title; a reading link on a new entry picks Manhwa (never overrides a type the user tapped); when a page has no cover, or its cover cannot be downloaded, the show is looked up by title on AniList/TVmaze (cover, and total if known). Verified live against AniList, TVmaze and the Asura Scans link for The Margrave's Worthless Mage.
- [x] UI refresh (2026-10-19): compact add/edit form with pinned Save; Media screen with a one-row header and search button, compact status tiles, full-width card actions, cover on the right with a slim progress bar (the old ring was removed as redundant); Settings in two grouped cards that fit a 360x800 phone without scrolling.
- [x] Release 1.3.1 mistake (2026-10-19): the GitHub release had `app-debug.apk` (167 MB, debug key) attached instead of `app-release.apk`, so installs failed with "package conflicts with an existing package". The release was deleted; the stale tag `v1.3.1` may still exist. The next release is **1.4.0+7** (1.3.2 never shipped, so that number is skipped).

- [x] Movie covers from TMDB (2026-10-19, unreleased): a link pasted into a Movie entry with no page cover is searched on TMDB (year in "(2026)" narrows it), poster downloaded; Settings shows the required TMDB credit. The key is bundled in the APK, so it only exists in builds made on a machine that has `lib/core/secrets.dart`. The stats screen was also redesigned to fit one phone screen (hero card with status bar, three counters, by-type bars).
- [x] Cat branding (2026-10-19, unreleased): app icon, splash, web favicon (64px) and a different cat per module (see below), with the old icon files and unused Material icon fallbacks removed.
- [x] New app icon (2026-10-19, unreleased): the Media orange tabby on lilac (it reuses `assets/cats/media.png`'s artwork; earlier a coral cat), made in Canva. Details of the file split below still apply: a neo-brutalist cat head on lilac (`#B99BFF`), made in Canva. `icon.png` is the full icon, `icon_bg.png` a solid lilac square, `icon_fg.png` the cat on transparent, scaled to sit inside Android's adaptive-icon safe zone. The splash screen (all three variants) now uses the same lilac background so the cat stays visible. Regenerated with `flutter_launcher_icons` and `flutter_native_splash`.
- [x] Settings and Media polish (2026-10-19, unreleased): Appearance is one row that opens a bottom sheet with System default, Light and Dark cards (replaces the segmented button); Settings buttons (Check for updates, Export, Import, Download) share one outlined button that sinks when pressed, and the update result is a tinted note with an icon; empty status tiles keep their full colour but sit flat (no shadow, thinner outline) instead of fading to pastel; a new entry starts as the type of the tab it was added from; the sort menu matches the app.
- [x] Hub redesign (2026-10-19, unreleased): Media is a large card showing live counts (N watching, N new) with its cat on a colour tile, a Pick up where you left off strip (last followed title, Continue opens its link), and Planner, Budget and Passwords as small Soon tiles that explain themselves when tapped. Cards sink on press. Each cat now sits on its module colour so its black outline reads in dark mode.
- [x] Cat marks per module (2026-10-19, unreleased): `assets/cats/media.png` (256x256 transparent PNG, outline and shadow baked in) replaces the Media tile on the hub and the brand mark in the Media header. A new module needs its own `assets/cats/<name>.png` and a `cat:` on its entry in `hub_screen.dart` (the old coloured icon tiles were removed). All four modules have a different cat: Media (orange tabby), Planner (Siamese with a pencil), Budget (black-and-white tuxedo with a coin), Passwords (calico with a key).
- [x] Also in this release: the sort menu is styled to match the app (outline, accent check mark); the stats screen sits in a chart icon beside the sort menu.
- [x] Notifications upgrade (2026-10-21, unreleased): tapping a release reminder opens the entry's link; release-day buttons are now Mo Tu We Th Fr Sa Su; **pinned notifications** (Android only): tapping **Continue** pins the entry automatically (a fourth pin drops the oldest) and the bell button on a card pins or unpins by hand, up to 3 unfinished series to the notification shade with **+1** and **Done** buttons that update the saved list with the app closed (`pinned_actions.dart` background handler, `pinned_store.dart`, `ActionBroadcastReceiver` in the manifest). The app re-reads the list when it comes back to the foreground. The notification has a cat status-bar icon (`res/drawable/ic_stat_faelen.xml`, kept from shrinking by `res/raw/keep.xml`), the cover (or the orange cat) as its large icon, a progress bar when the total is known, a type · status line, buttons that name the exact chapter ("Read Ch 35") plus "Mark done", and a "3 new waiting" / "Caught up · Next Sat" line. Not yet tried on a real phone. Known gap: if the shade is pulled over the open app, a button press is only picked up after the app is backgrounded and resumed. Tests in `test/pinned_test.dart`.
- [x] Safety and polish pass (2026-10-19, unreleased): Manhwa shown as "Webtoon" (enum name `manhwa` kept so saved data still loads); "All" status tile readable in dark mode; tolerant loading (bad entries skipped, unreadable list restored from the previous copy, dismissible notice; the unreadable text is kept under `media_entries_corrupt_v1`); saves are queued; delete has a 6-second Undo; "N new" chip marks everything caught up when tapped; reminders re-plan when the app returns to the foreground; Settings: default reminder time, test notification, timezone warning, "last backup" note; sorts by progress and recently added; empty status tiles fade; library stats screen (chart icon beside the sort menu); an entry with a link but no cover quietly looks for one when opened. Tests in `test/safety_test.dart`.

- [x] Big-library performance (2026-10-22, unreleased): the list is built lazily (`CustomScrollView` + rows in a `SliverList`, so only visible cards exist); `MediaStore.visible` and the status counts are cached until the list, a filter, the query, the sort or the day changes, and `items` is a view instead of a copy; the media list moved from one JSON string to SQLite (`entry_database.dart`), where a save writes only the changed rows and so can no longer overwrite a change the notification buttons made from another isolate. First launch after updating copies the old JSON list across once and leaves it in `shared_preferences` as a fallback. Status tile counts of 1000+ no longer overflow. Not done on purpose: page-by-page "load more" in the UI, because the lazy list already only builds what is on screen and the full list stays in memory for stats, the hub and the release sorts. **Not yet tried on a real phone**: check that an existing library survives the update, and +1 from a pinned notification with the app closed.
- [x] Review fixes (2026-10-22, unreleased): (1) syncing release reminders called `cancelAll()`, which also removed the pinned titles from the shade (and they were not shown again); it now cancels only scheduled reminders, and `ensureReady()` no longer runs its setup twice when two callers arrive together; (2) the edit form's "Out so far" showed the count saved weeks ago, so changing a release day reset the figure to that stale number; it now starts at today's figure and only re-anchors when the days or the number are edited; (3) after a resume with nothing changed, the next save rewrote every row and could undo a notification-button +1; unchanged entries now keep their instance. Tests in `test/review_fixes_test.dart`.
- [x] Hardening pass (2026-10-22, unreleased): a failed save now shows a snackbar (`takeSaveError`; the "could not load" banner is separate); in-app +1 and "mark caught up" go through `MediaStore.update`, which reads the newest saved copy of that one entry first, so a notification +1 is never overwritten; the release schedule pauses while a show is not Watching/On Hold (`settleSchedule`, also applied by the notification Done button) and resumes from the return day; Undo after a delete brings the pin back; covers nobody uses are swept at startup (never after a partial read, never when the list is empty); cover names with `/`, `\` or `..` are refused; backup values are corrected on read (negative counts, rating over 10, progress past the total, non-web links, bad reminder times); a replace-import keeps the old pictures if its save fails; the hub's Continue pins the title like the card's; a failed update check no longer blocks the next launch's check; list rows are keyed by the entries in them. Tests in `test/hardening_test.dart`. 188 tests pass.

### Not done yet
- [ ] **Release 1.6.0 (it includes everything that was going to be 1.5.0):** `pubspec.yaml` is already `1.6.0+13`. Commit and push the work on its branch (`feat/sqlite-lazy-list-hardening`), merge the pull request into `main` (main still says 1.2.1+4), `flutter build apk --release` on this PC (needs `lib/core/secrets.dart`), then create tag `v1.6.0` on `main` with only `app-release.apk` (about 56 MB) attached. See "Releasing".
- [ ] Check on a real phone, using a release build (a debug build cannot install over the release-signed app): covers fetched from a pasted link and by title (needs internet; not available in the browser build), the notification actually arriving on a release day, the compact form, header search and Settings layouts, dark theme everywhere.
- [ ] Finish the "Phone checklist" below. Confirmed on the phone so far (1.1.0 to 1.2.1): the update check and download offer, link autofill (Asura Scans), and the cover from a link in 1.2.1. Not yet checked: share sheet, file picker, gallery picker, splash screen, adaptive icon masks.
- [ ] Back up the signing key (`C:/Users/Bryan/.faelen/faelen-release.jks` and `android/key.properties`). The 1.2.1 and local release builds both use certificate SHA-256 `22473701df12...`.
- [ ] Rename the project folder to `faelen` (close the IDE first; the package rename is done).
- [ ] Still open from the review: Budget can reuse `EntryDatabase` (add its own table); encrypted backups; a way to pause a show's release schedule during a hiatus (today you edit "out so far"); backing up the signing key is manual.
- [ ] Movies: no episode total (not needed) and no title-only "Find cover" button yet; lookup only runs from a pasted link.
- [ ] Small ideas: a "Find cover" button or automatic lookup when opening an entry that has a link but no cover; fade empty status tiles; "Send test notification" button in Settings; a time picker for the default reminder time; "mark all caught up" on the release chip.
- [ ] Optional ideas: sort by progress or date added, app lock, cloud sync, Up next strip, watch history and stats.
- [ ] Floating Faelen bubble over the reading/watching app to update progress (Android overlay; needs "display over other apps" and a plugin such as `flutter_overlay_window`; not started).
- [ ] Passwords, Planner and Budget modules (see "Direction").

## Direction: from media tracker to personal life app (proposed, 2026-10-15)

Faelen is meant to grow beyond entertainment tracking into one local-first personal app with several modules. The current media tracker becomes the first module, not the whole app.

| Module | Purpose | Status |
|---|---|---|
| **Media** | Manhwa, anime, movies, K-dramas | Built (tracker, release reminders, seasons, cover lookup); waiting on a full real-device check |
| **Planner** | Tasks, goals, schedule/reminders | Idea only |
| **Budget** | Income, expenses, categories, monthly budgets | Idea only |
| **Passwords** | Account/password manager: site, username, password, notes | Idea only (placeholder card on the hub) |

### Proposed scope (to be confirmed)

**Planner**
- Tasks with due date, priority, status and optional recurrence.
- Today / Upcoming / Done views.
- Optional local notifications for reminders (the notification plumbing from the release tracker can be reused).
- Possible later: goals with milestones, a weekly view.

**Budget**
- Transactions (amount, category, date, note, income or expense).
- Categories with a monthly limit and a progress bar.
- Monthly summary: total in, total out, remaining, spending by category.
- Possible later: recurring bills, savings goals, CSV export.

**Passwords** (idea, to be confirmed)
- Entries: site/app name, link, username, password, notes, optional category.
- Must be encrypted at rest, not plain JSON in `shared_preferences`: store entries in an encrypted store with the key held in the Android Keystore / iOS Keychain (for example `flutter_secure_storage`), and require an app lock (biometric/PIN) before showing anything.
- Backups must be encrypted too (a passphrase-protected export), unlike the current plain Media backup, and must stay out of the plain Media backup file.
- Copy-to-clipboard with auto-clear, a password generator, and hide-by-default are expected basics.
- Honest limit: this would be a personal vault, not a replacement for a dedicated manager (no browser autofill, no sync); worth deciding up front whether that is acceptable.

### Technical implications

- **Navigation:** done as a hub screen. Each module opens full-screen with its own bottom bar/rail, and a back arrow in its header returns to the hub.
- **Folder structure:** done. `lib/core/` holds the theme and settings; each module lives in `lib/features/<module>/` with its own models, state and screens.
- **Storage:** `shared_preferences` with one JSON blob is fine for the media list but does not suit budget transactions, which grow without bound and need date and category queries. Plan to move to a local database (for example `drift` or `sqflite`) for Budget, and probably migrate Media and Planner to it as well so there is one store and one backup path.
- **Money:** store amounts as integer minor units (cents/centavos), never `double`. Decide the currency up front (single currency to start).
- **Backup/export:** done for Media (one JSON file with a version number and an `app` marker; `BackupService` in `features/settings/`). New optional entry fields are written only when set, so older backups still import. Planner and Budget should add their own keys next to `media`. Backups are plain, unencrypted JSON, which matters more once finances are included.
- **Privacy:** budget data is sensitive. Keep everything on-device, and consider an app lock (biometric/PIN) later.

### Suggested order

1. ~~Rename to Faelen~~, ~~refactor into `core/` + `features/`~~, ~~sorting, dark mode, backup, covers, icon and splash~~ (done).
2. ~~Media extras: release tracker, reminders, seasons, cover lookup, UI refresh~~ (done; shipped in 1.4.0 and 1.4.1).
3. Decide on the database and add it with a migration for existing media data.
4. Build Budget first (clearest value and the most data-model risk), then Planner.
5. Extend backup to cover Budget and Planner.

### Open questions

- Which module first: Budget or Planner?
- Single currency or multiple?
- Should Planner and Budget link up (for example a bill as a task with an amount)?
- Is a Google-Drive-style sync ever wanted, or stay strictly on-device?

## Phone checklist

Use a **release** build (`flutter build apk --release`, or the release APK from GitHub). It is signed with the Faelen key and installs over the old version; a debug build cannot.

- [ ] App icon and splash show correctly.
- [ ] Hub, Media, Settings and the add/edit form look right in light and dark.
- [ ] Paste a link such as an Asura Scans chapter link into a new entry: type switches to Manhwa, title, cover and chapter fill in. Then one from Anikoto (anime, cover by title).
- [ ] Add an entry with a cover from the gallery; it shows on the card (right side) and survives closing the app.
- [ ] Release days: set a day (try two, like Sat + Sun), see "N new" / "Caught up" on the card; turn on Settings, Release reminders, allow the permission, and confirm a notification arrives on a release day.
- [ ] Tap a release reminder: the entry's link opens. Tap Continue on an entry with a link (or pin it with the bell), close the app, press +1 in the notification, reopen: the chapter went up. Done removes the notification.
- [ ] Header search icon opens the search field and the close button clears it.
- [ ] Settings > Export opens the share sheet; save the file somewhere (Drive, Files).
- [ ] Settings > Import with that file, in both Merge and Replace modes.
- [ ] Sort menu changes the order and is remembered after a restart.
- [ ] Link with `.../chapter-45`: Ask first shows the "Use it" prompt, the switch on (Automatic) fills progress; Continue opens the link.
- [ ] Adaptive icon looks right under round and square launcher masks.

## Releasing (GitHub)

0. **Build on this PC only.** `lib/core/secrets.dart` (the TMDB key) is git-ignored, so it is not in the repo. A fresh clone or CI will not compile until `secrets.example.dart` is copied to `secrets.dart`, and movie covers need a real key in it.
1. Bump `version:` in `pubspec.yaml` (currently `1.6.0+13`). The number after `+` must go up every release or Android refuses the update.
2. `flutter build apk --release` (signed with the Faelen key automatically). Check the output is `build/app/outputs/flutter-apk/app-release.apk` (about 56 MB). The `app-debug.apk` next to it (about 167 MB) must never be attached.
3. Merge the version bump into `main` first, then publish a release tagged `v<version>` on `main` with `app-release.apk` attached. The `gh` CLI is not installed on this PC; use github.com/bryanvaw/faelen/releases/new, type the tag (for example `v1.6.0`) and choose "Create new tag on publish", write short notes (the update screen shows them), and attach the APK by clicking inside the dashed box (not by dragging into the notes box).
4. Check the attached file name and size before clicking Publish. Phones pick the release up from Settings > App updates, or at the next launch (within a day).

The repo must be **public** for the app to read releases without a login.

### Release lessons

- **Wrong file:** the 1.3.1 release had the debug APK attached, which fails to install over a release-signed app ("App not installed as package conflicts with an existing package"). You can check what a release carries without downloading: `curl https://api.github.com/repos/bryanvaw/faelen/releases/tags/<tag>` lists the asset name and size.
- **Deleting a release keeps its tag.** Reusing the tag points the new release at the old commit; prefer a new version number, or delete the tag too (`git push origin --delete <tag>` and `git tag -d <tag>`).
- **Version first:** build only after the version is bumped; an APK built before the bump still reports the old version.

### Signing key (do not lose it)

- Keystore: `C:/Users/Bryan/.faelen/faelen-release.jks`, passwords and alias in `android/key.properties` (git-ignored). **Back both up somewhere safe** (password manager or cloud drive). If the key is lost, installed phones can never be updated in place; they would have to uninstall first.
- Without `key.properties` the build falls back to the debug key, which will not install over a release-signed app.
- Check an APK's signer with `C:\Android\build-tools\36.0.0\apksigner.bat verify --print-certs <apk>`: the Faelen release key is `CN=Faelen, O=Faelen, C=PH`, SHA-256 `22473701df12aca155504d706e03de0e2b1eb1a9d14c98892957659f162252dc`; the debug key is `CN=Android Debug`.
- One-time switch: phones that have a build signed with the old debug key must uninstall once before installing a release build (export a backup from Settings first, then Import after). Every update after that installs in place.

## How to run

```bash
flutter pub get
flutter run -d windows         # desktop: covers, link lookups; needs Windows Developer Mode
flutter run -d web-server --web-port 8080   # browser: no covers, link lookups or notifications
flutter test
flutter analyze
flutter build apk --release    # output: build/app/outputs/flutter-apk/app-release.apk
```

Windows setup notes: Developer Mode is required for Flutter plugin symlinks (`start ms-settings:developers`). Restart the terminal after PATH changes so `flutter` is recognized.
