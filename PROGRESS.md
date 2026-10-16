# Faelen — Project Overview & Progress

> App name: **Faelen** (package `faelen`, Android id `com.faelen.app`). Started as a media tracker; now being grown into a multi-module personal app (see "Direction"). The project folder is still named `media_tracker_flutter`.

## What the project is

A personal, local-first mobile app for tracking a watch/read list across four media types:

- **Manhwa** (tracked in chapters)
- **Anime** (episodes)
- **Movies**
- **K-Dramas** (episodes)

Everything is stored on the device. There is no account, no server and no CSV file. The app is built with **Flutter** (Material 3), so it runs on Android, iOS, web and desktop from one codebase.

### Entry fields

| Field | Notes |
|---|---|
| ID | Generated automatically |
| Title | Required |
| Media type | Manhwa, Anime, Movie, Drama |
| Status | Plan to Watch, Currently Watching, Completed, On Hold, Dropped |
| Current episode/chapter | Cannot exceed the total |
| Total | 0 means unknown |
| Rating | Stored 1–10 (0 = unrated); shown as 5 stars with half steps |
| Notes | Free text |
| Link | Optional web address to continue reading/watching; also used to read the chapter/episode number |
| Cover | Optional photo from the gallery (stored as a file; the entry keeps the file name) |
| Updated at | Set automatically on every save; drives "Recently updated" sorting and backup merging |

### Features

- Add, edit and delete entries (bottom sheet form with validation).
- Search by keyword. Filter by status (tiles on the home screen) and by type (bottom bar or side rail).
- Sort by title, recently updated or highest rated (remembered).
- Optional cover image per entry, shown on the card.
- Hub home screen with module cards (Media now; Planner and Budget are placeholders) and a Settings screen.
- Optional link per entry: a **Continue** button on the card opens it, and a chapter/episode number in the address (`/chapter-45`, `ep_12`, `?ep=3`) can set your progress. Read from the address text only, never fetched.
- Settings: theme (System / Light / Dark), link progress mode (Ask first / Automatic) and backup (Export / Import a JSON file, merge or replace).
- Progress ring on every card, a progress label (for example `Ep 12 / 24`), and a one-tap **+1** button.
- Responsive layout:
  - Phones: bottom navigation bar.
  - 720px and wider: side `NavigationRail`.
  - Card grid: 1, 2 or 3 columns.
  - Content is capped at 1100px wide.
- Design: flat "outlined" style (bold black outlines, hard offset shadows, bright status colors, coral accent, no gradients). Fonts are Outfit for headings and DM Sans for body text. Light and dark palettes; the theme follows the system by default and can be set in Settings.

## Tech stack

| Area | Choice |
|---|---|
| Framework | Flutter 3.47.7 / Dart 3.13.5 |
| State | `provider` (`ChangeNotifier`) |
| Storage | `shared_preferences`, with the list saved as JSON under `media_entries_v1`; cover images as files via `path_provider`, picked with `image_picker` |
| Updates | `package_info_plus` (installed version); `UpdateService` calls the GitHub releases API with `dart:io` |
| Links | `url_launcher` opens the saved link in the browser or the site's app |
| Backup | `share_plus` (export) and `file_picker` (import) |
| Icon/splash | `flutter_launcher_icons`, `flutter_native_splash` (config at the bottom of `pubspec.yaml`; rerun `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create` after changing `assets/icon/`) |
| Fonts | `google_fonts` pinned to `>=8.0.0 <9.0.0` (v9 and v6.3 have build problems) |

## Project structure

