/// Aus dem geprüften Vorschlag wird ein Test — über die vorhandenen Wege.
///
/// ## Warum hier so wenig steht
///
/// Weil nichts Neues nötig ist. Ein importierter Stufentest ist derselbe
/// Stufentest wie ein von Hand eingetragener: dieselbe `performance_test`,
/// dieselben `test_stage`, dieselben Laktatproben, dieselbe Auswertung. Der
/// Unterschied steht in **einem** Feld — [MeasurementSource] — und in der
/// Provenienz.
///
/// Was das an Aufwand spart, ist nebensächlich. Was es an Vergleichbarkeit
/// rettet, ist es nicht: Ein Testbestand, in dem importierte und eingetippte
/// Tests zwei verschiedene Formen haben, lässt sich nicht mehr gemeinsam
/// auswerten, und genau das ist der Zweck des Bestandes.
///
/// ## Wie eine Korrektur gespeichert wird
///
/// ```text
///   lactate_sample                8,7   ← was das Gerät geliefert hat
///   diagnostic_stage_correction   6,7   ← was ein Mensch gelten lässt, mit Grund
///   loadTestData()                6,7   ← COALESCE(korrigiert, original)
/// ```
///
/// Der gelieferte Wert wird nie überschrieben. Das ist kein Zusatz dieses
/// Moduls — es ist der Weg, den
/// [correctStageData](../database/diagnostics_repository.dart) seit jeher geht.
library;

import '../database/diagnostics_repository.dart';
import '../domain/diagnostics.dart';
import '../measurement/contracts/measurement_sample.dart';
import '../measurement/contracts/test_stage.dart';
import '../observation/observation.dart';
import '../observation/observation_repository.dart';
import 'external_import_registry.dart';
import 'normalization/external_data.dart';
import 'normalization/import_review.dart';

/// Was beim Anlegen entstanden ist.
class ImportedTest {
  const ImportedTest({
    required this.testId,
    required this.stagesWritten,
    required this.correctionsWritten,
    required this.separateObservations,
  });

  final String testId;
  final int stagesWritten;

  /// Wie viele Stufen einen korrigierten Wert tragen. Der gelieferte steht
  /// daneben.
  final int correctionsWritten;

  /// Ruhe-, Aufwärm- und Erholungswerte, die zu keiner Stufe gehörten.
  final int separateObservations;
}

/// Legt aus einem geprüften Vorschlag einen Test an.
class ImportWriter {
  const ImportWriter({required this.diagnostics, required this.observations});

  final DiagnosticsRepository diagnostics;
  final ObservationRepository observations;

