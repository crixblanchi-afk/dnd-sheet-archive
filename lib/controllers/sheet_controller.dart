import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../data/character_repository.dart';
import '../models/character.dart';
import '../models/sheet_field.dart';

class SheetController extends ChangeNotifier with WidgetsBindingObserver {
  SheetController({
    required this.repository,
    required this.character,
    this.autosaveDelay = const Duration(milliseconds: 800),
    this.sessionCap = const Duration(minutes: 10),
  }) {
    lockedState = ValueNotifier(character.locked);
    WidgetsBinding.instance.addObserver(this);
  }

  final CharacterRepository repository;
  final Character character;
  final Duration autosaveDelay;
  final Duration sessionCap;
  late final ValueNotifier<bool> lockedState;
  final ValueNotifier<bool> dirtyState = ValueNotifier(false);
  final Map<String, ValueNotifier<bool>> _commentStates = {};

  Timer? _saveTimer;
  Timer? _capTimer;
  Future<void>? _saveInProgress;
  Future<void>? _finishInProgress;
  bool _dirty = false;
  bool _dirtySinceSnapshot = false;
  bool _closed = false;
  int _revision = 0;

  bool get locked => character.locked;
  Object? valueFor(String name) => character.fields[name];
  String? commentFor(String name) => character.comments[name];
  ValueListenable<bool> commentStateFor(String name) =>
      _commentStates.putIfAbsent(
        name,
        () => ValueNotifier(character.comments.containsKey(name)),
      );

  void setText(String name, String value) {
    if (locked) return;
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
    while (_dirty && !_closed) {
      final activeSave = _saveInProgress;
      if (activeSave != null) {
        await activeSave;
        continue;
      }

      final savingRevision = _revision;
      final operation = repository.saveCharacter(character);
      _saveInProgress = operation;
      try {
        await operation;
        if (_revision == savingRevision) {
          _dirty = false;
          dirtyState.value = false;
        }
      } catch (_) {
        _dirty = true;
        if (!_closed) _scheduleSave(const Duration(seconds: 2));
        rethrow;
      } finally {
        if (identical(_saveInProgress, operation)) _saveInProgress = null;
      }
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
    if (_closed) return;
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
