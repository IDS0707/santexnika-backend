import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'seed.dart';

class DataStore {
  DataStore({String? dataDir})
    : _file = File(p.join(dataDir ?? _defaultDir(), 'store.json'));

  static String _defaultDir() {
    final env = Platform.environment['DATA_DIR'];
    if (env != null && env.trim().isNotEmpty) return env;
    return p.join(Directory.current.path, 'data');
  }

  final File _file;
  final _lock = _Mutex();

  late Map<String, dynamic> _state;

  Future<void> initialize() async {
    await _file.parent.create(recursive: true);
    if (!await _file.exists()) {
      _state = buildSeed();
      await _flush();
      return;
    }
    try {
      final raw = await _file.readAsString();
      _state = (jsonDecode(raw) as Map<String, dynamic>);
      _ensureKeys();
    } catch (_) {
      _state = buildSeed();
      await _flush();
    }
  }

  void _ensureKeys() {
    for (final k in [
      'categories',
      'products',
      'orders',
      'drivers',
      'applications',
      'admin_credentials',
    ]) {
      _state.putIfAbsent(k, () => buildSeed()[k]);
    }
  }

  Future<T> read<T>(FutureOr<T> Function(Map<String, dynamic> s) fn) async {
    return _lock.run(() async => await fn(_state));
  }

  Future<T> write<T>(FutureOr<T> Function(Map<String, dynamic> s) fn) async {
    return _lock.run(() async {
      final result = await fn(_state);
      await _flush();
      return result;
    });
  }

  Future<void> _flush() async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_state));
    if (await _file.exists()) await _file.delete();
    await tmp.rename(_file.path);
  }
}

class _Mutex {
  Future<void> _last = Future.value();

  Future<T> run<T>(FutureOr<T> Function() fn) {
    final completer = Completer<T>();
    final prev = _last;
    _last = completer.future.catchError((_) => null as T);
    prev.then((_) async {
      try {
        completer.complete(await fn());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}
