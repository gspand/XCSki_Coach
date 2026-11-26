/// Die Bibliothek sagt, was erlaubt ist. Das Dosismodell sagt, was heute
/// davon zulässig ist. Nicht umgekehrt.
///
/// ## Der Fall, aus dem diese Datei entstand
///
/// Am 05.10.2026 ergab die plausible Ercolina-Dosis dreissig Minuten, und
/// verschrieben wurden fünfundvierzig. Grund war eine Ausnahme — «die
/// kleinste angebotene Form eines Reizes bleibt erreichbar» —, die die
/// Obergrenze überschrieb. Damit war sie keine Obergrenze.
///
/// Die Ausnahme ist weg. Gibt es für einen Reiz keine Einheit innerhalb der
/// Dosis, ist der Kandidat heute unzulässig — und das ist eine Aussage über
/// den Katalog, nicht über den Athleten.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/domain/xc_modality.dart';
import 'package:xc_coach/intelligence/load/stimulus_models.dart';
import 'package:xc_coach/intelligence/training_need/need_types.dart';
import 'package:xc_coach/intelligence/workout_selection/modality_dose.dart';
import 'package:xc_coach/intelligence/workout_selection/workout_family.dart';
import 'package:xc_coach/intelligence/workout_selection/workout_prescription.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/diagnostics_state.dart';
import 'package:xc_coach/workout_engine/ercolina_canonical_library.dart';

/// Eine Familie mit genau den angegebenen Stufen.
WorkoutFamily familyWith(List<int> minutes) => WorkoutFamily(
  id: 'fam_test',
  name: 'Testfamilie',
  type: WorkoutFamilyType.easyBase,
  modality: XcModality.cycling,
  primaryStimulus: StimulusType.aerobicBase,
  primaryNeed: TrainingNeedType.aerobicBase,
  minDurationMinutes: minutes.reduce((a, b) => a < b ? a : b),
  maxDurationMinutes: minutes.reduce((a, b) => a > b ? a : b),
  recoveryCost: RecoveryCost.low,
  affectedSystems: const {TrainedSystem.systemic},
  description: 'Nur fuer den Test.',
  allowedVariants: [
    for (final m in minutes)
      WorkoutVariant(
        id: '${m}m',
        name: 'Variante $m min',
        totalDurationMinutes: m,
        warmupMinutes: 0,
        workMinutes: m,
        cooldownMinutes: 0,
        structureDescription: '$m min',
      ),
  ],
);

int prescribedMinutes({
  required List<int> variants,
  required int available,
  int? dose,
}) => familyWith(variants)
    .buildPrescription(
      availableMinutes: available,
      doseCeilingMinutes: dose,
      diagnostics: const DiagnosticsState(),
    )
    .totalDurationMinutes;

