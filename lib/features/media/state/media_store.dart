import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/media_entry.dart';
import '../services/cover_service.dart';
import '../services/release_schedule.dart';
import '../services/storage_service.dart';

enum MediaSort {
  title('Title (A–Z)'),
  updated('Recently updated'),
  rating('Highest rated'),
  newest('Most unread releases'),
  progress('Most progress'),
  added('Recently added');

  const MediaSort(this.label);
  final String label;

  static MediaSort parse(String? s) => MediaSort.values.firstWhere((e) => e.name == s, orElse: () => MediaSort.title);
}

/// When [e] was created, in microseconds. New ids start with that time in base 36; ids from
/// imports or older data fall back to the last update.
int _addedAt(MediaEntry e) {
  final t = int.tryParse(e.id.split('-').first, radix: 36) ?? 0;
  return t > 1000000000000000 ? t : e.updatedAt * 1000;
}

class MediaStore extends ChangeNotifier {
  MediaStore(this._storage, {CoverService? covers}) : covers = covers ?? CoverService();
  final StorageService _storage;
  final CoverService covers;

  List<MediaEntry> _items = [];
  bool loading = true;
  String? error;

  /// The last failed save, until the screen has shown it (see [takeSaveError]).
  String? _saveError;

  /// A one-off heads-up after loading (skipped or recovered entries). Cleared by [dismissNotice].
  String? notice;

  String query = '';
  MediaType? typeFilter;
  Status? statusFilter;
  MediaSort sort = MediaSort.title;

  // The filtered, sorted list is rebuilt only when something it depends on changes (the list
  // itself, a filter, the query, the sort, or the day, which moves "N new"), not on every repaint.
  Object? _visibleKey;
  List<MediaEntry> _visible = const [];

