import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../data/character_repository.dart';
import '../models/character.dart';
import '../models/character_edits.dart';
import '../models/sheet_field.dart';

class SheetController extends ChangeNotifier with WidgetsBindingObserver {
  SheetController({
    required this.repository,
    required this.character,
    this.autosaveDelay = const Duration(milliseconds: 800),
    this.sessionCap = const Duration(minutes: 10),
  }) {
    _persisted = character.copy();
    lockedState = ValueNotifier(character.locked);
    _characterSubscription = repository.watchCharacter(character.id).listen(
      (current) {
        if (_closed || _disposed) return;
        if (_saveInProgress != null) {
          _refreshPending = true;
        } else {
          _receivePersisted(current);
        }
      },
      // Un errore nello stream non deve interrompere l'editing locale.
      onError: (Object _) {},
    );
    WidgetsBinding.instance.addObserver(this);
  }

  final CharacterRepository repository;
  final Character character;
  final Duration autosaveDelay;
  final Duration sessionCap;
  late final ValueNotifier<bool> lockedState;
  final ValueNotifier<bool> dirtyState = ValueNotifier(false);
  final Map<String, ValueNotifier<bool>> _commentStates = {};
  late Character _persisted;
  late final StreamSubscription<Character?> _characterSubscription;
  bool _refreshPending = false;
  bool _deleted = false;
  bool _disposed = false;

  Timer? _saveTimer;
  Timer? _capTimer;
  Future<void>? _saveInProgress;
  Future<void>? _finishInProgress;
  bool _dirty = false;
  bool _dirtySinceSnapshot = false;
  bool _closed = false;
  int _revision = 0;

  bool get locked => character.locked || _deleted || _closed || _disposed;
  Object? valueFor(String name) => character.fields[name];
  String? commentFor(String name) => character.comments[name];
  ValueListenable<bool> commentStateFor(String name) =>
      _commentStates.putIfAbsent(
        name,
        () => ValueNotifier(character.comments.containsKey(name)),
      );

  void setText(String name, String value) {
    if (locked) return;
    if (name == 'CharacterName' || name == 'CharacterName 2') {
      character.rename(value);
      _changed();
      notifyListeners();
      return;
    }
    if (value.isEmpty) {
      character.fields.remove(name);
    } else {
      character.fields[name] = value;
    }
    _changed();
  }

  void setCheckbox(String name, SheetCheckboxValue value) {
    if (locked) return;
    switch (value) {
      case SheetCheckboxValue.unchecked:
        character.fields.remove(name);
      case SheetCheckboxValue.proficient:
        character.fields[name] = true;
      case SheetCheckboxValue.expertise:
        character.fields[name] = 'expertise';
    }
    _changed();
  }