void main() {
  group('Dosis begrenzt die Variantenwahl', () {
    test('1. Dosis 30, Stufen 30/45/60 → 30', () {
      expect(
        prescribedMinutes(variants: [30, 45, 60], available: 240, dose: 30),
        30,
      );
    });

    test('2. Dosis 40, Stufen 30/45/60 → 30', () {
      // Nicht 45: Die naechste Stufe liegt ueber der Dosis, und es wird
      // nichts dazwischen erfunden.
      expect(
        prescribedMinutes(variants: [30, 45, 60], available: 240, dose: 40),
        30,
      );
    });

    test('3. Dosis 45, Stufen 30/45/60 → 45', () {
      expect(
        prescribedMinutes(variants: [30, 45, 60], available: 240, dose: 45),
        45,
      );
    });

    test('5. Verfügbarkeit kleiner als Dosis → Verfügbarkeit begrenzt', () {
      expect(
        prescribedMinutes(variants: [30, 45, 60], available: 35, dose: 60),
        30,
      );
    });

    test('6. Dosis kleiner als Verfügbarkeit → Dosis begrenzt', () {
      expect(
        prescribedMinutes(variants: [30, 45, 60], available: 240, dose: 45),
        45,
      );
    });

    test('12. keine erfundenen Dauern — nur Stufen des Katalogs', () {
      for (final dose in [31, 38, 44, 59, 83, 119]) {
        final minutes = prescribedMinutes(
          variants: [30, 45, 60],
          available: 240,
          dose: dose,
        );
        expect(
          [30, 45, 60],
          contains(minutes),
          reason: 'Dosis $dose ergab $minutes min — das ist keine Stufe.',
        );
        expect(minutes, lessThanOrEqualTo(dose));
      }
    });
  });

  group('4. Dosis unter der kleinsten Stufe', () {
    test('der Kandidat ist heute nicht zulässig', () {
      // Die Familie liefert ihre kuerzeste Variante, aber sie ueberschreitet
      // die Dosis — und wird deshalb im Expositionsfilter verworfen. Die
      // Verschreibung selbst darf die Dosis nicht unterbieten *koennen*:
      // Dass sie sie hier ueberschreitet, ist genau das Signal.
      final minutes = prescribedMinutes(
        variants: [45, 60],
        available: 240,
        dose: 30,
      );
      expect(
        minutes,
        greaterThan(30),
        reason: 'Es gibt nichts Kuerzeres — der Filter muss das sehen.',
      );
    });
  });

  group('11. Ercolina nutzt die kanonische Bibliothek', () {
    test('jede Ercolina-Variante stammt aus E0–E14', () {
      final canonicalMinutes = ercolinaCanonicalLibrary
          .map((w) => w.minutes)
          .toSet();
      final canonicalIds = ercolinaCanonicalLibrary.map((w) => w.id).toSet();

      final ercolinaFamilies = WorkoutFamily.standardFamilies.where(
        (f) => f.modality == XcModality.ercolinaDoublePoling,
      );
      expect(ercolinaFamilies, isNotEmpty);

      for (final family in ercolinaFamilies) {
        if (family.type == WorkoutFamilyType.activeRecovery) continue;
        for (final variant in family.allowedVariants) {
          expect(
            canonicalIds,
            contains(variant.id),
            reason:
                '${family.id}/${variant.id} steht nicht in der '
                'Gerätebibliothek — das wäre eine zweite Wahrheit.',
          );
          expect(canonicalMinutes, contains(variant.totalDurationMinutes));
        }
      }
    });

    test('die kurzen Technikeinheiten sind erreichbar', () {
      // E0 (20 min) und E1 (25 min) lagen auf der SD-Karte, waren aber ueber
      // keine Familie erreichbar. Dadurch war die kuerzeste Ercolina-Einheit
      // 35 Minuten — und bei einer Dosis von 30 fiel Ercolina ganz aus.
      final tech = WorkoutFamily.standardFamilies.firstWhere(
        (f) => f.id == 'fam_ercolina_tech',
      );
      final minutes = tech.allowedVariants
          .map((v) => v.totalDurationMinutes)
          .toList();
      expect(minutes, containsAll([20, 25]));
    });
  });

  group('Inhaltliche Lücken des Katalogs', () {
    // Diese Tests halten fest, was heute **fehlt**. Sie sind absichtlich so
    // geschrieben, dass sie rot werden, sobald die Luecke geschlossen ist —
    // dann gehoeren sie umgeschrieben. Varianten dafuer zu erfinden waere
    // eine sportwissenschaftliche Aussage ohne Grundlage.
    List<int> variantsOf(XcModality modality) => [
      for (final f in WorkoutFamily.standardFamilies)
        if (f.modality == modality)
          for (final v in f.allowedVariants) v.totalDurationMinutes,
    ];

    test('7./8. Laufen hat genau eine Stufe — CONTENT_GAP_RUNNING', () {
      expect(
        variantsOf(XcModality.running).toSet(),
        {45},
        reason:
            'Ein etablierter Laeufer mit belegten 120 min kann deshalb nicht '
            'mehr als 45 min bekommen. Das Dosismodell erlaubt mehr; die '
            'Bibliothek bietet nichts. CONTENT_GAP_RUNNING.',
      );
      // Die Gegenrichtung stimmt dagegen schon: Ohne Exposition bleibt es
      // bei der Einstiegsdosis, und die ist genau diese Stufe.
      expect(ModalityDoseModel.entryMinutesFor(XcModality.running), 45);
    });

    test('9. Rad hat genau eine Stufe — CONTENT_GAP_CYCLING', () {
      expect(
        variantsOf(XcModality.cycling).toSet(),
        {60},
        reason:
            'Belastbarkeit von 368 min, Angebot 60 min. CONTENT_GAP_CYCLING.',
      );
    });

    test('10. Rollski hat keine Familie — CONTENT_GAP_ROLLERSKI', () {
      for (final modality in [
        XcModality.rollerSkiSkating,
        XcModality.rollerSkiClassic,
        XcModality.rollerSkiDoublePoling,
      ]) {
        expect(
          variantsOf(modality),
          isEmpty,
          reason:
              '${modality.name} ist nicht verschreibbar, obwohl es im '
              'Sommer die spezifischste Modalitaet waere. '
              'CONTENT_GAP_ROLLERSKI.',
        );
        // Die Einstiegsdosis ist eine Eigenschaft der Belastungsart, nicht
        // des Katalogs: Rollski hat eine (45), aber keine Einheit, die man
        // darunter verschreiben koennte. Genau das ist die Luecke.
        expect(ModalityDoseModel.entryMinutesFor(modality), greaterThan(0));
      }
    });

    // -----------------------------------------------------------------------
    // 11.-13. Die Luecken, die beim Schliessen der Dosisdecke sichtbar
    // wurden. Jede beschreibt einen Athleten, dem der Katalog heute keine
    // Einheit anbieten kann — nicht einen Fehler der Dosisregel.
    // -----------------------------------------------------------------------

    /// Kuerzeste Einheit, die [stimulus] ausloest, ueber alle Modalitaeten.
    int? kuerzesteFuer(StimulusType stimulus) {
      final alle = <int>[
        for (final f in WorkoutFamily.standardFamilies)
          if (f.primaryStimulus == stimulus)
            for (final v in f.allowedVariants) v.totalDurationMinutes,
      ];
      if (alle.isEmpty) return null;
      return alle.reduce((a, b) => a < b ? a : b);
    }

    test(
      '11. Keine Schwelleneinheit unter 60 min — CONTENT_GAP_THRESHOLD_SHORT',
      () {
        final kuerzeste = kuerzesteFuer(StimulusType.threshold);
        expect(kuerzeste, isNotNull);
        expect(
          kuerzeste,
          greaterThanOrEqualTo(60),
          reason:
              'Ein Athlet mit einer plausiblen Dosis von 40 bis 45 min kann '
              'keinen Schwellenreiz bekommen, auch wenn er ausdruecklich einen '
              'Block plant: Die kuerzeste Schwelleneinheit der Bibliothek ist '
              '\$kuerzeste min. CONTENT_GAP_THRESHOLD_SHORT.',
        );
      },
    );

    test('12. Keine VO2max-Einheit unter 35 min — CONTENT_GAP_VO2_SHORT', () {
      expect(
        kuerzesteFuer(StimulusType.vo2max),
        35,
        reason:
            'Unter einer Dosisdecke von 30 min — der Einstiegsdosis am '
            'Zuggeraet — gibt es keinen VO2max-Reiz. CONTENT_GAP_VO2_SHORT.',
      );
    });

    test(
      '13. Keine kurze Ercolina-Grundlage — CONTENT_GAP_ERCOLINA_BASE_SHORT',
      () {
        final dpBase = <int>[
          for (final f in WorkoutFamily.standardFamilies)
            if (f.modality == XcModality.ercolinaDoublePoling &&
                (f.primaryStimulus == StimulusType.aerobicBase ||
                    f.primaryStimulus == StimulusType.doublePolingEndurance))
              for (final v in f.allowedVariants) v.totalDurationMinutes,
        ]..sort();
        expect(dpBase, isNotEmpty);
        expect(
          dpBase.first,
          greaterThanOrEqualTo(55),
          reason:
              'Wer Ercolina bevorzugt und 50 min Zeit hat, bekommt an einem '
              'Grundlagentag keine Ercolina-Grundlage: Die kuerzeste ist '
              '\${dpBase.first} min (E4). Die Praeferenz kann deshalb nicht '
              'erfuellt werden. CONTENT_GAP_ERCOLINA_BASE_SHORT.',
        );
      },
    );

    test(
      '14. Kein ausfuehrbares Z1-Blueprint — CONTENT_GAP_RECOVERY_BLUEPRINT',
      () {
        final rec = WorkoutFamily.standardFamilies.firstWhere(
          (f) => f.primaryStimulus == StimulusType.recovery,
        );
        for (final v in rec.allowedVariants) {
          expect(
            v.templateId,
            isNull,
            reason:
                'Aktive Erholung hat kein ausfuehrbares Blueprint. Der Start '
                'fuehrt bewusst in freies Training statt auf eine ID zu '
                'zeigen, die nicht aufloest. CONTENT_GAP_RECOVERY_BLUEPRINT.',
          );
        }
      },
    );
  });
}