  List<MediaEntry> get visible {
    final now = DateTime.now();
    final key = (_items, typeFilter, statusFilter, query, sort, now.year * 10000 + now.month * 100 + now.day);
    if (key == _visibleKey) return _visible;

    final q = query.trim().toLowerCase();
    int byTitle(MediaEntry a, MediaEntry b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
    final unread = sort == MediaSort.newest ? {for (final e in _items) e.id: releaseStatus(e, now)?.behind ?? 0} : const <String, int>{};
    final compare = switch (sort) {
      MediaSort.newest => (MediaEntry a, MediaEntry b) {
          final c = unread[b.id]!.compareTo(unread[a.id]!);
          return c != 0 ? c : byTitle(a, b);
        },
      MediaSort.title => byTitle,
      MediaSort.progress => (MediaEntry a, MediaEntry b) {
          final c = b.progress.compareTo(a.progress);
          if (c != 0) return c;
          final d = b.current.compareTo(a.current);
          return d != 0 ? d : byTitle(a, b);
        },
      MediaSort.added => (MediaEntry a, MediaEntry b) {
          final c = _addedAt(b).compareTo(_addedAt(a));
          return c != 0 ? c : byTitle(a, b);
        },
      MediaSort.updated => (MediaEntry a, MediaEntry b) {
          final c = b.updatedAt.compareTo(a.updatedAt);
          return c != 0 ? c : byTitle(a, b);
        },
      MediaSort.rating => (MediaEntry a, MediaEntry b) {
          final c = b.rating.compareTo(a.rating); // unrated (0) ends up last
          return c != 0 ? c : byTitle(a, b);
        },
    };
    _visible = _items
        .where((e) =>
            (typeFilter == null || e.type == typeFilter) &&
            (statusFilter == null || e.status == statusFilter) &&
            (q.isEmpty || e.title.toLowerCase().contains(q)))
        .toList()
      ..sort(compare);
    _visibleKey = key;
    return _visible;
  }

  /// Every entry, unfiltered and unsorted.
  List<MediaEntry> get items => UnmodifiableListView(_items); // a view, not a copy

  int get totalCount => _items.length;

  List<MediaEntry>? _countedItems;
  Map<Status, int> _counts = const {};

  int countWhere(Status s) {
    if (!identical(_countedItems, _items)) {
      _counts = {for (final s in Status.values) s: 0};
      for (final e in _items) {
        _counts[e.status] = _counts[e.status]! + 1;
      }
      _countedItems = _items;
    }
    return _counts[s] ?? 0;
  }

  void setQuery(String v) {
    query = v;
    notifyListeners();
  }

  void setType(MediaType? v) {
    typeFilter = v;
    notifyListeners();
  }

  void setStatus(Status? v) {
    statusFilter = v;
    notifyListeners();
  }

  Future<void> setSort(MediaSort v) async {
    sort = v;
    notifyListeners();
    try {
      await _storage.saveSort(v.name);
    } catch (_) {
      // Not being able to remember the sort order is not worth an error banner.
    }
  }

  Future<void> load() async {
    try {
      _items = await _storage.load();
      if (_storage.recovered) {
        notice = 'Your list could not be read, so the previous saved copy was restored.';
      } else if (_storage.skipped > 0) {
        final n = _storage.skipped;
        notice = '$n ${n == 1 ? 'entry' : 'entries'} could not be read and ${n == 1 ? 'was' : 'were'} skipped.';
      }
      sort = MediaSort.parse(await _storage.loadSort());
      await covers.init();
      // Pictures nobody uses (a crash during an undo window, a half-added entry). Only after a
      // clean read: an entry that could not be read may still own one.
      if (_storage.skipped == 0 && !_storage.recovered) {
        await covers.sweep({for (final e in _items) if (e.cover != null) e.cover!});
      }
    } catch (e) {
      error = 'Could not load data: $e';
    }
    loading = false;
    notifyListeners();
  }

  /// Re-reads the saved list, for changes made while the app was away (a notification button).
  Future<void> refresh() async {
    try {
      await _writing; // never read over a save that is still queued
      final fresh = await _storage.load(reload: true);
      String key(List<MediaEntry> l) => jsonEncode([for (final e in l) e.toJson()]);
      if (key(fresh) == key(_items)) return;
      _items = fresh;
      notifyListeners();
    } catch (_) {
      // Keep what is on screen.
    }
  }

  /// Adds the entry, or replaces the one with the same id. Stamps [MediaEntry.updatedAt].
  Future<void> save(MediaEntry e) {
    final now = DateTime.now();
    final i = _items.indexWhere((x) => x.id == e.id);
    e = settleSchedule(i < 0 ? null : _items[i], e, now).copyWith(updatedAt: now.millisecondsSinceEpoch);
    _items = [..._items];
    i < 0 ? _items.add(e) : _items[i] = e;
    return _persist();
  }

  /// Applies [change] to the newest saved copy of [id] rather than the one on screen, so a button
  /// pressed in a pinned notification a moment ago is built on, not overwritten.
  Future<void> update(String id, MediaEntry Function(MediaEntry current) change) async {
    await _writing; // a queued save of this entry must land before it is read back
    final saved = await _storage.loadOne(id);
    final i = _items.indexWhere((x) => x.id == id);
    if (i < 0) return;
    if (saved != null && jsonEncode(saved.toJson()) != jsonEncode(_items[i].toJson())) {
      _items = [..._items]..[i] = saved;
    }
    return save(change(_items[i]));
  }

  /// The error from the last failed save, once: the screen shows it and it is gone.
  String? takeSaveError() {
    final e = _saveError;
    _saveError = null;
    return e;
  }

  void dismissNotice() {
    notice = null;
    notifyListeners();
  }

  /// Removes the entry but keeps its cover file so [restore] can bring it back. Returns the entry
  /// (null if there was none); call [purgeCover] once the delete is final.
  Future<MediaEntry?> softDelete(String id) async {
    final i = _items.indexWhere((x) => x.id == id);
    if (i < 0) return null;
    final removed = _items[i];
    _items = [..._items]..removeAt(i);
    await _persist();
    return removed;
  }

  /// Puts back an entry removed by [softDelete], unchanged.
  Future<void> restore(MediaEntry e) {
    _items = [..._items, e];
    return _persist();
  }

  Future<void> purgeCover(MediaEntry e) => covers.delete(e.cover);

  Future<void> delete(String id) {
    for (final x in _items.where((x) => x.id == id)) {
      covers.delete(x.cover);
    }
    _items = _items.where((x) => x.id != id).toList();
    return _persist();
  }

  // --- Backup ---------------------------------------------------------------

  /// All entries as JSON maps, with each cover image embedded as base64 under `coverData`.
  Future<List<Map<String, dynamic>>> exportData() async {
    final out = <Map<String, dynamic>>[];
    for (final e in _items) {
      final m = e.toJson();
      final bytes = await covers.readBytes(e.cover);
      if (bytes != null) m['coverData'] = base64Encode(bytes);
      m.remove('cover');
      out.add(m);
    }
    return out;
  }

  /// Imports entries from [exportData] output. With [replace] the current list is discarded;
  /// otherwise entries are merged by id and the more recently updated copy wins.
  /// Returns how many entries were imported. Throws [FormatException] on malformed data.
  Future<int> importData(List<dynamic> data, {required bool replace}) async {
    final incoming = <MediaEntry>[];
    try {
      for (final raw in data) {
        final m = Map<String, dynamic>.from(raw as Map);
        var e = MediaEntry.fromJson(m);
        final cover = m['coverData'];
        if (cover is String) {
          final name = await covers.saveBytes(e.id, base64Decode(cover));
          if (name != null) e = e.copyWith(cover: name);
        }
        incoming.add(e);
      }
    } on TypeError {
      throw const FormatException('Backup entries are malformed');
    }

    final replaced = replace ? _items : const <MediaEntry>[];
    if (replace) {
      _items = incoming;
    } else {
      final byId = {for (final x in _items) x.id: x};
      for (final e in incoming) {
        final old = byId[e.id];
        if (old == null || e.updatedAt >= old.updatedAt) {
          if (old != null && old.cover != e.cover) covers.delete(old.cover);
          byId[e.id] = e;
        } else {
          covers.delete(e.cover); // keeping the existing copy
        }
      }
      _items = byId.values.toList();
    }
    await _persist();
    // The old pictures go only once the new list is safely saved.
    if (_saveError == null) {
      for (final x in replaced) {
        covers.delete(x.cover);
      }
    }
    return incoming.length;
  }

  Future<void> _writing = Future.value();

  /// Writes queue up one after another, so quick taps never run two saves at once.
  Future<void> _persist() {
    notifyListeners();
    return _writing = _writing.then((_) async {
      try {
        await _storage.save(_items); // always the latest list, even if earlier calls are still queued
      } catch (e) {
        _saveError = 'Could not save your changes: $e';
        notifyListeners();
      }
    });
  }
}