  /// Schreibt den Test.
  ///
  /// [idOf] erzeugt die Kennungen — eingespeist, damit ein Test denselben
  /// Import zweimal mit denselben Kennungen fahren und Zeichen für Zeichen
  /// vergleichen kann.
  ImportedTest write(
    ImportReview review, {
    required String organizationId,
    required String athleteId,
    required String actorUserId,
    required int nowUtcUs,
    required String Function(String kind, int ordinal) idOf,
  }) {
    return diagnostics.database.transaction(() {
      if (review.activity?.eligibleForCoach == false ||
          _measurementsOf(review).any((m) => m.provider.isStrava)) {
        throw const DiagnosticsDataException('Die Datenquelle ist für XC Ski Coach gesperrt.');
      }
      _validate(review);
      if (!review.mayBeEvaluated) {
        throw const DiagnosticsDataException(
          'Unter drei auswertbaren Stufen entsteht kein Test.',
        );
      }

      final measurements = _measurementsOf(review);
      final registry = ExternalImportRegistry(diagnostics.database);
      final alreadyImported = registry.importedCount(measurements);
      if (alreadyImported != 0) {
        throw DiagnosticsDataException(
          alreadyImported == 1
              ? 'Dieser Messwert wurde bereits importiert.'
              : '$alreadyImported Messwerte wurden bereits importiert.',
        );
      }

      final testId = idOf('test', 0);
      final activity = review.activity;
      final started =
          review.stages.first.measurement?.measuredAtUtcUs ??
          activity?.startedAtUtcUs ??
          nowUtcUs;

      diagnostics.createTest(
        id: testId,
        organizationId: organizationId,
        athleteId: athleteId,
        sport: review.protocol.sport,
        modality: review.protocol.sport,
        protocol: review.protocol.id,
        protocolVersion: review.protocol.version,
        loadUnit: review.protocol.loadUnit,
        // Wo eine fremde Aktivität die Belastung geliefert hat, hat ein Gerät
        // gemessen — nur eben nicht unseres. Wo nur der Scout da war, steht die
        // nominelle Belastung des Protokolls, und das ist ein Import.
        measurementSource: activity == null
            ? MeasurementSource.imported
            : MeasurementSource.externalDevice,
        startedAtUtcUs: started,
        createdByUserId: actorUserId,
        stageIncrementHint: review.protocol.increment,
        notes: _provenance(review),
      );

      var stagesWritten = 0;
      var correctionsWritten = 0;

      for (final stage in review.stages) {
        final measurement = stage.measurement;
        final stageId = idOf('stage', stage.stageNumber);

        diagnostics.addStage(
          testId: testId,
          nowUtcUs: nowUtcUs,
          stage: PersistedTestStage(
            id: stageId,
            stageIndex: stage.stageNumber,
            loadValue:
                stage.loadValue ??
                review.protocol.loadOfStage(stage.stageNumber),
            durationSeconds: review.protocol.stageDurationSeconds,
            heartRateBpm: stage.heartRateBpm,
            rpe: stage.rpe,
            targetValue: review.protocol.loadOfStage(stage.stageNumber),
            excluded: !stage.countsForAnalysis,
            exclusionReason: stage.countsForAnalysis
                ? null
                : _reasonText(stage),
          ),
        );
        stagesWritten++;

        if (measurement == null) continue;

        // Immer der **gelieferte** Wert. Was ein Mensch stattdessen gelten
        // lässt, kommt gleich darunter als eigene Zeile.
        diagnostics.addLactateSample(
          testId: testId,
          nowUtcUs: nowUtcUs,
          source: ObservationSource.device,
          sample: PersistedLactateSample(
            id: idOf('sample', stage.stageNumber),
            stageId: stageId,
            lactateMmolPerLitre: measurement.value,
            sampledAtUtcUs: measurement.measuredAtUtcUs,
            context: LactateSampleContext.stage,
            site: review.sampleSite,
            enteredByUserId: actorUserId,
            note:
                'Übertragen von ${measurement.provider.id}, '
                'Speicherplatz ${measurement.sourceId}.',
          ),
        );

        if (stage.isCorrected) {
          diagnostics.correctStageData(
            id: idOf('correction', stage.stageNumber),
            stageId: stageId,
            actorUserId: actorUserId,
            reason: _reasonText(stage),
            correctedAtUtcUs: nowUtcUs,
            lactateMmolPerLitre: stage.correctedValue,
          );
          correctionsWritten++;
        }
      }

      // Ruhe, Aufwärmen, Erholung: gültige Beobachtungen ohne Stufe. Sie hängen
      // am Test, nicht an einer seiner Stufen.
      for (final (index, measurement) in review.separate.indexed) {
        observations.record(
          Observation(
            id: idOf('observation', index),
            athleteId: athleteId,
            observedAtUtcUs: measurement.measuredAtUtcUs,
            type: measurement.type,
            context: ObservationContext(testId: testId),
            value: measurement.value,
            unit: measurement.unit,
            source: ObservationSource.device,
            recordedByUserId: actorUserId,
            occasion: _occasionOf(measurement, review),
            sampleSite: review.sampleSite.name,
          ),
        );
      }

      final endedAtUtcUs = measurements.fold<int>(
        started,
        (latest, measurement) => measurement.measuredAtUtcUs > latest
            ? measurement.measuredAtUtcUs
            : latest,
      );
      diagnostics.completeTest(testId: testId, endedAtUtcUs: endedAtUtcUs);
      registry.recordAll(
        measurements,
        organizationId: organizationId,
        athleteId: athleteId,
        testId: testId,
        importedAtUtcUs: nowUtcUs,
      );

      return ImportedTest(
        testId: testId,
        stagesWritten: stagesWritten,
        correctionsWritten: correctionsWritten,
        separateObservations: review.separate.length,
      );
    });
  }

  List<ExternalMeasurement> _measurementsOf(ImportReview review) => [
    for (final stage in review.stages)
      if (stage.measurement != null) stage.measurement!,
    ...review.separate,
  ];