```
lib/
  main.dart                          App entry, theme, provider setup, opens the hub
  core/
    theme.dart                       Palette, brutal() decoration, fonts (shared by all modules)
    settings_store.dart              Theme mode preference
  features/
    hub/hub_screen.dart              Home: module cards (Media; Planner and Budget "coming soon")
    settings/                        Settings screen (theme, backup) and BackupService
    media/
      media_theme.dart               Status/type colors and icons, rating label
      services/cover_service.dart    Cover image files in the app documents folder
      services/url_progress.dart     Finds the chapter/episode number in a link; normalizes pasted addresses
      models/media_entry.dart        MediaEntry, MediaType, Status
      services/storage_service.dart  Load/save JSON via SharedPreferences
      state/media_store.dart         Items, filters, search, sort, CRUD, backup data
      screens/media_screen.dart      Header, status tiles, list, bottom bar / rail
      widgets/media_card.dart        Entry card with progress ring and +1
      widgets/media_form_sheet.dart  Add/edit form
test/
  storage_test.dart                  Persistence and filter tests
  responsive_test.dart               No-overflow checks at 4 screen sizes, light and dark
  hub_test.dart                      Hub lists modules, opens Media, back works
  form_test.dart                     Add form: chips, stepper, star rating, movie hides progress
  backup_sort_test.dart              Sorting, backup export/import (incl. covers, merge, bad files), theme persistence
  link_preview_test.dart             Open Graph parsing, title cleanup, and the form filling title from a pasted link
  update_service_test.dart           Version compare, GitHub release parsing, once-a-day throttle
  url_progress_test.dart             Number detection on many URL shapes, normalize, url JSON round trip
  settings_ui_test.dart              Settings opens from the hub and switches theme; sort menu reorders the list
```

## Progress

### Done
- [x] Switched from React Native/Expo to Flutter (to avoid constant rebuilds).
- [x] Dropped CSV in favor of on-device local storage.
- [x] Removed the old React Native project.
- [x] Set up the Windows toolchain: Flutter SDK, JDK 17, Android SDK and licenses.
- [x] Core features: CRUD, search, status and type filters, progress rings, +1 button.
- [x] Responsive layout (phone, tablet, desktop).
- [x] Design restyled to the Streamline-style reference: white background, outlined cards, coral bottom bar with a center **+**.
- [x] Renamed to Faelen (2026-10-15): package, Android id/label, iOS/web/desktop names. Folder not renamed yet.
- [x] Refactored into `core/` + `features/` and added the module hub (2026-10-15). Media behaviour unchanged.
- [x] `flutter analyze` is clean and all 79 tests pass (re-run 2026-10-16, after link-autofill fixes).
- [x] Sorting (title, recently updated, highest rated), remembered between launches (2026-10-15).
- [x] Dark mode: System / Light / Dark switch in Settings (gear on the hub), remembered. Default is System.
- [x] Backup: Export shares a `faelen-backup-YYYY-MM-DD.json` file; Import can Merge (newer copy of a duplicate wins) or Replace. Covers are embedded in the file.
- [x] Cover images: pick a photo per entry (downsized to 600px wide); shown on the card. Android/iOS/desktop only (not web).
- [x] App icon and splash generated from `assets/icon/`. Redesigned 2026-10-15: the F is built from progress bars (teal bar ~80% full on top, yellow ~55% in the middle) with the black outline and hard shadow, over a flat coral tile with four tilted outlined squares in the media-type colors (lilac, blue, yellow, teal). No gradients, to match the app. Splash and adaptive-icon foreground use the F alone; the adaptive background is `icon_bg.png`.
- [x] Bottom bar restyled (labelled tabs, type-colour chips, raised add button) and add/edit form redesigned: type and status chips, +/- steppers, 5-star rating with half steps (still stored 0-10), progress hidden for movies.
- [x] Links (2026-10-15): optional URL per entry, **Continue** button on the card opens it, and the chapter/episode number is read from the address text (`services/url_progress.dart`, no network). Settings > Links chooses Ask first (default) or Automatic. URL is saved in backups. Not yet checked on a device.
- [x] In-app updates (2026-10-16): Settings > App updates has a manual check; the hub also checks quietly at launch (at most once a day) and shows a snackbar with Download. Reads the latest GitHub release of `bryanvaw/faelen` (`lib/core/update_service.dart`); Download opens the APK link in the browser. Release builds are now signed with a real key (see "Releasing"). Added the INTERNET permission to the main manifest (release builds had none, which would also have broken Google Fonts). Version bumped to 1.1.0+2.
- [x] Auto title and cover from a link (2026-10-16): pasting a link in the entry form reads the page's Open Graph tags (`services/link_preview_service.dart`) and fills an empty title and cover; a title or cover you already have is kept and offered as "Use title" / "Use cover". Cleans site names and chapter/episode suffixes from titles, ignores logos, never overwrites silently. Tried against real sites: works on MangaDex and Wikipedia; IMDb blocks it; AniList is rendered in JavaScript so has no readable title; MyAnimeList gives the title but only a generic image. Not yet tried on a phone.
- [x] Link autofill hardened (2026-10-16) after trying real anime/drama/movie/manhwa links: falls back to the title in the address slug ("Make-Me-Tingle--2026-" -> "Make Me Tingle (2026)") when the site is a JavaScript app that only shows a site-wide title, or blocks/fails; cleans "free X 2026 movie on Site" titles. Verified against Anikoto, KissKH, Moviesjoy and Asura Scans. KissKH gives no cover (JavaScript app). Settings screen labels no longer wrap on narrow phones. Not yet in a released APK (1.2.0 is published without these two fixes).
- [x] Release APK last rebuilt on 2026-10-15, before the new icon and links feature (superseded: rebuilt 2026-10-16 as 1.1.0+2 with the new signing key; not yet installed or published) (`build/app/outputs/flutter-apk/app-release.apk`, 50.4 MB).

