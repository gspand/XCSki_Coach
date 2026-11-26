/// Dauerhafte Identität importierter Rohmessungen.
///
/// Ein Scout-Speicher wird nicht leer, nur weil GIULIA ihn gelesen hat. Ein
/// zweiter Tipp auf «Importieren» liefert deshalb dieselben Records noch
/// einmal. Diese Tabelle trennt «vom Gerät erneut geliefert» von «in diesem
/// Bestand noch neu», ohne Rohwerte zu verändern oder den Scout zu löschen.
library;

import '../database/giulia_database.dart';
import 'normalization/external_data.dart';

class ExternalImportRegistry {
  const ExternalImportRegistry(this.database);

  final GiuliaDatabase database;

  /// Nur Werte, die in diesem Archiv noch nicht in einem Test stehen.
  List<ExternalMeasurement> unimported(
    Iterable<ExternalMeasurement> measurements,
  ) {
    final unique = _unique(measurements);
    if (unique.isEmpty) return const [];
    final existing = <String>{};
    for (final measurement in unique) {
      final rows = database.raw.select(
        '''SELECT 1 FROM external_measurement_import
            WHERE provider_id = ? AND source_id = ? LIMIT 1''',
        [measurement.provider.id, measurement.sourceId],
      );
      if (rows.isNotEmpty) existing.add(_key(measurement));
    }
    return [
      for (final measurement in unique)
        if (!existing.contains(_key(measurement))) measurement,
    ];
  }

  int importedCount(Iterable<ExternalMeasurement> measurements) {
    final unique = _unique(measurements);
    return unique.length - unimported(unique).length;
  }

  /// Verknüpft die externen Identitäten mit dem angelegten Test.
  ///
  /// Der Primärschlüssel ist die letzte Verteidigung gegen einen Doppelimport.
  /// [ImportWriter] ruft dies in derselben Datenbanktransaktion wie den Test
  /// auf, sodass weder eine verwaiste Reservierung noch ein halber Test bleibt.
  void recordAll(
    Iterable<ExternalMeasurement> measurements, {
    required String organizationId,
    required String athleteId,
    required String testId,
    required int importedAtUtcUs,
  }) {
    for (final measurement in _unique(measurements)) {
      database.raw.execute(
        '''INSERT INTO external_measurement_import(
             provider_id, source_id, organization_id, athlete_id, test_id,
             raw_payload_hex, imported_at_utc_us, measured_at_utc_us,
             sequence_number, heart_rate_bpm, temperature_c)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          measurement.provider.id,
          measurement.sourceId,
          organizationId,
          athleteId,
          testId,
          measurement.rawPayloadHex,
          importedAtUtcUs,
          measurement.measuredAtUtcUs,
          measurement.sequenceNumber,
          measurement.heartRateBpm,
          measurement.temperatureCelsius,
        ],
      );
    }
  }

  static List<ExternalMeasurement> _unique(
    Iterable<ExternalMeasurement> measurements,
  ) {
    final byIdentity = <String, ExternalMeasurement>{};
    for (final measurement in measurements) {
      byIdentity.putIfAbsent(_key(measurement), () => measurement);
    }
    return byIdentity.values.toList(growable: false);
  }

  static String _key(ExternalMeasurement measurement) =>
      '${measurement.provider.id}\u0000${measurement.sourceId}';
}
