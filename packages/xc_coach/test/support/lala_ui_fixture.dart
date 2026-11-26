/// Shared environment for the Phase-E LaLa tests.
///
/// Builds a realistic club: an organisation, a head coach and an athlete —
/// and deliberately **no device**. Everything the LaLa module needs must work
/// from manually entered numbers alone.
library;

import 'package:xc_coach/measurement/contracts/test_protocol.dart';
import 'package:xc_coach/database/diagnostics_repository.dart';
import 'package:xc_coach/domain/diagnostics.dart';
import 'package:xc_coach/domain/platform.dart';
import 'package:xc_coach/lala/application/lala_controller.dart';
import 'package:xc_coach/lala/application/lala_test_draft.dart';

import 'platform_fixture.dart';

/// One measured step as a diagnostician would write it on paper.
typedef LalaStepInput = ({double load, double lactate, int heartRate});

/// A real, fully evaluable cycling step test.
///
/// These are the measured stages of the demo ergometry `demo-bike-2021-02-18`
/// (60–280 W in 20 W steps). The standard LT1 method needs enough stages below
/// 70 % of peak load to be mathematically determined, so this is the protocol
/// that produces a regular standard-method result.
const List<LalaStepInput> fullCyclingSteps = <LalaStepInput>[
  (load: 60, lactate: 1.41, heartRate: 116),
  (load: 80, lactate: 1.44, heartRate: 117),
  (load: 100, lactate: 1.47, heartRate: 122),
  (load: 120, lactate: 1.70, heartRate: 138),
  (load: 140, lactate: 1.96, heartRate: 143),
  (load: 160, lactate: 2.53, heartRate: 151),
  (load: 180, lactate: 3.28, heartRate: 159),
  (load: 200, lactate: 4.16, heartRate: 167),
  (load: 220, lactate: 5.45, heartRate: 174),
  (load: 240, lactate: 7.23, heartRate: 178),
  (load: 260, lactate: 10.50, heartRate: 184),
  (load: 280, lactate: 14.90, heartRate: 193),
];

/// The same athlete a few months later — every stage a little lower.
const List<LalaStepInput> improvedCyclingSteps = <LalaStepInput>[
  (load: 60, lactate: 1.30, heartRate: 112),
  (load: 80, lactate: 1.32, heartRate: 114),
  (load: 100, lactate: 1.35, heartRate: 118),
  (load: 120, lactate: 1.50, heartRate: 131),
  (load: 140, lactate: 1.72, heartRate: 138),
  (load: 160, lactate: 2.10, heartRate: 146),
  (load: 180, lactate: 2.70, heartRate: 154),
  (load: 200, lactate: 3.40, heartRate: 162),
  (load: 220, lactate: 4.40, heartRate: 170),
  (load: 240, lactate: 5.90, heartRate: 175),
  (load: 260, lactate: 8.40, heartRate: 181),
  (load: 280, lactate: 12.10, heartRate: 190),
];

/// A short, coarse ramp — the "thin Hofmann data set" from Phase D.
///
/// Four 50 W steps starting at 100 W are a legitimate, recordable test, but
/// they leave too few stages below 70 % of peak load for the reconstructed
/// Hofmann/Graz breakpoint to be mathematically determined. The engine
/// therefore falls back for both thresholds, and the platform stores which
/// method it really used — which is exactly what the UI has to show.
const List<LalaStepInput> thinCyclingSteps = <LalaStepInput>[
  (load: 100, lactate: 1.10, heartRate: 115),
  (load: 150, lactate: 1.50, heartRate: 132),
  (load: 200, lactate: 2.30, heartRate: 150),
  (load: 250, lactate: 4.20, heartRate: 170),
];

