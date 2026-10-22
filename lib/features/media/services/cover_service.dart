import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Stores cover images as files in the app's documents folder. Entries only keep the
/// file name, so the app folder can move (for example after an OS update).
/// Unavailable on web, or when the platform folder can't be resolved (such as in tests).
class CoverService {
  CoverService();

  /// Uses [dir] instead of the app documents folder (tests).
  @visibleForTesting
  CoverService.inDirectory(Directory dir) : _dir = dir;

  /// Never touches the platform; covers are simply unavailable (widget tests, where real I/O would hang).
  @visibleForTesting
  CoverService.disabled() : _disabled = true;

  bool _disabled = false;
  Directory? _dir;

  bool get available => _dir != null;

  Future<void> init() async {
    if (kIsWeb || _disabled || _dir != null) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      _dir = await Directory('${docs.path}${Platform.pathSeparator}covers').create(recursive: true);
    } catch (_) {
      _dir = null;
    }
  }

  /// The file for a cover name. Names that point outside the covers folder (from a doctored
  /// backup) are refused, so deleting an entry can never delete some other file.
  File? fileFor(String? name) {
    if (name == null || _dir == null || name.isEmpty || name.contains('/') || name.contains(r'\') || name.contains('..')) return null;
    return File('${_dir!.path}${Platform.pathSeparator}$name');
  }

  /// Deletes cover files that no entry uses: leftovers from a crash during an undo window or
  /// while a picture was being added. Does nothing when [keep] is empty, so a list that failed to
  /// load can never wipe the pictures.
  Future<void> sweep(Set<String> keep) async {
    final dir = _dir;
    if (dir == null || keep.isEmpty) return;
    try {
      await for (final f in dir.list()) {
        if (f is File && !keep.contains(f.uri.pathSegments.last)) await f.delete();
      }
    } catch (_) {
      // Best effort: a leftover file is harmless.
    }
  }

  /// Lets the user pick a photo, downsizes it and saves it. Returns the new file name, or null if cancelled.
  Future<String?> pick(String entryId) async {
    if (!available) return null;
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600, maxHeight: 900, imageQuality: 80);
    if (x == null) return null;
    return saveBytes(entryId, await x.readAsBytes());
  }

  /// A new name each time so a replaced cover never shows a stale cached image.
  Future<String?> saveBytes(String entryId, Uint8List bytes) async {
    if (!available) return null;
    final name = '$entryId-${DateTime.now().microsecondsSinceEpoch}.jpg';
    await fileFor(name)!.writeAsBytes(bytes, flush: true);
    return name;
  }

  Future<Uint8List?> readBytes(String? name) async {
    final f = fileFor(name);
    if (f == null || !await f.exists()) return null;
    return f.readAsBytes();
  }

  Future<void> delete(String? name) async {
    try {
      final f = fileFor(name);
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {
      // Best effort: a leftover file is harmless.
    }
  }
}
