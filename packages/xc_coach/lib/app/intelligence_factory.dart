/// Product-neutral composition of GIULIA Intelligence.
library;

import '../database/giulia_database.dart';
import '../database/platform_repository.dart';
import '../database/training_plan_repository.dart';
import '../intelligence/coach.dart';
import '../intelligence/workout_selection/daily_coaching_decision.dart';
import '../intelligence/coach_context.dart';
import '../intelligence/tools.dart';
import 'intelligence_data_source.dart';

GiuliaCoach giuliaCoachFor({
  required GiuliaDatabase database,
  required PlatformRepository platform,
  required String organizationId,
  required String userId,
  DailyCoachingDecision Function(String)? todayFor,
}) {
  final data = GiuliaIntelligenceDataSource(
    database: database,
    platform: platform,
    organizationId: organizationId,
    userId: userId,
  );
  return GroundedGiuliaCoach(
    GiuliaContextBuilder(
      GiuliaIntelligenceTools(
        data: data,
        coachContext: CoachContextBuilder(
          data: data,
          plan: SqliteTrainingPlanRepository(database),
        ),
      ),
    ),
    todayFor: todayFor,
  );
}