### Not done yet
- [ ] Rebuild the APK, install it on a phone and run the "Phone checklist" below, including the new icon and links items. Nothing has been checked on a real device or emulator yet; layouts, the dark theme, the share sheet, the file picker, the gallery picker and the splash screen are only covered by automated tests or not at all.
- [ ] Commit the work. Everything since the initial commit (rename, refactor, redesigns, sorting, dark mode, backup, covers, icon) is uncommitted.
- [ ] Back up the signing key (`C:/Users/Bryan/.faelen/faelen-release.jks` and `android/key.properties`).
- [ ] Create the public GitHub repo `bryanvaw/faelen`, publish `v1.1.0` with the APK, then test Settings > App updates against it (not tested against the real GitHub API yet).
- [ ] Rename the project folder to `faelen` (close the IDE first; the package rename is done).
- [ ] Push to GitHub (`bryanvaw/faelen`).
- [ ] More reliable metadata: search by title through the AniList API (anime/manhwa, no key) and TMDB (movies/dramas, needs a free key) to get title, cover and total chapters/episodes, for sites the link reader cannot handle.
- [ ] Optional ideas: sort by progress or date added, app lock, cloud sync.
- [ ] Floating Faelen bubble over the reading/watching app to update progress (Android overlay; needs the "display over other apps" permission and a plugin such as `flutter_overlay_window`; not started).
- [ ] Passwords module (account/password manager): placeholder card is on the hub as "Coming soon" (2026-10-16). See "Direction" for the plan.
- [ ] Planner and Budget modules (see "Direction" below).

## Direction: from media tracker to personal life app (proposed, 2026-10-15)

Faelen is meant to grow beyond entertainment tracking into one local-first personal app with three modules. The current media tracker becomes the first module, not the whole app.

| Module | Purpose | Status |
|---|---|---|
| **Media** | Manhwa, anime, movies, K-dramas | Built; waiting on a real-device check |
| **Planner** | Tasks, goals, schedule/reminders | Idea only |
| **Budget** | Income, expenses, categories, monthly budgets | Idea only |
| **Passwords** | Account/password manager: site, username, password, notes | Idea only (placeholder card on the hub) |

### Proposed scope (to be confirmed)

**Planner**
- Tasks with due date, priority, status and optional recurrence.
- Today / Upcoming / Done views.
- Optional local notifications for reminders.
- Possible later: goals with milestones, a weekly view.

**Budget**
- Transactions (amount, category, date, note, income or expense).
- Categories with a monthly limit and a progress bar (reuse the progress-ring style).
- Monthly summary: total in, total out, remaining, spending by category.
- Possible later: recurring bills, savings goals, CSV export.

**Passwords** (idea, to be confirmed)
- Entries: site/app name, link, username, password, notes, optional category.
- Must be encrypted at rest, not plain JSON in `shared_preferences`: store entries in an encrypted store with the key held in the Android Keystore / iOS Keychain (for example `flutter_secure_storage`), and require an app lock (biometric/PIN) before showing anything.
- Backups must be encrypted too (a passphrase-protected export), unlike the current plain Media backup, and must stay out of the plain Media backup file.
- Copy-to-clipboard with auto-clear, a password generator, and hide-by-default are expected basics.
- Honest limit: this would be a personal vault, not a replacement for a dedicated manager (no browser autofill, no sync); worth deciding up front whether that is acceptable.

