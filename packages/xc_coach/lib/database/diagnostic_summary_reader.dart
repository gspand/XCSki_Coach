/// Veröffentlichte Diagnostikergebnisse lesen — ohne LaLa.
///
/// Gelesen werden **gespeicherte Ergebnisse**, nicht der wissenschaftliche
/// Kern aufgerufen. Das ist dieselbe Grenze wie bei den Trainingsvorgaben
/// ([training_basis_reader.dart](training_basis_reader.dart)): Wer ein
/// Ergebnis anzeigt, braucht die Auswertung nicht.
library;

import '../app/diagnostic_summary.dart';
import '../domain/diagnostic_catalogue.dart';
import '../domain/diagnostics.dart';
import 'giulia_database.dart';

class DiagnosticSummaryReader {
  const DiagnosticSummaryReader(this.database);

  final GiuliaDatabase database;

  /// Die ausgewerteten Tests eines Athleten, neueste zuerst.
  List<DiagnosticSummary> summariesOf(String athleteId, {int limit = 10}) {
    final tests = database.raw.select(
      '''SELECT id, started_at_utc_us, sport, protocol, measurement_source
           FROM xc_performance_test
          WHERE athlete_id = ?
          ORDER BY started_at_utc_us DESC
          LIMIT ?''',
      [athleteId, limit],
    );

    return [
      for (final test in tests)
        DiagnosticSummary(
          testId: test['id'] as String,
          startedAtUtcUs: test['started_at_utc_us'] as int,
          sport: (test['sport'] as String?) ?? 'generic',
          diagnosticSport: DiagnosticSport.classify(
            sport: test['sport'] as String?,
            protocol: test['protocol'] as String?,
            measurementSource: _source(test['measurement_source'] as String?),
          ),
          thresholds: _thresholdsOf(test['id'] as String),
        ),
    ];
  }

  static MeasurementSource? _source(String? name) {
    for (final source in MeasurementSource.values) {
      if (source.name == name) return source;
    }
    return null;
  }

  /// Das jüngste Ergebnis mit Schwellen, oder null.
  DiagnosticSummary? latestOf(String athleteId) {
    for (final summary in summariesOf(athleteId)) {
      if (summary.hasResult) return summary;
    }
    return null;
  }

  List<ThresholdSummary> _thresholdsOf(String testId) {
    // Nur die vom Verfahren als Standard gewählte Bestimmung: Alle Methoden
    // nebeneinander zu zeigen ist Diagnostik, nicht Anzeige.
    final rows = database.raw.select(
      '''SELECT threshold_type, load_value, power_w, load_unit,
                heart_rate_bpm, lactate_mmol_l
           FROM xc_threshold_result
          WHERE test_id = ? AND is_selected_standard = 1
          ORDER BY threshold_type''',
      [testId],
    );

    final out = <ThresholdSummary>[];
    for (final row in rows) {
      final load =
          (row['load_value'] as double?) ?? (row['power_w'] as double?);
      if (load == null) continue;
      out.add(
        ThresholdSummary(
          type: (row['threshold_type'] as String) == 'lt1'
              ? SummaryThreshold.lt1
              : SummaryThreshold.lt2,
          loadValue: load,
          loadUnit: (row['load_unit'] as String?) ?? 'W',
          heartRateBpm: row['heart_rate_bpm'] as int?,
          lactateMmolPerLitre: row['lactate_mmol_l'] as double?,
        ),
      );
    }
    return out;
  }
}
