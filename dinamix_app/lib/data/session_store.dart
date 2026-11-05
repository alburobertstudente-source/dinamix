import '../domain/sensor_kind.dart';
import '../domain/session.dart';

/// Persistence of recordings. Implemented on SQLite, in memory in the tests.
abstract class SessionStore {
  /// Marks sessions left open by a crash as interrupted. Returns how many.
  Future<int> recoverInterrupted();

  Future<int> createSession({
    required String name,
    required int startedAtMs,
    required String deviceName,
    required String deviceId,
    required String firmware,
    required DataSource source,
    required String configJson,
  });

  Future<void> insertSamples(int sessionId, List<SensorReading> readings);
  Future<void> addEvent(int sessionId, SessionEvent event);
  Future<void> finishSession(int sessionId,
      {required int endedAtMs, required SessionStatus status, required String configJson});

  Future<List<SessionInfo>> listSessions();
  Future<SessionInfo?> getSession(int sessionId);
  Future<void> renameSession(int sessionId, String name);
  Future<void> deleteSession(int sessionId);
  Future<void> deleteAll();
  Future<List<SessionEvent>> events(int sessionId);
  Future<List<SensorKind>> kindsIn(int sessionId);

  /// Pages samples in insertion order. Pass the last rowId to continue.
  Future<List<StoredSample>> pageSamples(int sessionId,
      {SensorKind? kind, int afterRowId = 0, int limit = 5000});
}

/// Rows contain at most this many channels.
const int maxStoredChannels = 4;