  void setComment(String name, String value) {
    if (locked) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      character.comments.remove(name);
    } else {
      character.comments[name] = trimmed;
    }
    final hasComment = character.comments.containsKey(name);
    final state = _commentStates[name];
    if (state != null && state.value != hasComment) state.value = hasComment;
    _changed();
  }

  void _changed() {
    _revision++;
    _dirty = true;
    dirtyState.value = true;
    _dirtySinceSnapshot = true;
    _scheduleSave(autosaveDelay);
    _capTimer ??= Timer(sessionCap, () {
      _capTimer = null;
      unawaited(_finishFromTrigger('session'));
    });
  }

  void _scheduleSave(Duration delay) {
    _saveTimer?.cancel();
    _saveTimer = Timer(delay, () => unawaited(_flushFromTimer()));
  }

  Future<void> _flushFromTimer() async {
    try {
      await flush();
    } catch (_) {
      // flush keeps the document dirty and schedules another attempt.
    }
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    while (_dirty && !_closed && !_disposed) {
      final activeSave = _saveInProgress;
      if (activeSave != null) {
        await activeSave;
        continue;
      }

      final savingRevision = _revision;
      final editing = character.copy();
      final operation = _saveRevision(
        editing,
        _persisted.copy(),
        savingRevision,
      );
      _saveInProgress = operation;
      try {
        await operation;
      } catch (_) {
        if (_refreshPending && !_disposed && !_closed) {
          _refreshPending = false;
          _receivePersisted(await repository.getCharacter(character.id));
          if (_deleted) return;
        }
        _dirty = true;
        if (!_closed && !_disposed) _scheduleSave(const Duration(seconds: 2));
        rethrow;
      } finally {
        if (identical(_saveInProgress, operation)) _saveInProgress = null;
      }
    }
  }

  Future<void> _saveRevision(
    Character editing,
    Character base,
    int revision,
  ) async {
    final saved = await repository.saveCharacterEdits(editing, base);
    if (_disposed || _closed) return;
    // Gli input arrivati durante la scrittura restano da salvare.
    _replaceCharacter(
      applyCharacterEdits(base: editing, edited: character, current: saved),
    );
    _persisted = saved.copy();
    while (_refreshPending && !_disposed && !_closed) {
      _refreshPending = false;
      _receivePersisted(await repository.getCharacter(character.id));
    }
    if (_disposed || _closed) return;
    if (_revision == revision) {
      _dirty = false;
      dirtyState.value = false;
    }
  }

  Future<void> finishEditingSession(String reason) async {
    final activeFinish = _finishInProgress;
    if (activeFinish != null) await activeFinish;
    if (!_dirtySinceSnapshot || _closed) return;

    final operation = _finishEditingSession(reason);
    _finishInProgress = operation;
    try {
      await operation;
    } finally {
      if (identical(_finishInProgress, operation)) _finishInProgress = null;
    }
  }

  Future<void> _finishEditingSession(String reason) async {
    await flush();
    if (_deleted || _disposed) return;
    final snapshotRevision = _revision;
    await repository.createSnapshot(character, reason);
    if (_revision == snapshotRevision) {
      _dirtySinceSnapshot = false;
      _capTimer?.cancel();
      _capTimer = null;
    }
  }

  Future<void> _finishFromTrigger(String reason) async {
    try {
      await finishEditingSession(reason);
    } catch (_) {
      // A later autosave/lifecycle event retries while dirty remains true.
    }
  }

  Future<void> toggleLock() async {
    if (_closed || _deleted || _disposed) return;
    final hadDirtySession = _dirtySinceSnapshot;
    character.locked = !character.locked;
    lockedState.value = character.locked;
    _revision++;
    _dirty = true;
    dirtyState.value = true;
    if (character.locked && hadDirtySession) {
      await finishEditingSession('lock');
    } else {
      await flush();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    if (_dirtySinceSnapshot) {
      await finishEditingSession('session');
    } else {
      await flush();
    }
    _closed = true;
    _saveTimer?.cancel();
    _capTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_characterSubscription.cancel());
  }

  void _receivePersisted(Character? current) {
    if (_disposed || _closed) return;
    if (current == null) {
      _deleted = true;
      _dirty = false;
      _dirtySinceSnapshot = false;
      _saveTimer?.cancel();
      _capTimer?.cancel();
      lockedState.value = true;
      dirtyState.value = false;
      notifyListeners();
      return;
    }
    if (_deleted) return;
    final merged = applyCharacterEdits(
      base: _persisted,
      edited: character,
      current: current,
    );
    _persisted = current.copy();
    _replaceCharacter(merged);
  }

  void _replaceCharacter(Character current) {
    final changed =
        character.name != current.name ||
        character.locked != current.locked ||
        !mapEquals(character.fields, current.fields) ||
        !mapEquals(character.comments, current.comments);
    character.name = current.name;
    character.updatedAt = current.updatedAt;
    character.locked = current.locked;
    character.fields
      ..clear()
      ..addAll(current.fields);
    character.comments
      ..clear()
      ..addAll(current.comments);
    lockedState.value = locked;
    for (final entry in _commentStates.entries) {
      entry.value.value = character.comments.containsKey(entry.key);
    }
    if (changed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_finishFromTrigger('session'));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_characterSubscription.cancel());
    _saveTimer?.cancel();
    _capTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    lockedState.dispose();
    dirtyState.dispose();
    for (final state in _commentStates.values) {
      state.dispose();
    }
    super.dispose();
  }
}
