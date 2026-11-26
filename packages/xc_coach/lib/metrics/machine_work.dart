/// Maschinenleistungsmodell: bekannte mechanische Arbeit je Seite und Zug.
///
/// Die Sensoren rechnen das Modell selbst, an jeder Schwungradumdrehung, und
/// schicken je Seite und Zug einen Datensatz (Schema 0x1205). Hier wird nur
/// gezählt — nichts nachgerechnet, nichts geglättet.
///
/// Drei Grössen bleiben getrennt:
///
/// * **bekannte mechanische Arbeit** — was die Freilaufkopplung sieht:
///   Rotation, Verlust (Lager, Luft, Bremse), Rückholseil, Lastverlust;
/// * **unbeobachtete Arbeit** — Seilweg vor dem Einkuppeln und nach dem
///   Auskuppeln. Nicht gemessen, darum `null` und nie 0;
/// * **validierte Gesamtarbeit** — erst, wenn die unbeobachtete Arbeit
///   gemessen ist. Bis dahin `null`.
///
/// Modell V2 (ab Firmware 0.22.35) nimmt den Verlust aus dem gemessenen
/// Bremskennfeld an der je Seite geschätzten Bremsstellung.
///
/// Die Leistung ist integrierte Zugenergie durch Zugzeit, nicht das Mittel
/// eines geglätteten Anzeigesignals.
///
/// Das Buch kennt das Geräteprotokoll nicht: Entschlüsselt wird in
/// `device_platform/machine_work_frames.dart`, nur in Produkten mit Gerät.
library;

/// Ein Datensatz des Maschinenmodells, wie ihn das Buch braucht.
abstract interface class MachineStroke {
  bool get isRight;
  int get sequence;
  int get startTimeUs;
  double get cycleSeconds;
  double get knownJoule;
  double get rotationalAccelerationJoule;
  double get lossJoule;
  double get returnRopeJoule;
  double get loadedExtraJoule;
  double get measuredJoule;
  double get calibratedJoule;
  double get modeledJoule;
  double get extrapolatedJoule;

  /// Verlust gilt als kalibriert (Bremsstellung bestätigt).
  bool get lossTrusted;

  /// Geschätzte Bremsstellung (Marken 1..4), null ohne Schätzung.
  double? get brakePosition;
}

class MachineWorkLedger {
  final List<MachineStroke> _left = [];
  final List<MachineStroke> _right = [];
  final Set<(bool, String, int, int, int)> _seen = {};
  final Map<(bool, String, int), Set<int>> _sequences = {};
  final Map<(bool, String, int), int> _emitted = {};

  List<MachineStroke> get left => List.unmodifiable(_left);
  List<MachineStroke> get right => List.unmodifiable(_right);

  /// Nimmt einen Datensatz auf; doppelt empfangene zählen einmal.
  bool add(
    MachineStroke stroke, {
    String sourceDeviceId = '',
    int streamEpoch = 0,
  }) {
    if (!_seen.add((
      stroke.isRight,
      sourceDeviceId,
      streamEpoch,
      stroke.sequence,
      stroke.startTimeUs,
    ))) {
      return false;
    }
    (stroke.isRight ? _right : _left).add(stroke);
    (_sequences[(stroke.isRight, sourceDeviceId, streamEpoch)] ??= {}).add(
      stroke.sequence,
    );
    return true;
  }

  /// Der Sensor meldet die Nummer seines zuletzt erzeugten Zugs
  /// (Pipeline-Status). Damit wird auch ein verlorener letzter Zug sichtbar.
  void noteEmitted({
    required bool isRight,
    required int lastSequence,
    String sourceDeviceId = '',
    int streamEpoch = 0,
  }) {
    final key = (isRight, sourceDeviceId, streamEpoch);
    final previous = _emitted[key];
    if (previous == null || lastSequence > previous) {
      _emitted[key] = lastSequence;
    }
  }

