/// Deterministic fingerprints for a LaLa evaluation.
///
/// Purpose: it must be provable, years later, that *these* thresholds were
/// computed from *exactly that* data state. A stored result whose input can no
/// longer be identified is not a scientific record.
///
/// Two fingerprints are kept per calculation run:
///
/// * the **input fingerprint** over the measured data,
/// * the **output fingerprint** over everything LaLa concluded.
///
/// A changed input fingerprint with an unchanged engine version means the test
/// data was edited. An unchanged input fingerprint with a changed output
/// fingerprint means the engine changed — which
/// `docs/LALA_SCIENTIFIC_GUARDRAILS.md` only permits together with a version
/// bump.
///
/// This file lives outside `lib/lala/core/**` on purpose: fingerprinting is a
/// platform concern. The core stays untouched, and the C5 purity test enforces
/// that it never learns about this layer.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:xc_coach/lala/core/models/threshold_result.dart';
import 'package:xc_coach/lala/core/models/training_zone.dart';
import 'package:xc_coach/measurement/contracts/test_session.dart';

abstract final class LalaFingerprint {
  /// Version of the fingerprint construction itself.
  ///
  /// Prefixed to every digest so a future change to *how* we fingerprint can
  /// never be mistaken for a change to *what* was measured.
  static const String algorithmVersion = 'giulia-fingerprint-v1';

  /// Fingerprint of the measured data of one test.
  ///
  /// Deliberately covers **only measurement**, not identity: test id, athlete,
  /// organisation and timestamps are excluded. Two tests with byte-identical
  /// measurements therefore share a fingerprint — which is a feature, because
  /// it exposes accidental duplicate entry.
  ///
  /// Covered: sport, modality, protocol, load unit, stage increment hint and,
  /// per analysable stage, the step number, load, duration, heart rate, RPE,
  /// exclusion state and the lactate value with its puncture site.
  static String ofInput(MeasurementSession data) {
    final payload = <String, Object?>{
      'sport': data.sport,
      'modality': data.modality,
      'protocol': data.protocol,
      'protocolVersion': data.protocolVersion,
      'loadUnit': data.loadUnit,
      'stageIncrementHint': _number(data.stageIncrementHint),
      'stages': <Object?>[
        for (final stage in data.stages)
          <String, Object?>{
            'stageIndex': stage.stageIndex,
            'load': _number(stage.loadValue),
            'durationSeconds': stage.durationSeconds,
            'heartRate': stage.heartRateBpm,
            'rpe': stage.rpe,
            'excluded': stage.excluded,
            'exclusionReason': stage.exclusionReason,
            'lactate': _number(
              data.sampleOfStage(stage.id)?.lactateMmolPerLitre,
            ),
            'sampleSite': data.sampleOfStage(stage.id)?.site.name,
          },
      ],
    };
    return _digest('input', payload);
  }

  /// Fingerprint of everything one run concluded.
  ///
  /// Covers every threshold result of every method and every generated zone
  /// set with its exact boundaries — not only the two standard methods. A
  /// silent change in a secondary method would otherwise stay invisible.
  static String ofOutput({
    required List<ThresholdResult> thresholds,
    required List<GeneratedTrainingZoneSet> zoneSets,
    required String engineVersion,
  }) {
    final payload = <String, Object?>{
      'engineVersion': engineVersion,
      'thresholds': <Object?>[
        for (final result in thresholds)
          <String, Object?>{
            'methodId': result.methodId,
            'algorithmVersion': result.algorithmVersion,
            'thresholdType': result.thresholdType.name,
            'status': result.status.name,
            'load': _number(result.thresholdLoad),
            'lactate': _number(result.interpolatedLactate),
            'heartRate': _number(result.interpolatedHeartRate),
            'usedStages': result.usedStageNumbers,
            'excludedStages': result.excludedStageNumbers,
          },
      ],
      'zoneSets': <Object?>[
        for (final set in zoneSets)
          <String, Object?>{
            'modelId': set.modelId,
            'modelVersion': set.modelVersion,
            'quality': set.quality.name,
            'zones': <Object?>[
              for (final zone in set.zones)
                <String, Object?>{
                  'code': zone.code,
                  'lowerLoadExact': _number(zone.lowerLoadExact),
                  'upperLoadExact': _number(zone.upperLoadExact),
                  'lowerHeartRateExact': _number(zone.lowerHeartRateExact),
                  'upperHeartRateExact': _number(zone.upperHeartRateExact),
                  'provisional': zone.provisionalBoundary,
                },
            ],
          },
      ],
    };
    return _digest('output', payload);
  }

  static String _digest(String scope, Map<String, Object?> payload) {
    final canonical = jsonEncode(<String, Object?>{
      'algorithm': algorithmVersion,
      'scope': scope,
      'payload': _canonical(payload),
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  /// Sorts every map key recursively.
  ///
  /// Without this, a fingerprint would depend on Dart's map insertion order,
  /// which is an implementation detail and not a property of the data.
  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => '$key').toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonical(value[key]),
      };
    }
    if (value is Iterable) {
      return <Object?>[for (final item in value) _canonical(item)];
    }
    return value;
  }

  /// Renders a number in a stable textual form.
  ///
  /// `double.toString()` is the shortest representation that round-trips
  /// exactly, so the fingerprint distinguishes every value the engine can
  /// distinguish — no rounding is introduced here.
  static String? _number(num? value) => value?.toString();
}
