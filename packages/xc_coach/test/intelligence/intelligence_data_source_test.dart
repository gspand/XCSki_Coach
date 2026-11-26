import 'package:flutter_test/flutter_test.dart';
import 'package:xc_coach/app/intelligence_data_source.dart';

import '../support/lala_ui_fixture.dart';

void main() {
  late LalaFixture fixture;

  setUp(() => fixture = LalaFixture());
  tearDown(() => fixture.dispose());

  test('reads immutable engine results and measured curves together', () {
    fixture.seedEvaluatedTest(
      fullCyclingSteps,
      startedAtUtcUs: 1_600_000_000_000_000,
    );
    fixture.seedEvaluatedTest(
      improvedCyclingSteps,
      startedAtUtcUs: 1_700_000_000_000_000,
    );
    final source = GiuliaIntelligenceDataSource(
      database: fixture.platform.database,
      platform: fixture.platform.platform,
      organizationId: 'club',
      userId: 'coach',
    );

    final tests = source.getTests('anna');

    expect(tests, hasLength(2));
    expect(tests.first.curve, hasLength(fullCyclingSteps.length));
    expect(tests.first.threshold('lt1'), isNotNull);
    expect(tests.first.threshold('lt2'), isNotNull);
    expect(tests.first.thresholds, hasLength(24));
    expect(tests.first.zones, isNotEmpty);
    expect(tests.first.engineVersion, isNotNull);
    expect(tests.first.structure?.increment, 20);
  });

  test('access control is applied before intelligence reads athlete data', () {
    final source = GiuliaIntelligenceDataSource(
      database: fixture.platform.database,
      platform: fixture.platform.platform,
      organizationId: 'other-club',
      userId: 'coach',
    );

    expect(source.getAthleteProfile('anna'), isNull);
    expect(source.getTests('anna'), isEmpty);
    expect(source.getRecentTraining('anna'), isEmpty);
    expect(source.getAthleteState('anna', nowUtcUs: 1), isNull);
  });
}