  /// Züge, die der Sensor nummeriert hat, die aber nie ankamen: Lücken in der
  /// Folge zwischen erstem und letztem empfangenen Zug, dazu fehlende am Ende,
  /// wenn der Sensor eine höhere Nummer gemeldet hat. Sie werden gezählt,
  /// nicht ergänzt — ihre Arbeit fehlt in allen Summen.
  int get missingLeft => _missingSide(false);
  int get missingRight => _missingSide(true);

  int _missingSide(bool right) {
    var missing = 0;
    for (final entry in _sequences.entries) {
      if (entry.key.$1 == right) {
        missing += _missing(entry.value, _emitted[entry.key]);
      }
    }
    return missing;
  }

  static int _missing(Set<int> sequences, int? emitted) {
    if (sequences.isEmpty) return 0;
    var low = sequences.first, high = low;
    for (final s in sequences) {
      if (s < low) low = s;
      if (s > high) high = s;
    }
    final inner = high - low + 1 - sequences.length;
    final tail = emitted != null && emitted > high ? emitted - high : 0;
    return inner + tail;
  }

  bool get isEmpty => _left.isEmpty && _right.isEmpty;

  int get strokes =>
      _left.length > _right.length ? _left.length : _right.length;

  double _sum(double Function(MachineStroke) of) {
    var total = 0.0;
    for (final s in _left) {
      total += of(s);
    }
    for (final s in _right) {
      total += of(s);
    }
    return total;
  }

  double get knownJoule => _sum((s) => s.knownJoule);
  double get rotationalAccelerationJoule =>
      _sum((s) => s.rotationalAccelerationJoule);
  double get lossJoule => _sum((s) => s.lossJoule);
  double get returnRopeJoule => _sum((s) => s.returnRopeJoule);
  double get loadedExtraJoule => _sum((s) => s.loadedExtraJoule);
  double get measuredJoule => _sum((s) => s.measuredJoule);
  double get calibratedJoule => _sum((s) => s.calibratedJoule);
  double get modeledJoule => _sum((s) => s.modeledJoule);
  double get extrapolatedJoule => _sum((s) => s.extrapolatedJoule);

  /// Zuletzt bestätigte Bremsstellung der Seite, null ohne.
  double? brakePosition({required bool isRight}) {
    final side = isRight ? _right : _left;
    for (var i = side.length - 1; i >= 0; --i) {
      final s = side[i];
      if (s.lossTrusted && s.brakePosition != null) return s.brakePosition;
    }
    return null;
  }

  /// Nicht beobachtet: unbekannt, nicht null.
  double? get unobservedJoule => null;

  /// Erst mit gemessener unbeobachteter Arbeit.
  double? get validatedJoule => null;

  /// Zugzeit: die Zyklen der Seite mit den meisten Zügen (beide Seiten ziehen
  /// im Doppelstock gleichzeitig; so zählt keine Zeit doppelt).
  double get cycleSeconds {
    final side = _left.length >= _right.length ? _left : _right;
    var total = 0.0;
    for (final s in side) {
      total += s.cycleSeconds;
    }
    return total;
  }

  /// Bekannte mechanische Leistung beider Seiten, null ohne Zugzeit.
  double? get knownPowerWatt {
    final seconds = cycleSeconds;
    return seconds > 0 ? knownJoule / seconds : null;
  }

  /// Anteil der bekannten Arbeit aus gemessenen oder kalibrierten Grössen.
  double? get measuredShare {
    final known = knownJoule;
    return known > 0 ? (measuredJoule + calibratedJoule) / known : null;
  }

  /// Bekannte Arbeit des letzten Doppelstocks (links + rechts), null ohne Zug.
  double? get lastCycleKnownJoule {
    final l = _left.isEmpty ? null : _left.last.knownJoule;
    final r = _right.isEmpty ? null : _right.last.knownJoule;
    if (l == null && r == null) return null;
    return (l ?? 0) + (r ?? 0);
  }
}
