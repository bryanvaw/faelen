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

  /// A one-off heads-up after loading (skipped or recovered entries). Cleared by [dismissNotice].
  String? notice;

  String query = '';
  MediaType? typeFilter;
  Status? statusFilter;
  MediaSort sort = MediaSort.title;

  List<MediaEntry> get visible {
    final q = query.trim().toLowerCase();
    int byTitle(MediaEntry a, MediaEntry b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
    final now = DateTime.now();
    int unread(MediaEntry e) => releaseStatus(e, now)?.behind ?? 0;
    final compare = switch (sort) {
      MediaSort.newest => (MediaEntry a, MediaEntry b) {
          final c = unread(b).compareTo(unread(a));
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
    return _items
        .where((e) =>
            (typeFilter == null || e.type == typeFilter) &&
            (statusFilter == null || e.status == statusFilter) &&
            (q.isEmpty || e.title.toLowerCase().contains(q)))
        .toList()
      ..sort(compare);
  }

  /// Every entry, unfiltered and unsorted.
  List<MediaEntry> get items => List.unmodifiable(_items);

  int get totalCount => _items.length;
  int countWhere(Status s) => _items.where((e) => e.status == s).length;

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
    } catch (e) {
      error = 'Could not load data: $e';
    }
    loading = false;
    notifyListeners();
  }

  /// Adds the entry, or replaces the one with the same id. Stamps [MediaEntry.updatedAt].
  Future<void> save(MediaEntry e) {
    e = e.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch);
    final i = _items.indexWhere((x) => x.id == e.id);
    _items = [..._items];
    i < 0 ? _items.add(e) : _items[i] = e;
    return _persist();
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

    if (replace) {
      for (final x in _items) {
        covers.delete(x.cover);
      }
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
        error = 'Could not save: $e';
        notifyListeners();
      }
    });
  }
}