  void _validate(ImportReview review) {
    if (review.protocol.id.trim().isEmpty ||
        review.protocol.version.trim().isEmpty ||
        review.protocol.stageDurationSeconds <= 0 ||
        !review.protocol.startLoad.isFinite ||
        !review.protocol.increment.isFinite ||
        review.protocol.increment <= 0) {
      throw const DiagnosticsDataException(
        'Das Testprotokoll enthält ungültige oder unversionierte Angaben.',
      );
    }

    final stageNumbers = <int>{};
    for (final stage in review.stages) {
      if (stage.stageNumber <= 0 || !stageNumbers.add(stage.stageNumber)) {
        throw const DiagnosticsDataException(
          'Stufennummern müssen positiv und eindeutig sein.',
        );
      }
      final load = stage.loadValue;
      if (load != null && (!load.isFinite || load <= 0)) {
        throw DiagnosticsDataException(
          'Stufe ${stage.stageNumber} enthält keine gültige Belastung.',
        );
      }
      final heartRate = stage.heartRateBpm;
      if (heartRate != null && (heartRate < 20 || heartRate > 250)) {
        throw DiagnosticsDataException(
          'Stufe ${stage.stageNumber} enthält eine ungültige Herzfrequenz.',
        );
      }
      final rpe = stage.rpe;
      if (rpe != null && (rpe < 0 || rpe > 10)) {
        throw DiagnosticsDataException(
          'Stufe ${stage.stageNumber} enthält einen ungültigen RPE-Wert.',
        );
      }
      if (stage.decision != ReviewDecision.accept && stage.reason == null) {
        throw DiagnosticsDataException(
          'Stufe ${stage.stageNumber}: Korrektur oder Ausschluss braucht '
          'einen Grund.',
        );
      }
      final corrected = stage.correctedValue;
      if (stage.decision == ReviewDecision.correct &&
          (corrected == null ||
              !corrected.isFinite ||
              corrected < 0.1 ||
              corrected > 40)) {
        throw DiagnosticsDataException(
          'Stufe ${stage.stageNumber} enthält keinen gültigen Korrekturwert.',
        );
      }
    }

    final identities = <String>{};
    for (final measurement in _measurementsOf(review)) {
      final identity =
          '${measurement.provider.id}\u0000${measurement.sourceId}';
      if (measurement.provider.id.trim().isEmpty ||
          measurement.sourceId.trim().isEmpty ||
          !identities.add(identity) ||
          measurement.measuredAtUtcUs <= 0 ||
          !measurement.value.isFinite ||
          (measurement.type == ObservationType.lactate &&
              (measurement.unit != 'mmol/l' ||
                  measurement.value < 0.1 ||
                  measurement.value > 40))) {
        throw const DiagnosticsDataException(
          'Der Import enthält ungültige oder doppelte Rohmessungen.',
        );
      }
    }

    final activity = review.activity;
    if (activity != null) {
      if (activity.startedAtUtcUs <= 0 ||
          activity.endedAtUtcUs < activity.startedAtUtcUs) {
        throw const DiagnosticsDataException(
          'Die importierte Aktivität hat einen ungültigen Zeitraum.',
        );
      }
      var previous = activity.startedAtUtcUs - 1;
      for (final sample in activity.samples) {
        if (sample.atUtcUs < previous ||
            sample.atUtcUs < activity.startedAtUtcUs ||
            sample.atUtcUs > activity.endedAtUtcUs ||
            !sample.loadValue.isFinite) {
          throw const DiagnosticsDataException(
            'Der Belastungsverlauf ist nicht gültig oder nicht sortiert.',
          );
        }
        previous = sample.atUtcUs;
      }
    }
  }

  /// Wo ein Wert lag, wo keine Stufe war.
  ///
  /// Vor der ersten Stufe ist es Ruhe oder Aufwärmen, danach Erholung. Ohne
  /// eine erste Stufe lässt sich das nicht sagen — dann heisst es
  /// «Stichprobe», und nicht etwas Genaueres, das nicht bekannt ist.
  String _occasionOf(ExternalMeasurement measurement, ImportReview review) {
    final first = review.stages.first.measurement?.measuredAtUtcUs;
    final last = review.stages.last.measurement?.measuredAtUtcUs;
    if (first == null || last == null) return LactateSampleContext.spot.name;
    if (measurement.measuredAtUtcUs < first) {
      return LactateSampleContext.rest.name;
    }
    if (measurement.measuredAtUtcUs > last) {
      return LactateSampleContext.recovery.name;
    }
    return LactateSampleContext.spot.name;
  }

  String _reasonText(ReviewedStage stage) {
    final reason = stage.reason?.label ?? 'Ohne Angabe';
    final note = stage.note;
    return note == null || note.isEmpty ? reason : '$reason — $note';
  }

  /// Was der Test über seine eigene Herkunft festhält.
  String _provenance(ImportReview review) {
    final parts = <String>[
      'Importiert aus '
          '${review.stages.first.measurement?.provider.id ?? 'externer Quelle'}.',
      if (review.activity != null)
        'Belastung und Herzfrequenz aus '
            '${review.activity!.provider.id}, Aktivität '
            '${review.activity!.sourceId}.'
      else
        'Belastung nominell aus dem Protokoll — keine gemessene Aktivität.',
      if (review.activity?.fitFileOrigin case final origin?) 'Direkte FIT-Quelle: ${origin.name}.',
      if (review.clockOffset != Duration.zero)
        'Uhrenversatz ${review.clockOffset.inSeconds} s berücksichtigt.',
    ];
    return parts.join(' ');
  }
}