### Technical implications

- **Navigation:** done as a hub screen. Each module opens full-screen with its own bottom bar/rail, and a back arrow in its header returns to the hub. Planner and Budget cards are placeholders until built.
- **Folder structure:** done. `lib/core/` holds the theme and settings; each module lives in `lib/features/<module>/` with its own models, state and screens.
- **Storage:** `shared_preferences` with one JSON blob is fine for the media list but does not suit budget transactions, which grow without bound and need date and category queries. Plan to move to a local database (for example `drift` or `sqflite`) for Budget, and probably migrate Media and Planner to it as well so there is one store and one backup path.
- **Money:** store amounts as integer minor units (cents/centavos), never `double`. Decide the currency up front (single currency to start).
- **Backup/export:** done for Media (one JSON file with a version number and an `app` marker; `BackupService` in `features/settings/`). Planner and Budget should add their own keys next to `media`. Backups are plain, unencrypted JSON, which matters more once finances are included.
- **Privacy:** budget data is sensitive. Keep everything on-device, and consider an app lock (biometric/PIN) later.

### Suggested order

1. ~~Rename to Faelen~~ (done). Commit and push to GitHub still pending.
2. ~~Refactor into `core/` + `features/media/` with a module switcher~~ (done).
3. ~~Sorting, dark mode, backup, covers, icon and splash~~ (done; needs the phone check).
4. Decide on the database and add it with a migration for existing media data.
5. Build Budget first (clearest value and the most data-model risk), then Planner.
6. Extend backup to cover Budget and Planner.

### Open questions

- Which module first: Budget or Planner?
- Single currency or multiple?
- Should Planner and Budget link up (for example a bill as a task with an amount)?
- Is a Google-Drive-style sync ever wanted, or stay strictly on-device?

## Phone checklist

Install `build/app/outputs/flutter-apk/app-release.apk`, then check:

- [ ] App icon and splash show correctly.
- [ ] Hub, Media, Settings and the add/edit form look right in light and dark.
- [ ] Add an entry with a cover from the gallery; it shows on the card and survives closing the app.
- [ ] Settings > Export opens the share sheet; save the file somewhere (Drive, Files).
- [ ] Settings > Import with that file, in both Merge and Replace modes.
- [ ] Sort menu changes the order and is remembered after a restart.
- [ ] Add an entry with a link such as `.../chapter-45`: Ask first shows the "Use it" prompt, Automatic fills progress; Continue opens the link.
- [ ] Adaptive icon looks right under round and square launcher masks.

## Releasing (GitHub)

1. Bump `version:` in `pubspec.yaml` (for example `1.2.0+3`). The number after `+` must go up every release or Android refuses the update.
2. `flutter build apk --release` (signed with the Faelen key automatically).
3. Publish a release tagged `v<version>` with the APK attached, for example: `gh release create v1.2.0 build/app/outputs/flutter-apk/app-release.apk --title "Faelen 1.2.0" --notes "What changed"`.
4. Phones pick it up from Settings > App updates, or at the next launch (within a day).

The repo must be **public** for the app to read releases without a login.

### Signing key (do not lose it)

- Keystore: `C:/Users/Bryan/.faelen/faelen-release.jks`, passwords and alias in `android/key.properties` (git-ignored). **Back both up somewhere safe** (password manager or cloud drive). If the key is lost, installed phones can never be updated in place; they would have to uninstall first.
- Without `key.properties` the build falls back to the debug key, which will not install over a release-signed app.
- One-time switch: phones that have a build signed with the old debug key must uninstall once before installing 1.1.0 (export a backup from Settings first, then Import after). Every update after that installs in place.

## How to run

```bash
flutter pub get
flutter run -d chrome          # or: flutter run -d web-server --web-port 8080
flutter test
flutter analyze
flutter build apk --release    # output: build/app/outputs/flutter-apk/app-release.apk
```

Windows setup notes: Developer Mode is required for Flutter plugin symlinks. Restart the terminal after PATH changes so `flutter` is recognized.
