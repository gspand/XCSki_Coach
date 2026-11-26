import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/app/athlete_ercolina_profile.dart';
import 'package:xc_coach/domain/normalized_session.dart';
import 'package:xc_coach/domain/xc_modality.dart';
import 'package:xc_coach/intelligence/load/stimulus_models.dart';
import 'package:xc_coach/intelligence/load/ewma_load_tracker.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/data_coverage_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/elite_analysis_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/goal_context.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/ski_exposure_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/stimulus_history_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/subjective_readiness_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/training_load_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/xc_athlete_state.dart';
import 'package:xc_coach/intelligence/xc_athlete_state/xc_athlete_state_builder.dart';
import 'package:xc_coach/metrics/session_complete_analysis.dart';
import 'package:xc_coach/presentation/canonical_terminology.dart';
import 'package:xc_coach/ui/athlete/athlete_state_view_screen.dart';
import 'package:xc_coach/ui/design_system.dart';

void main() {
  const builder = XCAthleteStateBuilder();
  final baseDate = DateTime.utc(2026, 10, 3, 9, 0);

  group('AthleteStateViewScreen Widget Tests', () {
    testWidgets('charts use explicit scientific axes and canonical units', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 14000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final loadStates = [
        for (var day = 0; day < 28; day++)
          EwmaDailyState(
            date: baseDate.subtract(Duration(days: 27 - day)),
            dailyLoad: day.isEven ? 40 : 20,
            acuteLoad: 32 + day * .8,
            chronicLoad: 40 + day * .35,
            loadBalance: 8 - day * .45,
          ),
      ];
      final state = XCAthleteState(
        athleteId: 'jan_01',
        asOf: baseDate,
        trainingLoad: TrainingLoadState(
          banisterTrimpSeries: EwmaSeries(
            seriesId: 'jan-trimp',
            athleteId: 'jan_01',
            method: 'banister_trimp',
            unit: 'trimp_points',
            version: '1.0',
            states: loadStates,
          ),
        ),
        skiExposure: const SkiSpecificExposureState(
          byModality: {
            XcModality.skiClassic: SkiModalityExposure(
              modality: XcModality.skiClassic,
              durationSeconds28d: 28800,
              sessionCount28d: 5,
            ),
            XcModality.ercolinaDoublePoling: SkiModalityExposure(
              modality: XcModality.ercolinaDoublePoling,
              durationSeconds28d: 10800,
              sessionCount28d: 3,
            ),
          },
        ),
        stimulusHistory: const StimulusHistoryState(
          entries: {
            StimulusType.aerobicBase: StimulusHistoryEntry(
              type: StimulusType.aerobicBase,
              frequency28d: 6,
              accumulatedExposureMinutes28d: 420,
            ),
            StimulusType.threshold: StimulusHistoryEntry(
              type: StimulusType.threshold,
              frequency28d: 3,
              accumulatedExposureMinutes28d: 72,
            ),
          },
        ),
        dataCoverage: const DataCoverageState(
          externalActivityCoverage: .92,
          ercolinaCoverage: 1,
          hrCoverage: .84,
          powerCoverage: .68,
          subjectiveCoverage: .55,
          diagnosticsCoverage: .4,
          unknownDays28d: 2,
          observedTrainingDays28d: 20,
          confirmedRestDays28d: 6,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(
            useMaterial3: true,
          ).copyWith(scaffoldBackgroundColor: GiuliaTokens.surface0),
          home: AthleteStateViewScreen(athleteState: state, athleteName: 'Jan'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('athlete-load-trend')), findsOneWidget);
      expect(find.byKey(const Key('chart-modality-exposure')), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Banister TRIMP in Punkten')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Trainingszeit in Stunden in 28 Tagen')),
        findsOneWidget,
      );

      await tester.tap(find.text('TRAININGSREIZE'));
      await tester.tap(
        find.text(CanonicalTerminology.sectionDiagnosticsAndData),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chart-stimulus-frequency')), findsOneWidget);
      expect(find.byKey(const Key('chart-data-coverage')), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Anzahl der Reize in 28 Tagen')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Datenabdeckung in Prozent')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders the complete evidence-backed athlete evaluation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 9000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final state = builder.buildState(
        athleteId: 'jan_01',
        asOf: baseDate,
        goal: GoalContext(
          name: 'Vasaloppet 2027',
          modality: XcModality.skiClassic,
          targetDistanceMetres: 90000.0,
          raceDate: DateTime.utc(2027, 3, 7),
          priority: 'A',
        ),
        subjectiveReadiness: SubjectiveReadinessState(
          recordedAt: baseDate,
          perceivedRecovery: 8.0,
          sleepQuality: 7.5,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(
            useMaterial3: true,
          ).copyWith(scaffoldBackgroundColor: GiuliaTokens.surface0),
          home: AthleteStateViewScreen(athleteState: state, athleteName: 'Jan'),
        ),
      );
      await tester.pumpAndSettle();

      // Hero Card
      expect(find.text('Jan'), findsOneWidget);
      expect(find.text('Vasaloppet 2027'), findsOneWidget);

      // Canonical overview and every full-evaluation domain.
      expect(find.text('BELASTUNG & ERHOLUNG'), findsOneWidget);
      expect(
        find.text(CanonicalTerminology.sectionPerformance),
        findsOneWidget,
      );
      expect(
        find.text(CanonicalTerminology.sectionXcSpecificity),
        findsOneWidget,
      );
      expect(find.text('DOPPELSTOCK & TECHNIK'), findsOneWidget);
      expect(find.text('TRAININGSREIZE'), findsOneWidget);
      expect(find.text('LEISTUNGSENTWICKLUNG'), findsOneWidget);
      expect(
        find.text(CanonicalTerminology.sectionDiagnosticsAndData),
        findsOneWidget,
      );

      // Section 1 details (in initial viewport)
      expect(find.text('Kurzfristige Last'), findsOneWidget);
      expect(find.text('Langfristige Last'), findsOneWidget);
      expect(find.text('Belastungsbalance'), findsOneWidget);

      // Every one of the 14 XC stimulus types is present. Missing evidence
      // stays explicit rather than being filled with a made-up score.
      await tester.tap(find.text('TRAININGSREIZE'));
      await tester.pumpAndSettle();
      for (final type in StimulusType.values) {
        expect(find.byKey(ValueKey('stimulus-${type.key}')), findsOneWidget);
      }
      expect(find.textContaining('Nicht erfasst'), findsWidgets);
    });

    testWidgets(
      'renders full-history elite charts and explicit evidence gaps',
      (tester) async {
        var profileEdits = 0;
        tester.view.physicalSize = const Size(900, 16000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final state = builder.buildState(
          athleteId: 'jan_01',
          asOf: baseDate,
          physiology: const AthletePhysiologyState(
            bodyMassKg: 72,
            maxHeartRateBpm: 190,
            restingHeartRateBpm: 45,
          ),
          sessions: [
            NormalizedSession(
              id: 'history-session',
              athleteId: 'jan_01',
              source: NormalizedSessionSource.garmin,
              sourceId: 'history-session',
              startedAtUtcUs: baseDate
                  .subtract(const Duration(days: 400))
                  .microsecondsSinceEpoch,
              durationSeconds: 7200,
              movingTimeSeconds: 7000,
              modality: XcModality.skiSkating,
              isIndoor: false,
              title: 'Skating lang',
              distanceMetres: 35000,
              elevationGainMetres: 800,
              internalMetrics: const SessionInternalMetrics(
                averageHeartRateBpm: 142,
                timeInHrZonesSeconds: {
                  'z1': 1000,
                  'z2': 3000,
                  'z3': 2000,
                  'z4': 1000,
                },
              ),
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light(
              useMaterial3: true,
            ).copyWith(scaffoldBackgroundColor: GiuliaTokens.surface0),
            home: AthleteStateViewScreen(
              athleteState: state,
              athleteName: 'Jan',
              ercolinaProfile: AthleteErcolinaProfile(
                sessionCount: 4,
                firstSessionAt: baseDate.subtract(const Duration(days: 300)),
                lastSessionAt: baseDate,
                powerBests: [
                  HistoricalPowerDurationBest(
                    sessionId: 'e1',
                    achievedAt: baseDate,
                    best: const PowerDurationBest(
                      duration: Duration(seconds: 5),
                      averagePowerWatt: 320,
                      startedAtSeconds: 10,
                      workJoule: 1600,
                      strokeCount: 4,
                      cadencePerMinute: 48,
                      workPerStrokeJoule: 400,
                      leftShare: .504,
                    ),
                  ),
                  HistoricalPowerDurationBest(
                    sessionId: 'e2',
                    achievedAt: baseDate.subtract(const Duration(days: 20)),
                    best: const PowerDurationBest(
                      duration: Duration(minutes: 5),
                      averagePowerWatt: 210,
                      startedAtSeconds: 30,
                      workJoule: 63000,
                      strokeCount: 210,
                      cadencePerMinute: 42,
                      workPerStrokeJoule: 300,
                      leftShare: .498,
                    ),
                    fatigueDeltaPercent: -3.2,
                  ),
                ],
                strokeBests: [
                  HistoricalStrokeCountBest(
                    sessionId: 'e1',
                    achievedAt: baseDate,
                    best: const StrokeCountBest(
                      strokeCount: 10,
                      firstStrokeIndex: 12,
                      activePowerWatt: 290,
                      workPerStrokeJoule: 380,
                      peakPowerWatt: 520,
                      cadencePerMinute: 45,
                      leftShare: .501,
                      shapeVariationPercent: 4.2,
                    ),
                  ),
                ],
                powerHistory: const {},
              ),
              onEditProfile: () => profileEdits++,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('section-longitudinal-analysis')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('elite-analysis-overview')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('elite-window-comparison')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('elite-monthly-volume-chart')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('ercolina-longitudinal-profile')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp('Ercolina Bestleistung')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('elite-intensity-chart')), findsOneWidget);
        expect(find.byKey(const Key('elite-modality-chart')), findsOneWidget);
        expect(find.byKey(const Key('section-best-evidence')), findsOneWidget);
        expect(find.byKey(const Key('elite-evidence-gaps')), findsOneWidget);
        expect(
          find.byKey(const Key('edit-athlete-physiology')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('edit-athlete-physiology')));
        expect(profileEdits, 1);
        expect(find.text('Gesamte Zeit'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