/// A treadmill test, used to prove that km/h and W are never mixed.
const List<LalaStepInput> runningSteps = <LalaStepInput>[
  (load: 8.0, lactate: 1.20, heartRate: 120),
  (load: 9.5, lactate: 1.35, heartRate: 130),
  (load: 11.0, lactate: 1.60, heartRate: 141),
  (load: 12.5, lactate: 2.10, heartRate: 152),
  (load: 14.0, lactate: 3.00, heartRate: 163),
  (load: 15.5, lactate: 4.40, heartRate: 172),
  (load: 17.0, lactate: 6.60, heartRate: 180),
  (load: 18.5, lactate: 9.80, heartRate: 188),
];

/// Club, coach, athlete and a ready-to-use [LalaController].
class LalaFixture {
  LalaFixture() {
    platform.organization('club');
    platform.organization('other-club');
    platform.user('coach');
    platform.membership(
      organizationId: 'club',
      userId: 'coach',
      role: PlatformRole.headCoach,
    );
    platform.athlete('anna', 'club');

    diagnostics = DiagnosticsRepository(
      platform.database,
      platform: platform.platform,
    );
    controller = LalaController(
      diagnostics: diagnostics,
      platform: platform.platform,
      session: const LalaSession(
        userId: 'coach',
        organizationId: 'club',
        roles: {PlatformRole.headCoach},
      ),
      clock: clock,
    );
  }

  final PlatformFixture platform = PlatformFixture();
  late final DiagnosticsRepository diagnostics;
  late final LalaController controller;

  int _now = 1_700_000_000_000_000;

  /// Monotonic clock: reproducible, and distinct ids for successive tests.
  int clock() => _now += 1_000_000;

  /// Records a body mass for the athlete, effective from [effectiveFromUtcUs].
  ///
  /// Zeitwirksam, nicht "aktuell": Die Relativleistung eines Tests vom letzten
  /// Winter muss gegen die Masse von damals gelesen werden.
  void recordBodyMass(
    double kilograms, {
    String athleteId = 'anna',
    int effectiveFromUtcUs = 1_500_000_000_000_000,
  }) {
    platform.platform.recordAttribute(
      id: 'mass-$athleteId-$effectiveFromUtcUs',
      athleteId: athleteId,
      attribute: AthleteAttribute.bodyMassKg,
      value: kilograms,
      unit: 'kg',
      effectiveFromUtcUs: effectiveFromUtcUs,
      recordedAtUtcUs: effectiveFromUtcUs,
    );
  }

  /// Turns measured steps into a ready-to-save draft.
  LalaTestDraft draft(
    List<LalaStepInput> steps, {
    TestProtocol? preset,
    String athleteId = 'anna',
    int startedAtUtcUs = 1_600_000_000_000_000,
  }) => LalaTestDraft(
    athleteId: athleteId,
    preset: preset ?? testProtocols.first,
    startedAtUtcUs: startedAtUtcUs,
    stages: <LalaStageDraft>[
      for (var index = 0; index < steps.length; index++)
        LalaStageDraft(
          stageNumber: index + 1,
          load: steps[index].load,
          durationSeconds: 180,
          heartRateBpm: steps[index].heartRate,
          lactateMmolPerLitre: steps[index].lactate,
        ),
    ],
  );

  /// Stores and evaluates a test, returning its id.
  String seedEvaluatedTest(
    List<LalaStepInput> steps, {
    TestProtocol? preset,
    int startedAtUtcUs = 1_600_000_000_000_000,
  }) {
    controller.saveAndEvaluate(
      draft(steps, preset: preset, startedAtUtcUs: startedAtUtcUs),
    );
    return controller.overview!.latestTest!.head.id;
  }

  /// Records a test without ever evaluating it.
  void seedUnevaluatedTest({String id = 'test-open'}) {
    diagnostics.createTest(
      id: id,
      organizationId: 'club',
      athleteId: 'anna',
      sport: 'cycling',
      modality: 'step_test',
      protocol: 'standard_step_3min',
      protocolVersion: '1.0.0',
      loadUnit: LoadUnits.watt,
      measurementSource: MeasurementSource.manual,
      startedAtUtcUs: 5_000_000,
      createdByUserId: 'coach',
    );
  }

  void dispose() {
    controller.dispose();
    platform.dispose();
  }
}
