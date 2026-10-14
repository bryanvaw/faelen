import 'package:flutter/foundation.dart';

import '../models/media_entry.dart';
import '../services/storage_service.dart';

class MediaStore extends ChangeNotifier {
  MediaStore(this._storage);
  final StorageService _storage;

  List<MediaEntry> _items = [];
  bool loading = true;
  String? error;

  String query = '';
  MediaType? typeFilter;
  Status? statusFilter;

  List<MediaEntry> get visible {
    final q = query.trim().toLowerCase();
    return _items
        .where((e) =>
            (typeFilter == null || e.type == typeFilter) &&
            (statusFilter == null || e.status == statusFilter) &&
            (q.isEmpty || e.title.toLowerCase().contains(q)))
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

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

  Future<void> load() async {
    try {
      _items = await _storage.load();
    } catch (e) {
      error = 'Could not load data: $e';
    }
    loading = false;
    notifyListeners();
  }

  /// Adds the entry, or replaces the one with the same id.
  Future<void> save(MediaEntry e) {
    final i = _items.indexWhere((x) => x.id == e.id);
    _items = [..._items];
    i < 0 ? _items.add(e) : _items[i] = e;
    return _persist();
  }

  Future<void> delete(String id) {
    _items = _items.where((x) => x.id != id).toList();
    return _persist();
  }

  Future<void> _persist() async {
    notifyListeners();
    try {
      await _storage.save(_items);
    } catch (e) {
      error = 'Could not save: $e';
      notifyListeners();
    }
  }
}
