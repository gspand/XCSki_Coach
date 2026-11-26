import 'dart:math';

import 'package:xc_coach/lala/core/models/analysis_input.dart';
import 'package:xc_coach/lala/core/preprocessing/stage_sorter.dart';

class ValidationIssue {
  const ValidationIssue({required this.message, required this.stageNumbers});

  final String message;
  final List<int> stageNumbers;
}

class ValidationResult {
  const ValidationResult({required this.errors, required this.warnings});

  final List<ValidationIssue> errors;
  final List<ValidationIssue> warnings;
}

class InputValidator {
  const InputValidator({this.sorter = const StageSorter()});

  final StageSorter sorter;

  ValidationResult validate(AnalysisInput input) {
    final errors = <ValidationIssue>[];
    final warnings = <ValidationIssue>[];
    final stages = input.stages;

    if (stages.isEmpty) {
      errors.add(
        const ValidationIssue(
          message: 'Keine Messstufen vorhanden.',
          stageNumbers: <int>[],
        ),
      );
      return ValidationResult(errors: errors, warnings: warnings);
    }

    final validStages = stages
        .where((stage) => stage.isValid)
        .toList(growable: false);

    if (validStages.length < 2) {
      errors.add(
        ValidationIssue(
          message: 'Weniger als zwei gueltige Messpunkte vorhanden.',
          stageNumbers: validStages
              .map((stage) => stage.stageNumber)
              .toList(growable: false),
        ),
      );
    }

    final knownUnits = {'W', 'km/h', 'm/s', 'pace_s_per_km', 'custom'};

    final stageIds = <int>{};
    for (final stage in stages) {
      if (!stageIds.add(stage.stageNumber)) {
        errors.add(
          ValidationIssue(
            message: 'Doppelte Stufennummer erkannt.',
            stageNumbers: <int>[stage.stageNumber],
          ),
        );
      }

      if (stage.loadUnit.trim().isEmpty ||
          !knownUnits.contains(stage.loadUnit)) {
        errors.add(
          ValidationIssue(
            message: 'Ungueltige oder fehlende Belastungseinheit.',
            stageNumbers: <int>[stage.stageNumber],
          ),
        );
      }

      if (!stage.load.isFinite || stage.load < 0) {
        errors.add(
          ValidationIssue(
            message: 'Belastung ist negativ oder nicht endlich.',
            stageNumbers: <int>[stage.stageNumber],
          ),
        );
      }

      if (!stage.lactate.isFinite || stage.lactate < 0) {
        errors.add(
          ValidationIssue(
            message: 'Laktatwert ist negativ oder nicht endlich.',
            stageNumbers: <int>[stage.stageNumber],
          ),
        );
      }

      if (stage.heartRate != null &&
          (stage.heartRate! < 40 || stage.heartRate! > 240)) {
        warnings.add(
          ValidationIssue(
            message: 'Herzfrequenz ausserhalb plausibler Grenzen.',
            stageNumbers: <int>[stage.stageNumber],
          ),
        );
      }

      if (stage.heartRate == null) {
        warnings.add(
          ValidationIssue(
            message: 'Herzfrequenz fehlt fuer mindestens eine Stufe.',
            stageNumbers: <int>[stage.stageNumber],
          ),
        );
      }

      if (stage.durationSeconds <= 0) {
        errors.add(
          ValidationIssue(
            message: 'Stufendauer muss positiv sein.',
            stageNumbers: <int>[stage.stageNumber],
          ),
        );
      }
    }

    final sortedValid = sorter.sortByStageThenTime(validStages);
    for (var i = 1; i < sortedValid.length; i++) {
      final current = sortedValid[i];
      final prev = sortedValid[i - 1];

      if ((current.load - prev.load).abs() < 1e-9) {
        errors.add(
          ValidationIssue(
            message: 'Doppelte Belastungswerte bei gueltigen Stufen erkannt.',
            stageNumbers: <int>[prev.stageNumber, current.stageNumber],
          ),
        );
      }

      final diff = current.load - prev.load;
      if (diff <= 0) {
        errors.add(
          ValidationIssue(
            message: 'Belastung ist nicht monoton steigend.',
            stageNumbers: <int>[prev.stageNumber, current.stageNumber],
          ),
        );
      }

      final lactateDiff = current.lactate - prev.lactate;
      if (lactateDiff < -0.1) {
        warnings.add(
          ValidationIssue(
            message: 'Laktat sinkt trotz steigender Belastung.',
            stageNumbers: <int>[prev.stageNumber, current.stageNumber],
          ),
        );
      }

      if (lactateDiff > 2.0) {
        warnings.add(
          ValidationIssue(
            message: 'Auffaelliger Laktatsprung > 2.0 mmol/l.',
            stageNumbers: <int>[prev.stageNumber, current.stageNumber],
          ),
        );
      }
    }

    final increments = <double>[];
    for (var i = 1; i < sortedValid.length; i++) {
      increments.add(sortedValid[i].load - sortedValid[i - 1].load);
    }
    if (increments.length >= 2) {
      final mean = increments.reduce((a, b) => a + b) / increments.length;
      for (final increment in increments) {
        if ((increment - mean).abs() > max(1.0, mean * 0.35)) {
          warnings.add(
            const ValidationIssue(
              message: 'Ungleichmaessige Belastungssteigerungen erkannt.',
              stageNumbers: <int>[],
            ),
          );
          break;
        }
      }
    }

    if (validStages.where((stage) => stage.lactate >= 4.0).isEmpty) {
      warnings.add(
        const ValidationIssue(
          message: 'Keine Messstufe bei oder oberhalb 4.0 mmol/l vorhanden.',
          stageNumbers: <int>[],
        ),
      );
    }

    return ValidationResult(errors: errors, warnings: warnings);
  }
}
