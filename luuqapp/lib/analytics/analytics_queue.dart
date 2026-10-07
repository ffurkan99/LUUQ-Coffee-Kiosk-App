import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// What to do with an analytics event after one send attempt.
enum TrackOutcome {
  /// Stored by the server (a resend of a stored event also counts).
  delivered,

  /// The server refused the event itself; sending it again cannot help.
  drop,

  /// No connection, rate limit or an HTTPS problem: try again later.
  keep,

  /// A server error: try again later, but give up after a number of tries.
  keepCounted,
}

/// Classifies a track-event.php answer (status and body).
TrackOutcome classifyTrackResponse(int status, String body) {
  if (status >= 200 && status < 300) return TrackOutcome.delivered;
  if (status == 408 || status == 429) return TrackOutcome.keep;
  if (status >= 500 || (status >= 300 && status < 400)) {
    return TrackOutcome.keepCounted;
  }
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    decoded = null;
  }
  // A 4xx without our JSON came from a proxy/firewall, not from the API.
  if (decoded is! Map) return TrackOutcome.keepCounted;
  if (decoded['reason'] == 'https_required') return TrackOutcome.keep;
  return TrackOutcome.drop;
}

/// An event waiting to be sent. Only the event itself is stored; device id,
/// fingerprint and license key are added at send time and never written here.
class QueuedAnalyticsEvent {
  QueuedAnalyticsEvent({
    required this.id,
    required this.createdAt,
    required this.payload,
    this.attempts = 0,
  });

  /// client_event_id: the server stores an id once, so a resend after a lost
  /// answer is not counted twice.
  final String id;
  final DateTime createdAt;
  final Map<String, dynamic> payload;
  int attempts;

  Map<String, dynamic> toJson() => {
    'id': id,
    'created_at_ms': createdAt.millisecondsSinceEpoch,
    'attempts': attempts,
    'payload': payload,
  };

  static QueuedAnalyticsEvent? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final created = json['created_at_ms'];
    final payload = json['payload'];
    final attempts = json['attempts'];
    if (id is! String || created is! int || payload is! Map) return null;
    return QueuedAnalyticsEvent(
      id: id,
      createdAt: DateTime.fromMillisecondsSinceEpoch(created),
      payload: Map<String, dynamic>.from(payload),
      attempts: attempts is int ? attempts : 0,
    );
  }
}

/// The offline queue: at most [maxEvents] events (the oldest are dropped),
/// none older than [maxAge], kept in one JSON file written atomically.
/// Without a file (tests, storage unavailable) it lives in memory only.
class AnalyticsQueueStore {
  AnalyticsQueueStore({
    required Future<File?> Function() file,
    this.maxEvents = 500,
    this.maxAge = const Duration(days: 7),
    DateTime Function()? now,
  }) : _fileProvider = file,
       _now = now ?? DateTime.now;

  final Future<File?> Function() _fileProvider;
  final int maxEvents;
  final Duration maxAge;
  final DateTime Function() _now;

  final List<QueuedAnalyticsEvent> _events = [];
  Future<void>? _loading;
  File? _file;
  Future<void>? _saving;
  bool _dirty = false;

  List<QueuedAnalyticsEvent> get events => List.unmodifiable(_events);
  bool get isEmpty => _events.isEmpty;

  /// Completes when every change so far is on disk.
  Future<void> get saveIdle async {
    while (_saving != null) {
      await _saving;
    }
  }

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      _file = await _fileProvider();
      final file = _file;
      if (file == null || !await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      final raw = decoded is Map ? decoded['events'] : null;
      if (raw is! List) return;
      // Events queued while this run was loading stay after the saved ones.
      final saved = raw
          .map(QueuedAnalyticsEvent.tryParse)
          .whereType<QueuedAnalyticsEvent>()
          .toList();
      _events.insertAll(0, saved);
      _trim();
    } catch (error) {
      // A corrupt or unreadable file starts an empty queue.
      debugPrint('[ANALYTICS] queue not loaded: $error');
    }
  }

  Future<void> add(QueuedAnalyticsEvent event) async {
    await load();
    _events.add(event);
    _trim();
    _scheduleSave();
  }

  Future<void> remove(String id) async {
    _events.removeWhere((event) => event.id == id);
    _scheduleSave();
  }

  /// Persists a changed attempt count.
  void touch() => _scheduleSave();

  /// Drops events older than [maxAge]; returns how many.
  int dropExpired() {
    final cutoff = _now().subtract(maxAge);
    final before = _events.length;
    _events.removeWhere((event) => event.createdAt.isBefore(cutoff));
    if (_events.length != before) _scheduleSave();
    return before - _events.length;
  }

  void _trim() {
    if (_events.length > maxEvents) {
      _events.removeRange(0, _events.length - maxEvents);
    }
  }

  /// Bursts of changes are written once: one write runs at a time and a
  /// change made meanwhile is written right after it.
  void _scheduleSave() {
    _dirty = true;
    _saving ??= _saveLoop();
  }

  Future<void> _saveLoop() async {
    try {
      while (_dirty) {
        _dirty = false;
        await _writeNow();
      }
    } finally {
      _saving = null;
    }
  }

  Future<void> _writeNow() async {
    final file = _file;
    if (file == null) return;
    try {
      if (_events.isEmpty) {
        if (await file.exists()) await file.delete();
        return;
      }
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({'v': 1, 'events': _events.map((e) => e.toJson()).toList()}),
        flush: true,
      );
      await temp.rename(file.path);
    } catch (error) {
      debugPrint('[ANALYTICS] queue not saved: $error');
    }
  }
}
