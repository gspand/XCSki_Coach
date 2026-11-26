/// Durable multi-tenant schema for the Giulia platform.
///
/// Design rules enforced here:
/// * every measured record is attributable to exactly one organization and,
///   where applicable, exactly one athlete;
/// * a training device is owned by an organization, never by an athlete;
/// * longitudinal facts (body mass, thresholds, zones, records) are stored as
///   insert-only, time-effective rows so history is never overwritten;
/// * every mutable row carries `updated_at_utc_us` and a sync state so the
///   offline-first sync layer can be added without a schema rebuild.
library;

/// Incremented for every migration. `PRAGMA user_version` tracks the applied
/// state of an existing database file. Migrations are additive with one
/// documented exception, `_v9RemoveDemonstrationWorkspace`, which removes the
/// generated demonstration tenant and says at length why.
const int giuliaSchemaVersion = 32;

/// Ordered migrations. Index `n` upgrades a database from version `n` to `n+1`.
const List<String> giuliaMigrations = <String>[
  _v1PlatformSchema,
  _v2LalaDiagnostics,
  _v3WorkspacesAndCoaching,
  _v4DeviceMeasuredSteps,
  _v5ProductManagement,
  _v6TrainerPrivateNotes,
  _v7DiagnosticCorrections,
  _v8ExplicitMethodSelections,
  _v9RemoveDemonstrationWorkspace,
  _v10CoachingConfiguration,
  _v11Observations,
  _v12SessionPauses,
  _v13DeviceKindsAndExternalImports,
  _v14RepairAndEnrichScoutImports,
  _v15LosslessRecordingAndRecovery,
  _v16ExternalActivities,
  _v17CanonicalActivitiesAndAthleteState,
  _v18RawPullState,
  _v19CompleteErcolinaLogging,
  _v20MechanicalStrokeEvents,
  _v21StrokeTechnique,
  _v22TrainingPlanAndCoachDecisions,
  _v23TrainingGoalsAndAvailability,
  _v24CoachEndToEndPersistence,
  _v25FemaleAthleteIntelligence,
  _v26NormalizedSessionAnalysisCache,
  _v27WorkoutLibraryRemoval,
  _v28EpochScopedObservations,
  _v29SignedWork,
  _v30SideStrokeRecords,
  _v31MeasurementSegments,
  _v32ScoutReadings,
];

/// Source records are independent of bilateral clock pairing and display rows.
/// Retransmissions share one key; original raw envelopes remain append-only.
const String _v30SideStrokeRecords = '''
CREATE TABLE side_stroke_record (
  session_id TEXT NOT NULL REFERENCES session(id),
  source_id TEXT NOT NULL,
  source_epoch INTEGER NOT NULL,
  sequence INTEGER NOT NULL,
  side TEXT NOT NULL CHECK(side IN ('left','right')),
  start_us INTEGER NOT NULL,
  end_us INTEGER NOT NULL,
  duration_us INTEGER NOT NULL,
  work_mj INTEGER NOT NULL,
  rope_mj INTEGER NOT NULL,
  quality INTEGER NOT NULL,
  payload BLOB NOT NULL,
  first_received_us INTEGER NOT NULL,
  in_scope INTEGER NOT NULL CHECK(in_scope IN (0,1)),
  scope_reason TEXT NOT NULL,
  PRIMARY KEY(session_id,source_id,source_epoch,sequence),
  CHECK(end_us>=start_us AND duration_us=end_us-start_us)
);
CREATE INDEX idx_side_stroke_source_time ON side_stroke_record(session_id,source_id,source_epoch,start_us);
CREATE TRIGGER side_stroke_source_immutable
BEFORE UPDATE OF source_id,source_epoch,sequence,side,start_us,end_us,duration_us,work_mj,rope_mj,quality,payload
ON side_stroke_record BEGIN SELECT RAISE(ABORT,'Immutable side-stroke observation'); END;
''';

/// Templates can be removed without breaking session / interval foreign keys.
/// Undo only clears this marker; measurements and step identities stay intact.
const String _v27WorkoutLibraryRemoval = '''
ALTER TABLE workout ADD COLUMN deleted_at_utc_us INTEGER;
''';

/// Compact projection for the hot athlete-analysis path.
///
/// `data_json` remains the immutable source payload, including the original
/// Strava streams. The projection is populated by [GiuliaDatabase] after the
/// SQL migration because gap-preserving stream summarisation is deliberately
/// implemented once in Dart, not duplicated in migration SQL.
const String _v26NormalizedSessionAnalysisCache = '''
ALTER TABLE normalized_session_record ADD COLUMN analysis_json TEXT;
''';

/// Storage for Strava sync states, normalized sessions, check-ins, overrides,
/// and coach validation records.
const String _v24CoachEndToEndPersistence = '''
CREATE TABLE strava_sync_state (
  athlete_id TEXT PRIMARY KEY REFERENCES athlete(id),
  api_base_url TEXT NOT NULL,
  session_id TEXT NOT NULL,
  session_secret TEXT NOT NULL,
  access_token TEXT NOT NULL,
  refresh_token TEXT NOT NULL,
  strava_athlete_id TEXT NOT NULL,
  strava_athlete_name TEXT NOT NULL,
  last_sync_at_utc_us INTEGER,
  covered_from_utc_us INTEGER,
  covered_to_utc_us INTEGER,
  last_error TEXT,
  updated_at_utc_us INTEGER NOT NULL
);

CREATE TABLE normalized_session_record (
  id TEXT PRIMARY KEY,
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  source TEXT NOT NULL,
  source_id TEXT NOT NULL,
  started_at_utc_us INTEGER NOT NULL,
  duration_seconds INTEGER NOT NULL,
  moving_time_seconds INTEGER NOT NULL,
  modality TEXT NOT NULL,
  technique TEXT NOT NULL,
  provenance TEXT NOT NULL,
  is_indoor INTEGER NOT NULL,
  title TEXT NOT NULL,
  data_json TEXT NOT NULL,
  created_at_utc_us INTEGER NOT NULL,
  UNIQUE(athlete_id, source, source_id)
);
CREATE INDEX idx_norm_session_athlete ON normalized_session_record(athlete_id, started_at_utc_us DESC);

CREATE TABLE athlete_check_in (
  id TEXT PRIMARY KEY,
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  recorded_at_utc_us INTEGER NOT NULL,
  readiness_json TEXT NOT NULL,
  created_at_utc_us INTEGER NOT NULL
);
CREATE INDEX idx_check_in_athlete ON athlete_check_in(athlete_id, recorded_at_utc_us DESC);

CREATE TABLE athlete_user_override (
  id TEXT PRIMARY KEY,
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  recorded_at_utc_us INTEGER NOT NULL,
  override_json TEXT NOT NULL,
  created_at_utc_us INTEGER NOT NULL
);
CREATE INDEX idx_override_athlete ON athlete_user_override(athlete_id, recorded_at_utc_us DESC);

CREATE TABLE coach_decision_record (
  id TEXT PRIMARY KEY,
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  decided_at_utc_us INTEGER NOT NULL,
  decision_json TEXT NOT NULL,
  created_at_utc_us INTEGER NOT NULL
);
CREATE INDEX idx_decision_record_athlete ON coach_decision_record(athlete_id, decided_at_utc_us DESC);

CREATE TABLE coach_validation_record_store (
  id TEXT PRIMARY KEY,
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  created_at_utc_us INTEGER NOT NULL,
  record_json TEXT NOT NULL
);
CREATE INDEX idx_validation_store_athlete ON coach_validation_record_store(athlete_id, created_at_utc_us DESC);

CREATE TABLE coach_chat_message (
  id TEXT PRIMARY KEY,
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  sender TEXT NOT NULL,
  text TEXT NOT NULL,
  structured_json TEXT,
  created_at_utc_us INTEGER NOT NULL
);
CREATE INDEX idx_chat_athlete ON coach_chat_message(athlete_id, created_at_utc_us ASC);
''';

/// Female athlete, cycle configuration, symptom reports, periods and health signals.
const String _v25FemaleAthleteIntelligence = '''
CREATE TABLE female_athlete_profile (
  athlete_id TEXT PRIMARY KEY REFERENCES athlete(id),
  opt_in TEXT NOT NULL DEFAULT 'undecided',
  hormonal_status TEXT NOT NULL DEFAULT 'unknown',
  is_regular_cycle INTEGER,
  typical_cycle_length_days REAL,
  contraceptive_details TEXT,
  contraceptive_started_at_utc_us INTEGER,
  updated_at_utc_us INTEGER NOT NULL
);

CREATE TABLE cycle_period_record (
  id TEXT PRIMARY KEY,
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  start_date TEXT NOT NULL,
  end_date TEXT,
  average_bleeding TEXT NOT NULL,
  cycle_length_days INTEGER,
  is_spotting_only INTEGER NOT NULL DEFAULT 0,
  has_perceived_ovulation INTEGER NOT NULL DEFAULT 0,
  has_objective_ovulation INTEGER NOT NULL DEFAULT 0,
  provenance TEXT NOT NULL DEFAULT 'userReported',
  created_at_utc_us INTEGER NOT NULL
);
CREATE INDEX idx_cycle_period_athlete ON cycle_period_record(athlete_id, start_date DESC);

CREATE TABLE daily_cycle_symptom_record (
  id TEXT PRIMARY KEY,
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  date TEXT NOT NULL,
  bleeding TEXT NOT NULL,
  cramps TEXT NOT NULL,
  unusual_fatigue TEXT NOT NULL,
  energy_level REAL,
  sleep_disturbance TEXT NOT NULL,
  mood_changes TEXT NOT NULL,
  headache TEXT NOT NULL,
  gi_symptoms TEXT NOT NULL,
  breast_tenderness TEXT NOT NULL,
  perceived_readiness REAL,
  notes TEXT,
  recorded_at_utc_us INTEGER NOT NULL,
  UNIQUE(athlete_id, date)
);
CREATE INDEX idx_cycle_symptom_athlete ON daily_cycle_symptom_record(athlete_id, date DESC);

CREATE TABLE female_athlete_health_signal_record (
  id TEXT PRIMARY KEY,
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  signal_type TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  medical_disclaimer TEXT NOT NULL,
  detected_at TEXT NOT NULL,
  recommendation_action TEXT NOT NULL,
  created_at_utc_us INTEGER NOT NULL
);
CREATE INDEX idx_female_health_signal_athlete ON female_athlete_health_signal_record(athlete_id, detected_at DESC);

CREATE TABLE iron_lab_record (
  id TEXT PRIMARY KEY,
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  measured_at TEXT NOT NULL,
  ferritin_ug_l REAL,
  hemoglobin_g_dl REAL,
  transferrin_sat_percent REAL,
  reference_range TEXT,
  source TEXT NOT NULL,
  confidence REAL NOT NULL,
  created_at_utc_us INTEGER NOT NULL
);
CREATE INDEX idx_iron_lab_athlete ON iron_lab_record(athlete_id, measured_at DESC);
''';

/// What the athlete aims for and when training fits into the week.
///
/// Availability is a constraint, not a prescription: a row says what is
/// possible on a weekday, never what has to be trained.
const String _v23TrainingGoalsAndAvailability = '''
CREATE TABLE training_goal (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organization(id),
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  name TEXT NOT NULL,
  kind TEXT NOT NULL,
  modality TEXT NOT NULL,
  goal_date TEXT,
  distance_km REAL,
  target_seconds INTEGER,
  priority TEXT NOT NULL DEFAULT 'a',
  created_at_utc_us INTEGER NOT NULL,
  updated_at_utc_us INTEGER NOT NULL,
  archived_at_utc_us INTEGER,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);
CREATE INDEX idx_training_goal_athlete ON training_goal(athlete_id);

CREATE TABLE training_availability (
  organization_id TEXT NOT NULL REFERENCES organization(id),
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  weekday INTEGER NOT NULL CHECK (weekday BETWEEN 1 AND 7),
  minutes INTEGER NOT NULL CHECK (minutes >= 0),
  modalities_json TEXT NOT NULL DEFAULT '[]',
  rest_day INTEGER NOT NULL DEFAULT 0,
  long_day INTEGER NOT NULL DEFAULT 0,
  updated_at_utc_us INTEGER NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending',
  PRIMARY KEY (athlete_id, weekday)
);
''';

/// Planned workouts and the decisions that changed them.
///
/// A planned workout is not a session: it points to the session that fulfilled
/// it. Decisions are append-only so every plan change keeps its reason.
const String _v22TrainingPlanAndCoachDecisions = '''
CREATE TABLE planned_workout (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organization(id),
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  planned_date TEXT NOT NULL,
  sport TEXT NOT NULL,
  goal TEXT NOT NULL,
  duration_seconds INTEGER NOT NULL,
  intensity TEXT,
  blueprint_id TEXT,
  structure_json TEXT NOT NULL DEFAULT '[]',
  status TEXT NOT NULL DEFAULT 'planned',
  session_id TEXT REFERENCES session(id),
  created_by_user_id TEXT REFERENCES app_user(id),
  created_at_utc_us INTEGER NOT NULL,
  updated_at_utc_us INTEGER NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);
CREATE INDEX idx_planned_workout_athlete
  ON planned_workout(athlete_id, planned_date);
CREATE UNIQUE INDEX idx_planned_workout_session
  ON planned_workout(session_id) WHERE session_id IS NOT NULL;

CREATE TABLE coach_decision (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organization(id),
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  decided_at_utc_us INTEGER NOT NULL,
  decision_type TEXT NOT NULL,
  decided_by TEXT NOT NULL,
  decided_by_user_id TEXT REFERENCES app_user(id),
  planned_workout_ids_json TEXT NOT NULL DEFAULT '[]',
  facts_json TEXT NOT NULL DEFAULT '[]',
  change_json TEXT NOT NULL DEFAULT '{}',
  reason TEXT NOT NULL,
  data_quality TEXT,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);
CREATE INDEX idx_coach_decision_athlete
  ON coach_decision(athlete_id, decided_at_utc_us);
CREATE TRIGGER trg_coach_decision_no_update
BEFORE UPDATE ON coach_decision
BEGIN
  SELECT RAISE(ABORT, 'coach_decision ist unveraenderlich');
END;
CREATE TRIGGER trg_coach_decision_no_delete
BEFORE DELETE ON coach_decision
BEGIN
  SELECT RAISE(ABORT, 'coach_decision ist unveraenderlich');
END;
''';

const String _v21StrokeTechnique = '''
ALTER TABLE stroke ADD COLUMN technique TEXT NOT NULL DEFAULT 'legacy';
''';

const String _v20MechanicalStrokeEvents = '''
ALTER TABLE raw_sensor_sample
  ADD COLUMN angular_velocity_rad_s REAL;
ALTER TABLE raw_sensor_sample ADD COLUMN stroke_event_time_us INTEGER;
ALTER TABLE raw_sensor_sample ADD COLUMN stroke_source TEXT;
ALTER TABLE raw_sensor_sample
  ADD COLUMN stroke_events_supported INTEGER NOT NULL DEFAULT 0;
ALTER TABLE stroke ADD COLUMN firmware_events_json TEXT;
''';

/// Preserves the logical PRIMARY frame and freezes all processing provenance.
///
/// A PRIMARY notification contains left and right source observations. It is
/// neither a left nor a right frame, so storing it in `raw_sensor_frame` would
/// assign false provenance. This device-level append-only table keeps it once,
/// byte-for-byte. Session metadata is JSON by design: firmware can add fields
/// without forcing an app migration, while the format version makes every
/// snapshot interpretable.
const String _v19CompleteErcolinaLogging = '''
ALTER TABLE session ADD COLUMN data_format_version TEXT NOT NULL
  DEFAULT 'giulia.session.v1';
ALTER TABLE session ADD COLUMN app_version TEXT;
ALTER TABLE session ADD COLUMN sensor_snapshot_json TEXT NOT NULL DEFAULT '{}';
ALTER TABLE session ADD COLUMN calibration_snapshot_json TEXT NOT NULL DEFAULT '{}';
ALTER TABLE session ADD COLUMN battery_start_json TEXT NOT NULL DEFAULT '{}';
ALTER TABLE session ADD COLUMN battery_end_json TEXT NOT NULL DEFAULT '{}';
ALTER TABLE session ADD COLUMN data_quality_json TEXT;
ALTER TABLE stroke ADD COLUMN sides_json TEXT;
ALTER TABLE raw_sensor_sample ADD COLUMN source_epoch INTEGER;
ALTER TABLE raw_sensor_sample ADD COLUMN mapped_time_us INTEGER;
ALTER TABLE raw_sensor_sample ADD COLUMN status_flags INTEGER;
ALTER TABLE raw_sensor_sample ADD COLUMN position_m REAL;
ALTER TABLE raw_sensor_sample ADD COLUMN optical_raw INTEGER;
ALTER TABLE raw_sensor_sample ADD COLUMN optical_min INTEGER;
ALTER TABLE raw_sensor_sample ADD COLUMN optical_max INTEGER;
ALTER TABLE raw_sensor_sample ADD COLUMN hall_passes INTEGER;
ALTER TABLE raw_sensor_sample ADD COLUMN flywheel_revolutions INTEGER;
ALTER TABLE raw_sensor_sample ADD COLUMN stroke_counter INTEGER;
ALTER TABLE raw_sensor_sample ADD COLUMN battery_mv INTEGER;
ALTER TABLE raw_sensor_sample ADD COLUMN missed_samples INTEGER;
ALTER TABLE raw_sensor_sample ADD COLUMN adc_errors INTEGER;

CREATE TABLE raw_device_frame (
  session_id TEXT NOT NULL REFERENCES session(id),
  ordinal INTEGER NOT NULL,
  device_id TEXT NOT NULL REFERENCES device(id),
  received_at_monotonic_us INTEGER NOT NULL,
  payload BLOB NOT NULL,
  decoder_version TEXT NOT NULL,
  source_channel TEXT NOT NULL,
  decode_valid INTEGER NOT NULL,
  failure_code TEXT,
  decoded_device_time_us INTEGER,
  decoded_sequence INTEGER,
  stream_epoch INTEGER,
  schema_id INTEGER,
  envelope_flags INTEGER,
  PRIMARY KEY (session_id, ordinal)
);
CREATE INDEX idx_raw_device_frame_arrival
  ON raw_device_frame(session_id, received_at_monotonic_us, ordinal);
CREATE TRIGGER trg_raw_device_frame_no_update
BEFORE UPDATE ON raw_device_frame
BEGIN
  SELECT RAISE(ABORT, 'raw_device_frame ist eine Rohbeobachtung: kein UPDATE');
END;
''';

/// Preserves the firmware's mechanical pull phase for deterministic replay.
const String _v18RawPullState = '''
ALTER TABLE raw_sensor_sample ADD COLUMN pulling INTEGER;
''';

/// Introduces the durable centre of GIULIA Intelligence.
///
/// External providers remain immutable observations. [canonical_activity]
/// groups provider copies of the same real workout and points at exactly one
/// preferred session, so a Garmin recording that also appears in Strava does
/// not double the athlete's load. The provider rows remain available for
/// provenance and a later policy change.
///
/// Athlete state is snapshot based. A chat reads [athlete_state_current]
/// instead of reconstructing the athlete from scratch. Raw-data changes only
/// mark the state dirty; the deterministic feature engine creates the next
/// immutable snapshot at the application boundary.
const String _v17CanonicalActivitiesAndAthleteState = '''
CREATE TABLE canonical_activity (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organization(id),
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  sport TEXT NOT NULL,
  started_at_utc_us INTEGER NOT NULL,
  elapsed_seconds INTEGER NOT NULL,
  distance_metres REAL,
  preferred_provider_id TEXT NOT NULL,
  preferred_source_id TEXT NOT NULL,
  preferred_session_id TEXT NOT NULL UNIQUE REFERENCES session(id),
  created_at_utc_us INTEGER NOT NULL,
  updated_at_utc_us INTEGER NOT NULL
);
CREATE INDEX idx_canonical_activity_match
  ON canonical_activity(
    organization_id, athlete_id, sport, started_at_utc_us
  );

CREATE TABLE canonical_activity_source (
  organization_id TEXT NOT NULL REFERENCES organization(id),
  provider_id TEXT NOT NULL,
  source_id TEXT NOT NULL,
  canonical_activity_id TEXT NOT NULL REFERENCES canonical_activity(id),
  session_id TEXT NOT NULL UNIQUE REFERENCES session(id),
  authority_rank INTEGER NOT NULL,
  linked_at_utc_us INTEGER NOT NULL,
  PRIMARY KEY (organization_id, provider_id, source_id)
);
CREATE INDEX idx_canonical_source_activity
  ON canonical_activity_source(canonical_activity_id, authority_rank);

-- Every v16 import was canonical because cross-provider matching did not yet
-- exist. This lossless migration preserves that fact and its selected session.
INSERT INTO canonical_activity(
  id, organization_id, athlete_id, sport, started_at_utc_us,
  elapsed_seconds, distance_metres, preferred_provider_id,
  preferred_source_id, preferred_session_id, created_at_utc_us,
  updated_at_utc_us)
SELECT 'canonical-v16-' || imported.rowid,
       imported.organization_id,
       imported.athlete_id,
       COALESCE(training.movement_type, 'generic'),
       training.started_at_utc_us,
       CAST(MAX(0, training.ended_at_utc_us - training.started_at_utc_us)
            / 1000000 AS INTEGER),
       NULL,
       imported.provider_id,
       imported.source_id,
       imported.session_id,
       imported.imported_at_utc_us,
       imported.imported_at_utc_us
  FROM external_activity_import imported
  JOIN session training ON training.id = imported.session_id;

INSERT INTO canonical_activity_source(
  organization_id, provider_id, source_id, canonical_activity_id,
  session_id, authority_rank, linked_at_utc_us)
SELECT imported.organization_id,
       imported.provider_id,
       imported.source_id,
       'canonical-v16-' || imported.rowid,
       imported.session_id,
       CASE imported.provider_id
         WHEN 'garmin' THEN 100
         WHEN 'strava' THEN 60
         ELSE 40
       END,
       imported.imported_at_utc_us
  FROM external_activity_import imported;

CREATE TABLE athlete_state_snapshot (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organization(id),
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  as_of_utc_us INTEGER NOT NULL,
  calculated_at_utc_us INTEGER NOT NULL,
  feature_engine_version TEXT NOT NULL,
  input_fingerprint TEXT NOT NULL,
  state_json TEXT NOT NULL,
  UNIQUE (athlete_id, feature_engine_version, input_fingerprint, as_of_utc_us)
);
CREATE INDEX idx_athlete_state_history
  ON athlete_state_snapshot(athlete_id, as_of_utc_us DESC);
CREATE TRIGGER trg_athlete_state_snapshot_no_update
BEFORE UPDATE ON athlete_state_snapshot
BEGIN
  SELECT RAISE(ABORT, 'athlete_state_snapshot ist unveraenderlich');
END;
CREATE TRIGGER trg_athlete_state_snapshot_no_delete
BEFORE DELETE ON athlete_state_snapshot
BEGIN
  SELECT RAISE(ABORT, 'athlete_state_snapshot ist unveraenderlich');
END;

CREATE TABLE athlete_state_current (
  athlete_id TEXT PRIMARY KEY REFERENCES athlete(id),
  organization_id TEXT NOT NULL REFERENCES organization(id),
  snapshot_id TEXT NOT NULL UNIQUE REFERENCES athlete_state_snapshot(id),
  updated_at_utc_us INTEGER NOT NULL
);

CREATE TABLE athlete_state_refresh_queue (
  athlete_id TEXT PRIMARY KEY REFERENCES athlete(id),
  organization_id TEXT NOT NULL REFERENCES organization(id),
  requested_at_utc_us INTEGER NOT NULL,
  reason TEXT NOT NULL
);

INSERT INTO athlete_state_refresh_queue(
  athlete_id, organization_id, requested_at_utc_us, reason)
SELECT id, organization_id, updated_at_utc_us, 'schema_v17'
  FROM athlete WHERE archived_at_utc_us IS NULL;

CREATE TRIGGER trg_state_dirty_session_insert
AFTER INSERT ON session
BEGIN
  INSERT INTO athlete_state_refresh_queue(
    athlete_id, organization_id, requested_at_utc_us, reason)
  VALUES (NEW.athlete_id, NEW.organization_id, NEW.updated_at_utc_us, 'session')
  ON CONFLICT(athlete_id) DO UPDATE SET
    requested_at_utc_us = excluded.requested_at_utc_us,
    reason = excluded.reason;
END;
CREATE TRIGGER trg_state_dirty_session_update
AFTER UPDATE ON session
BEGIN
  INSERT INTO athlete_state_refresh_queue(
    athlete_id, organization_id, requested_at_utc_us, reason)
  VALUES (NEW.athlete_id, NEW.organization_id, NEW.updated_at_utc_us, 'session')
  ON CONFLICT(athlete_id) DO UPDATE SET
    requested_at_utc_us = excluded.requested_at_utc_us,
    reason = excluded.reason;
END;
CREATE TRIGGER trg_state_dirty_test_insert
AFTER INSERT ON performance_test
BEGIN
  INSERT INTO athlete_state_refresh_queue(
    athlete_id, organization_id, requested_at_utc_us, reason)
  VALUES (
    NEW.athlete_id, NEW.organization_id, NEW.updated_at_utc_us,
    'performance_test'
  )
  ON CONFLICT(athlete_id) DO UPDATE SET
    requested_at_utc_us = excluded.requested_at_utc_us,
    reason = excluded.reason;
END;
CREATE TRIGGER trg_state_dirty_test_update
AFTER UPDATE ON performance_test
BEGIN
  INSERT INTO athlete_state_refresh_queue(
    athlete_id, organization_id, requested_at_utc_us, reason)
  VALUES (
    NEW.athlete_id, NEW.organization_id, NEW.updated_at_utc_us,
    'performance_test'
  )
  ON CONFLICT(athlete_id) DO UPDATE SET
    requested_at_utc_us = excluded.requested_at_utc_us,
    reason = excluded.reason;
END;
CREATE TRIGGER trg_state_dirty_threshold
AFTER INSERT ON threshold_result
BEGIN
  INSERT INTO athlete_state_refresh_queue(
    athlete_id, organization_id, requested_at_utc_us, reason)
  VALUES (
    NEW.athlete_id,
    (SELECT organization_id FROM athlete WHERE id = NEW.athlete_id),
    NEW.computed_at_utc_us,
    'lala_threshold'
  )
  ON CONFLICT(athlete_id) DO UPDATE SET
    requested_at_utc_us = excluded.requested_at_utc_us,
    reason = excluded.reason;
END;
CREATE TRIGGER trg_state_dirty_observation
AFTER INSERT ON observation
BEGIN
  INSERT INTO athlete_state_refresh_queue(
    athlete_id, organization_id, requested_at_utc_us, reason)
  VALUES (
    NEW.athlete_id,
    (SELECT organization_id FROM athlete WHERE id = NEW.athlete_id),
    NEW.observed_at_utc_us,
    'observation'
  )
  ON CONFLICT(athlete_id) DO UPDATE SET
    requested_at_utc_us = excluded.requested_at_utc_us,
    reason = excluded.reason;
END;
CREATE TRIGGER trg_state_dirty_attribute
AFTER INSERT ON athlete_attribute
BEGIN
  INSERT INTO athlete_state_refresh_queue(
    athlete_id, organization_id, requested_at_utc_us, reason)
  VALUES (
    NEW.athlete_id,
    (SELECT organization_id FROM athlete WHERE id = NEW.athlete_id),
    NEW.recorded_at_utc_us,
    'athlete_attribute'
  )
  ON CONFLICT(athlete_id) DO UPDATE SET
    requested_at_utc_us = excluded.requested_at_utc_us,
    reason = excluded.reason;
END;
''';

/// Preserves imported activity files and their normalized measurement curve.
///
/// A completed Garmin activity is both useful training history and provenance
/// for a lactate test. The session row makes it visible to existing load and
/// readiness tools; these tables retain what the external system actually
/// supplied, including the exact source file where one exists. A provider
/// source may occur once per organization, preventing a second tap from
/// creating a duplicate training session.
const String _v16ExternalActivities = '''
CREATE TABLE external_activity_import (
  organization_id TEXT NOT NULL REFERENCES organization(id),
  provider_id TEXT NOT NULL,
  source_id TEXT NOT NULL,
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  session_id TEXT NOT NULL UNIQUE REFERENCES session(id),
  file_name TEXT,
  raw_file BLOB,
  raw_sha256 TEXT,
  decoder_version TEXT NOT NULL,
  warnings_json TEXT NOT NULL DEFAULT '[]',
  imported_at_utc_us INTEGER NOT NULL,
  PRIMARY KEY (organization_id, provider_id, source_id)
);
CREATE INDEX idx_external_activity_athlete
  ON external_activity_import(athlete_id, imported_at_utc_us);
CREATE TRIGGER trg_external_activity_import_no_update
BEFORE UPDATE ON external_activity_import
BEGIN
  SELECT RAISE(ABORT, 'external_activity_import ist unveraenderlich');
END;

CREATE TABLE external_activity_sample (
  organization_id TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  source_id TEXT NOT NULL,
  ordinal INTEGER NOT NULL,
  recorded_at_utc_us INTEGER NOT NULL,
  load_value REAL NOT NULL,
  load_unit TEXT NOT NULL,
  heart_rate_bpm INTEGER,
  cadence_per_minute INTEGER,
  PRIMARY KEY (organization_id, provider_id, source_id, ordinal),
  FOREIGN KEY (organization_id, provider_id, source_id)
    REFERENCES external_activity_import(organization_id, provider_id, source_id)
);
CREATE INDEX idx_external_activity_sample_time
  ON external_activity_sample(
    organization_id, provider_id, source_id, recorded_at_utc_us
  );
CREATE TRIGGER trg_external_activity_sample_no_update
BEFORE UPDATE ON external_activity_sample
BEGIN
  SELECT RAISE(ABORT, 'external_activity_sample ist eine Rohbeobachtung');
END;
''';

/// Makes the transport boundary durable and interrupted recordings explicit.
///
/// Earlier versions stored decoded sensor samples during an Ercolina test,
/// but not rejected BLE frames and not the raw stream of free training. A
/// malformed frame therefore looked exactly like a radio gap. The frame table
/// keeps the physical observation independently of decoder success; the
/// existing `raw_sensor_sample` remains the normalized, replayable record.
///
/// `recording_state` also removes an ambiguity from `ended_at_utc_us IS NULL`:
/// after a process restart an open row is now visibly interrupted and can be
/// resumed or finalized deliberately. Existing completed sessions stay
/// completed; existing open sessions are conservatively marked interrupted.
const String _v15LosslessRecordingAndRecovery = '''
ALTER TABLE session ADD COLUMN recording_state TEXT NOT NULL DEFAULT 'completed';
ALTER TABLE session ADD COLUMN last_checkpoint_utc_us INTEGER;
UPDATE session
   SET recording_state = CASE
         WHEN ended_at_utc_us IS NULL THEN 'interrupted'
         ELSE 'completed'
       END,
       last_checkpoint_utc_us = COALESCE(ended_at_utc_us, updated_at_utc_us);

CREATE TABLE raw_sensor_frame (
  session_id TEXT NOT NULL REFERENCES session(id),
  ordinal INTEGER NOT NULL,
  sensor_id TEXT NOT NULL REFERENCES sensor(id),
  side TEXT NOT NULL,
  received_at_monotonic_us INTEGER NOT NULL,
  payload BLOB NOT NULL,
  decoder_version TEXT NOT NULL,
  decode_valid INTEGER NOT NULL,
  failure_code TEXT,
  decoded_device_time_us INTEGER,
  decoded_sequence INTEGER,
  PRIMARY KEY (session_id, ordinal)
);
CREATE INDEX idx_raw_frame_arrival
  ON raw_sensor_frame(session_id, received_at_monotonic_us, ordinal);
CREATE TRIGGER trg_raw_frame_no_update BEFORE UPDATE ON raw_sensor_frame
BEGIN
  SELECT RAISE(ABORT, 'raw_sensor_frame ist eine Rohbeobachtung: kein UPDATE');
END;

CREATE TABLE session_event (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES session(id),
  kind TEXT NOT NULL,
  occurred_at_utc_us INTEGER NOT NULL,
  occurred_at_monotonic_us INTEGER,
  detail TEXT
);
CREATE INDEX idx_session_event_time
  ON session_event(session_id, occurred_at_utc_us, id);
CREATE TRIGGER trg_session_event_no_update BEFORE UPDATE ON session_event
BEGIN
  SELECT RAISE(ABORT, 'session_event ist unveraenderlich');
END;

ALTER TABLE heart_rate_sample ADD COLUMN contact_detected INTEGER;

ALTER TABLE calibration ADD COLUMN calibration_type TEXT NOT NULL
  DEFAULT 'force_linear';
ALTER TABLE calibration ADD COLUMN parameters_json TEXT NOT NULL DEFAULT '{}';
ALTER TABLE calibration ADD COLUMN valid_until_utc_us INTEGER;

UPDATE device SET kind = 'simulator' WHERE id = 'ercolina-simulator';
''';

/// Repariert den ersten echten Scout-Import und bewahrt künftig seine
/// Qualitätsdaten vollständig auf.
///
/// Der Scout verwendet 0xFF als «kein Puls» und speichert seine lokale
/// Wanduhr ohne Zeitzone. Version 13 hatte beides zu wörtlich gelesen: 255
/// Schläge/min gelangten in die Auswertung und Ortszeit wurde als UTC
/// gespeichert. Nur eindeutig über die Importtabelle belegte Scout-Tests
/// werden korrigiert. Rohbytes und frühere Berechnungsläufe bleiben erhalten;
/// LaLa hängt beim nächsten Start einen reparierten Lauf an.
const String _v14RepairAndEnrichScoutImports = '''
ALTER TABLE external_measurement_import ADD COLUMN measured_at_utc_us INTEGER;
ALTER TABLE external_measurement_import ADD COLUMN sequence_number INTEGER;
ALTER TABLE external_measurement_import ADD COLUMN heart_rate_bpm INTEGER;
ALTER TABLE external_measurement_import ADD COLUMN temperature_c REAL;

UPDATE test_stage
   SET heart_rate_bpm = NULL
 WHERE heart_rate_bpm = 255
   AND test_id IN (
     SELECT DISTINCT test_id FROM external_measurement_import
      WHERE provider_id = 'lactate_scout'
   );

DROP TRIGGER trg_lactate_sample_no_update;
UPDATE lactate_sample
   SET sampled_at_utc_us = CAST(
     strftime('%s', datetime(sampled_at_utc_us / 1000000, 'unixepoch'), 'utc')
     AS INTEGER
   ) * 1000000
 WHERE test_id IN (
   SELECT DISTINCT test_id FROM external_measurement_import
    WHERE provider_id = 'lactate_scout'
 );
CREATE TRIGGER trg_lactate_sample_no_update BEFORE UPDATE OF
  test_id, stage_id, athlete_id, sampled_at_utc_us, lactate_mmol_l,
  sample_site, context
ON lactate_sample
BEGIN
  SELECT RAISE(ABORT, 'lactate_sample ist eine Rohmessung: kein UPDATE');
END;

UPDATE observation
   SET observed_at_utc_us = CAST(
     strftime('%s', datetime(observed_at_utc_us / 1000000, 'unixepoch'), 'utc')
     AS INTEGER
   ) * 1000000
 WHERE test_id IN (
   SELECT DISTINCT test_id FROM external_measurement_import
    WHERE provider_id = 'lactate_scout'
 ) AND type = 'lactate';

UPDATE performance_test
   SET started_at_utc_us = (
         SELECT MIN(sampled_at_utc_us) FROM lactate_sample
          WHERE lactate_sample.test_id = performance_test.id
       ),
       ended_at_utc_us = (
         SELECT MAX(sampled_at_utc_us) FROM lactate_sample
          WHERE lactate_sample.test_id = performance_test.id
       )
 WHERE id IN (
   SELECT DISTINCT test_id FROM external_measurement_import
    WHERE provider_id = 'lactate_scout'
 );
''';

/// Messgeräte sind keine Trainingsgeräte, und ein übertragener Rohwert hat
/// genau eine dauerhafte Identität.
///
/// Bis hierher bedeutete jede Zeile in `device` stillschweigend «Ercolina».
/// Das wird falsch, sobald ein Lactate Scout zum Arbeitsbereich gehört: Er ist
/// Hardware, darf aber niemals beim Start einer Trainingseinheit angeboten
/// werden. Bestehende Geräte bleiben durch den Default Trainingsgeräte.
///
/// Die zweite Tabelle ist der Doppelimport-Schutz. `source_id` enthält beim
/// Scout Gerätekennung, Speicherplatz und Messzeit; zusammen mit dem Anbieter
/// erkennt sie denselben Rohwert auch nach einem Neustart wieder. Der
/// Originalwert bleibt weiterhin in `lactate_sample` und `observation`.
const String _v13DeviceKindsAndExternalImports = '''
ALTER TABLE device ADD COLUMN kind TEXT NOT NULL DEFAULT 'training';
CREATE INDEX idx_device_org_kind ON device(organization_id, kind);

CREATE TABLE external_measurement_import (
  provider_id TEXT NOT NULL,
  source_id TEXT NOT NULL,
  organization_id TEXT NOT NULL REFERENCES organization(id),
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  test_id TEXT NOT NULL REFERENCES performance_test(id),
  raw_payload_hex TEXT,
  imported_at_utc_us INTEGER NOT NULL,
  PRIMARY KEY (provider_id, source_id)
);
CREATE INDEX idx_external_import_test
  ON external_measurement_import(test_id, provider_id, source_id);
CREATE INDEX idx_external_import_athlete
  ON external_measurement_import(athlete_id, imported_at_utc_us);
''';

/// Phase J — eine Einheit weiss, wie lange wirklich trainiert wurde.
///
/// Bisher standen an einer Sitzung Beginn und Ende. Wer dazwischen zwanzig
/// Minuten pausiert — Laktatentnahme, Telefon, Gespräch —, hatte trotzdem eine
/// «45-Minuten-Einheit». Die Pausenzeit lag nur im Arbeitsspeicher des
/// Bildschirms und war nach dem Beenden verloren.
///
/// Das ist die Voraussetzung dafür, dass die Zusammenfassung **aus dem Archiv**
/// entsteht und nicht aus dem, was gerade noch im Speicher liegt. Sonst
/// bekämen Live- und Archivansicht zwei Rechenwege, und der Unterschied fiele
/// erst auf, wenn ihn jemand bemerkt.
const String _v12SessionPauses = '''
ALTER TABLE session ADD COLUMN paused_us INTEGER NOT NULL DEFAULT 0;
''';

/// Phase I — Beobachtungen bekommen einen Ort.
///
/// ## MIGRATIONSSCHULD
///
/// `lactate_sample` und `test_stage.rpe` bleiben bestehen und werden weiter
/// beschrieben. Das ist ein **Zwischenzustand**, kein Endzustand:
///
/// * Die Auswertung liest weiter aus `lactate_sample`.
/// * Jeder neue Wert wird zusätzlich als Beobachtung geschrieben
///   (`DiagnosticsRepository.addLactateSample`).
/// * Der Nachweis, dass beide Wege dasselbe ergeben, steht in
///   `test/observation/lactate_migration_test.dart`.
///
/// Offen bleibt: den Lesepfad umlegen, den Altschreibpfad schliessen, die
/// Tabelle entfernen. Bis dahin gilt für jede Änderung an Laktatdaten: **beide
/// Speicher bedienen**. Ein Test hält fest, dass es nur eine Stelle im
/// Programm gibt, die in `lactate_sample` schreibt.
///
/// ## Wer einen Athleten oder Mandanten entfernt
///
/// muss `observation` mitnehmen. Einen solchen Pfad gibt es im Programm heute
/// nicht — nur die einmalige Migration `_v9RemoveDemonstrationWorkspace`, die
/// vor dieser Tabelle lief und sie deshalb nicht kennen konnte. Wird je einer
/// gebaut, gehören Beobachtungen in dieselbe Aufräumliste wie Sitzungen,
/// Tests und Proben; `test/demonstration_removal_test.dart` zeigt den Fall.
///
/// Laktat hing bisher an `performance_test`, RPE an `test_stage`, und für eine
/// normale Trainingseinheit gab es überhaupt keinen Ort: Wer während einer
/// Schwelleneinheit zwei Werte nahm, konnte sie nicht festhalten.
///
/// Diese Migration legt die Tabelle an und **kopiert** den Bestand hinein.
/// Kopiert, nicht verschoben: `lactate_sample` und `test_stage.rpe` bleiben
/// unverändert lesbar, und die Auswertung liest bis auf Weiteres von dort.
/// Erst wenn ein Regressionsnachweis zeigt, dass beide Wege dieselben
/// Stufenzuordnungen, Werte, Reihenfolgen, Zeitpunkte, Testzuordnungen,
/// Schwellen und Berichte ergeben, wird der Schreibpfad umgelegt — und die
/// alte Tabelle fällt zuletzt.
///
/// Zwei Dinge werden bewusst **nicht** mitkopiert:
///
/// * Die Korrekturüberlagerung aus `diagnostic_stage_correction`. Eine
///   Beobachtung ist, was beobachtet wurde; eine Korrektur ist ein späterer
///   diagnostischer Akt und bleibt, wo sie ist. Beim Lesen wird sie wie bisher
///   darübergelegt.
/// * Eine Anreicherung um `time_since_load_end_s`. Der Altbestand kennt diesen
///   Bezug nicht, und ihn zu schätzen hiesse, eine Zahl zu erfinden, die
///   später wie eine gemessene aussieht.
const String _v11Observations = '''
CREATE TABLE observation (
  id TEXT PRIMARY KEY,
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  observed_at_utc_us INTEGER NOT NULL,
  type TEXT NOT NULL,
  value REAL,
  text_value TEXT,
  unit TEXT,
  source TEXT NOT NULL DEFAULT 'manual',
  quality TEXT NOT NULL DEFAULT 'recorded',
  recorded_by_user_id TEXT REFERENCES app_user(id),
  time_since_load_end_s INTEGER,
  occasion TEXT,
  sample_site TEXT,
  session_id TEXT REFERENCES session(id),
  interval_record_id TEXT REFERENCES interval_record(id),
  test_id TEXT REFERENCES performance_test(id),
  test_stage_id TEXT REFERENCES test_stage(id),
  legacy_lactate_sample_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);
CREATE INDEX idx_observation_test ON observation(test_id, observed_at_utc_us);
CREATE INDEX idx_observation_session
  ON observation(session_id, observed_at_utc_us);
CREATE INDEX idx_observation_athlete
  ON observation(athlete_id, observed_at_utc_us);

INSERT INTO observation(
  id, athlete_id, observed_at_utc_us, type, value, text_value, unit,
  source, quality, recorded_by_user_id, occasion, sample_site,
  test_id, test_stage_id, legacy_lactate_sample_id)
SELECT
  'obs-lactate-' || l.id,
  COALESCE(l.athlete_id, p.athlete_id),
  l.sampled_at_utc_us,
  'lactate',
  l.lactate_mmol_l,
  l.note,
  'mmol/l',
  'manual',
  'recorded',
  l.entered_by_user_id,
  l.context,
  l.sample_site,
  l.test_id,
  l.stage_id,
  l.id
FROM lactate_sample l
JOIN performance_test p ON p.id = l.test_id;

INSERT INTO observation(
  id, athlete_id, observed_at_utc_us, type, value, unit, source, quality,
  occasion, test_id, test_stage_id)
SELECT
  'obs-rpe-' || s.id,
  p.athlete_id,
  COALESCE(s.ended_at_utc_us, s.started_at_utc_us, p.started_at_utc_us),
  'rpe',
  s.rpe,
  '',
  'manual',
  'recorded',
  'stage',
  s.test_id,
  s.id
FROM test_stage s
JOIN performance_test p ON p.id = s.test_id
WHERE s.rpe IS NOT NULL;
''';

/// Phase H — wer verantwortet die Trainingsplanung.
///
/// Zwei Dinge, und beide bewusst klein gehalten:
///
/// **`coaching_mode`** ist eine historisierte Konfiguration je Athlet und
/// Organisation, gebaut nach dem Muster von `athlete_attribute`: einfügend,
/// mit Gültigkeitszeitpunkt, nie überschreibend. Damit ist «seit wann wird
/// dieser Mensch von einem Trainer geführt» beantwortbar, ohne dass jemand
/// eigens ein Protokoll dafür anlegt.
///
/// **`coach_athlete_assignment`** wird erweitert statt ersetzt. Die Tabelle
/// trägt seit v3 die Zugriffsentscheidung; eine zweite Beziehung daneben
/// ergäbe zwei Wahrheiten über die Frage, wer wessen Daten sehen darf.
///
/// Die Datenübernahme ist so gewählt, dass **niemand Zugriff verliert**:
/// Bestehende Zuordnungen bekommen alle Freigaben, weil sie heute faktisch
/// alles sehen. Widerrufene werden als beendet markiert — derselbe Zustand,
/// den `revoked_at_utc_us` schon ausdrückt, nur jetzt benannt.
const String _v10CoachingConfiguration = '''
CREATE TABLE coaching_mode (
  id TEXT PRIMARY KEY,
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  organization_id TEXT NOT NULL REFERENCES organization(id),
  mode TEXT NOT NULL,
  effective_from_utc_us INTEGER NOT NULL,
  recorded_at_utc_us INTEGER NOT NULL,
  recorded_by_user_id TEXT REFERENCES app_user(id),
  sync_state TEXT NOT NULL DEFAULT 'pending'
);
CREATE INDEX idx_coaching_mode_athlete
  ON coaching_mode(athlete_id, organization_id, effective_from_utc_us);

CREATE TRIGGER trg_coaching_mode_no_delete BEFORE DELETE ON coaching_mode
BEGIN
  SELECT RAISE(ABORT, 'coaching_mode ist unveraenderlich: kein DELETE');
END;
CREATE TRIGGER trg_coaching_mode_no_update BEFORE UPDATE OF
  athlete_id, organization_id, mode, effective_from_utc_us, recorded_at_utc_us
ON coaching_mode
BEGIN
  SELECT RAISE(ABORT, 'coaching_mode ist unveraenderlich: kein UPDATE');
END;

ALTER TABLE coach_athlete_assignment ADD COLUMN status TEXT NOT NULL
  DEFAULT 'active';
-- Der Vorgabewert trägt die bisherige Bedeutung: Eine Zuordnung ohne
-- ausgesprochene Freigaben ist eine vollständige, so wie sie es seit v3 war.
-- Das gilt nicht nur für vorhandene Zeilen, sondern auch für jeden Schreiber,
-- der die Spalte nicht kennt — etwa das ältere `assignCoach`.
ALTER TABLE coach_athlete_assignment ADD COLUMN permissions TEXT NOT NULL
  DEFAULT 'viewSessions,viewPerformance,viewDiagnostics,viewLactate,viewRpe,assignWorkouts,manageCalendar,commentSessions';
ALTER TABLE coach_athlete_assignment ADD COLUMN updated_at_utc_us INTEGER
  NOT NULL DEFAULT 0;
ALTER TABLE coach_athlete_assignment ADD COLUMN sync_state TEXT NOT NULL
  DEFAULT 'pending';

UPDATE coach_athlete_assignment
   SET status = 'ended'
 WHERE revoked_at_utc_us IS NOT NULL;

UPDATE coach_athlete_assignment
   SET updated_at_utc_us = assigned_at_utc_us
 WHERE updated_at_utc_us = 0;

UPDATE coach_athlete_assignment
   SET permissions = 'viewSessions,viewPerformance,viewDiagnostics,'
                  || 'viewLactate,viewRpe,assignWorkouts,manageCalendar,'
                  || 'commentSessions'
 WHERE permissions IS NULL OR permissions = '';
''';

const String _v1PlatformSchema = '''
CREATE TABLE organization (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  kind TEXT NOT NULL,
  created_at_utc_us INTEGER NOT NULL,
  updated_at_utc_us INTEGER NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE app_user (
  id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  email TEXT,
  created_at_utc_us INTEGER NOT NULL,
  updated_at_utc_us INTEGER NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE athlete (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organization(id),
  user_id TEXT REFERENCES app_user(id),
  name TEXT NOT NULL,
  birth_year INTEGER,
  sex TEXT,
  is_minor INTEGER NOT NULL DEFAULT 0,
  consent_recorded_at_utc_us INTEGER,
  created_at_utc_us INTEGER NOT NULL,
  updated_at_utc_us INTEGER NOT NULL,
  archived_at_utc_us INTEGER,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);
CREATE INDEX idx_athlete_org ON athlete(organization_id);

CREATE TABLE team (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organization(id),
  name TEXT NOT NULL,
  age_class TEXT,
  season TEXT,
  created_at_utc_us INTEGER NOT NULL,
  updated_at_utc_us INTEGER NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);
CREATE INDEX idx_team_org ON team(organization_id);

CREATE TABLE membership (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organization(id),
  user_id TEXT NOT NULL REFERENCES app_user(id),
  role TEXT NOT NULL,
  team_id TEXT REFERENCES team(id),
  granted_at_utc_us INTEGER NOT NULL,
  revoked_at_utc_us INTEGER
);
CREATE INDEX idx_membership_user ON membership(user_id, organization_id);

CREATE TABLE team_athlete (
  team_id TEXT NOT NULL REFERENCES team(id),
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  joined_at_utc_us INTEGER NOT NULL,
  left_at_utc_us INTEGER,
  PRIMARY KEY (team_id, athlete_id, joined_at_utc_us)
);

CREATE TABLE coach_athlete_assignment (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organization(id),
  coach_user_id TEXT NOT NULL REFERENCES app_user(id),
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  assigned_at_utc_us INTEGER NOT NULL,
  revoked_at_utc_us INTEGER
);
CREATE INDEX idx_assignment_coach
  ON coach_athlete_assignment(coach_user_id, athlete_id);

CREATE TABLE device (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organization(id),
  ble_identifier TEXT NOT NULL,
  display_name TEXT NOT NULL,
  location TEXT,
  model TEXT,
  hardware_version TEXT,
  firmware_version TEXT,
  serial_number TEXT,
  last_seen_at_utc_us INTEGER,
  created_at_utc_us INTEGER NOT NULL,
  updated_at_utc_us INTEGER NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);
CREATE INDEX idx_device_org ON device(organization_id);

CREATE TABLE sensor (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES device(id),
  side TEXT NOT NULL,
  service_uuid TEXT NOT NULL,
  measurement_uuid TEXT NOT NULL,
  hardware_version TEXT,
  firmware_version TEXT,
  UNIQUE (device_id, side)
);

CREATE TABLE calibration (
  id TEXT PRIMARY KEY,
  sensor_id TEXT NOT NULL REFERENCES sensor(id),
  created_at_utc_us INTEGER NOT NULL,
  effective_from_utc_us INTEGER NOT NULL,
  force_offset_n REAL NOT NULL,
  force_scale REAL NOT NULL,
  protocol_version TEXT NOT NULL,
  performed_by_user_id TEXT REFERENCES app_user(id),
  valid INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX idx_calibration_sensor
  ON calibration(sensor_id, effective_from_utc_us);

CREATE TABLE athlete_attribute (
  id TEXT PRIMARY KEY,
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  attribute TEXT NOT NULL,
  value_numeric REAL,
  value_text TEXT,
  unit TEXT,
  effective_from_utc_us INTEGER NOT NULL,
  recorded_at_utc_us INTEGER NOT NULL,
  recorded_by_user_id TEXT REFERENCES app_user(id),
  source TEXT NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);
CREATE INDEX idx_attribute_history
  ON athlete_attribute(athlete_id, attribute, effective_from_utc_us);

CREATE TABLE workout (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organization(id),
  athlete_id TEXT REFERENCES athlete(id),
  created_by_user_id TEXT REFERENCES app_user(id),
  name TEXT NOT NULL,
  category TEXT,
  is_template INTEGER NOT NULL DEFAULT 0,
  definition_json TEXT NOT NULL,
  created_at_utc_us INTEGER NOT NULL,
  updated_at_utc_us INTEGER NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE workout_step (
  id TEXT PRIMARY KEY,
  workout_id TEXT NOT NULL REFERENCES workout(id),
  ordinal INTEGER NOT NULL,
  kind TEXT NOT NULL,
  completion_type TEXT NOT NULL,
  completion_target REAL NOT NULL,
  targets_json TEXT NOT NULL
);

CREATE TABLE session (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organization(id),
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  device_id TEXT REFERENCES device(id),
  team_id TEXT REFERENCES team(id),
  workout_id TEXT REFERENCES workout(id),
  recorded_by_user_id TEXT REFERENCES app_user(id),
  started_at_utc_us INTEGER NOT NULL,
  ended_at_utc_us INTEGER,
  movement_type TEXT,
  resistance_setting TEXT,
  algorithm_version TEXT NOT NULL,
  processing_config_json TEXT NOT NULL,
  notes TEXT,
  updated_at_utc_us INTEGER NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);
CREATE INDEX idx_session_athlete ON session(athlete_id, started_at_utc_us);
CREATE INDEX idx_session_org ON session(organization_id, started_at_utc_us);

CREATE TABLE interval_record (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES session(id),
  step_id TEXT REFERENCES workout_step(id),
  ordinal INTEGER NOT NULL,
  started_at_us INTEGER NOT NULL,
  ended_at_us INTEGER,
  metrics_json TEXT NOT NULL
);

CREATE TABLE raw_sensor_sample (
  session_id TEXT NOT NULL REFERENCES session(id),
  sensor_id TEXT NOT NULL REFERENCES sensor(id),
  device_time_us INTEGER NOT NULL,
  received_at_monotonic_us INTEGER NOT NULL,
  sequence INTEGER NOT NULL,
  payload BLOB,
  force_n REAL,
  velocity_m_s REAL,
  power_w REAL,
  battery_percent INTEGER,
  parser_valid INTEGER NOT NULL,
  PRIMARY KEY (session_id, sensor_id, device_time_us, sequence)
);

CREATE TABLE derived_sample (
  session_id TEXT NOT NULL REFERENCES session(id),
  sensor_id TEXT NOT NULL REFERENCES sensor(id),
  aligned_time_us INTEGER NOT NULL,
  calibrated_force_n REAL NOT NULL,
  calibrated_velocity_m_s REAL NOT NULL,
  calibrated_power_w REAL NOT NULL,
  filtered_force_n REAL NOT NULL,
  filtered_power_w REAL NOT NULL,
  quality TEXT NOT NULL,
  algorithm_version TEXT NOT NULL,
  PRIMARY KEY (session_id, sensor_id, aligned_time_us)
);

CREATE TABLE stroke (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES session(id),
  ordinal INTEGER NOT NULL,
  start_us INTEGER NOT NULL,
  end_us INTEGER NOT NULL,
  recovery_us INTEGER NOT NULL,
  work_j REAL NOT NULL,
  impulse_ns REAL NOT NULL,
  mean_power_w REAL NOT NULL,
  peak_power_w REAL NOT NULL,
  peak_force_n REAL NOT NULL,
  left_work_j REAL NOT NULL,
  right_work_j REAL NOT NULL,
  quality TEXT NOT NULL,
  algorithm_version TEXT NOT NULL
);
CREATE INDEX idx_stroke_session ON stroke(session_id, ordinal);

CREATE TABLE heart_rate_sample (
  session_id TEXT NOT NULL REFERENCES session(id),
  recorded_at_us INTEGER NOT NULL,
  bpm INTEGER NOT NULL,
  rr_intervals_ms BLOB,
  PRIMARY KEY (session_id, recorded_at_us)
);

CREATE TABLE session_metrics (
  session_id TEXT PRIMARY KEY REFERENCES session(id),
  calculated_at_utc_us INTEGER NOT NULL,
  algorithm_version TEXT NOT NULL,
  metrics_json TEXT NOT NULL
);

CREATE TABLE performance_test (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organization(id),
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  session_id TEXT REFERENCES session(id),
  device_id TEXT REFERENCES device(id),
  supervised_by_user_id TEXT REFERENCES app_user(id),
  protocol TEXT NOT NULL,
  protocol_version TEXT NOT NULL,
  started_at_utc_us INTEGER NOT NULL,
  ended_at_utc_us INTEGER,
  notes TEXT,
  updated_at_utc_us INTEGER NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);
CREATE INDEX idx_test_athlete ON performance_test(athlete_id, started_at_utc_us);

CREATE TABLE test_stage (
  id TEXT PRIMARY KEY,
  test_id TEXT NOT NULL REFERENCES performance_test(id),
  ordinal INTEGER NOT NULL,
  target_power_w REAL,
  duration_s REAL,
  mean_power_w REAL,
  heart_rate_bpm INTEGER,
  stroke_rate_per_min REAL,
  rpe REAL,
  completed INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX idx_stage_test ON test_stage(test_id, ordinal);

CREATE TABLE lactate_sample (
  id TEXT PRIMARY KEY,
  test_id TEXT NOT NULL REFERENCES performance_test(id),
  stage_id TEXT REFERENCES test_stage(id),
  sampled_at_utc_us INTEGER NOT NULL,
  lactate_mmol_l REAL NOT NULL,
  context TEXT NOT NULL,
  entered_by_user_id TEXT REFERENCES app_user(id)
);

CREATE TABLE threshold_result (
  id TEXT PRIMARY KEY,
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  test_id TEXT REFERENCES performance_test(id),
  threshold_type TEXT NOT NULL,
  method TEXT NOT NULL,
  method_version TEXT NOT NULL,
  power_w REAL,
  heart_rate_bpm INTEGER,
  lactate_mmol_l REAL,
  effective_at_utc_us INTEGER NOT NULL,
  computed_at_utc_us INTEGER NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);
CREATE INDEX idx_threshold_history
  ON threshold_result(athlete_id, threshold_type, method, effective_at_utc_us);

CREATE TABLE training_zone_set (
  id TEXT PRIMARY KEY,
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  basis TEXT NOT NULL,
  method TEXT NOT NULL,
  method_version TEXT NOT NULL,
  derived_from_test_id TEXT REFERENCES performance_test(id),
  effective_from_utc_us INTEGER NOT NULL,
  created_at_utc_us INTEGER NOT NULL
);
CREATE INDEX idx_zone_set_history
  ON training_zone_set(athlete_id, basis, effective_from_utc_us);

CREATE TABLE training_zone (
  id TEXT PRIMARY KEY,
  zone_set_id TEXT NOT NULL REFERENCES training_zone_set(id),
  ordinal INTEGER NOT NULL,
  name TEXT NOT NULL,
  lower_bound REAL,
  upper_bound REAL,
  unit TEXT NOT NULL
);

CREATE TABLE athlete_metric (
  id TEXT PRIMARY KEY,
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  session_id TEXT REFERENCES session(id),
  test_id TEXT REFERENCES performance_test(id),
  metric TEXT NOT NULL,
  value REAL NOT NULL,
  unit TEXT NOT NULL,
  effective_at_utc_us INTEGER NOT NULL,
  algorithm_version TEXT NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);
CREATE INDEX idx_athlete_metric_series
  ON athlete_metric(athlete_id, metric, effective_at_utc_us);

CREATE TABLE personal_record (
  id TEXT PRIMARY KEY,
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  record_type TEXT NOT NULL,
  value REAL NOT NULL,
  unit TEXT NOT NULL,
  achieved_at_utc_us INTEGER NOT NULL,
  session_id TEXT REFERENCES session(id),
  algorithm_version TEXT NOT NULL,
  superseded_at_utc_us INTEGER
);
CREATE INDEX idx_record_athlete ON personal_record(athlete_id, record_type);

CREATE TABLE audit_log (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organization(id),
  actor_user_id TEXT REFERENCES app_user(id),
  action TEXT NOT NULL,
  entity TEXT NOT NULL,
  entity_id TEXT,
  at_utc_us INTEGER NOT NULL,
  detail TEXT
);
CREATE INDEX idx_audit_org ON audit_log(organization_id, at_utc_us);

CREATE TABLE sync_outbox (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  organization_id TEXT NOT NULL,
  entity TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL,
  queued_at_utc_us INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  acknowledged_at_utc_us INTEGER
);
CREATE INDEX idx_outbox_pending ON sync_outbox(acknowledged_at_utc_us, id);
''';

/// Phase D — persistence for LaLa diagnostics.
///
/// Purely additive. The v1 tables `performance_test`, `test_stage`,
/// `lactate_sample`, `threshold_result`, `training_zone_set` and
/// `training_zone` were shaped around an Ercolina power test; they are widened
/// here so a lactate step test is representable **without any device**.
///
/// Three principles are enforced by the schema itself, not by convention:
///
/// * **Measurement and interpretation are separated.** `performance_test`,
///   `test_stage` and `lactate_sample` hold what was measured.
///   `lala_calculation_run`, `threshold_result` and `training_zone_set` hold
///   what LaLa concluded from it. The same test can be evaluated again years
///   later with a newer engine; both runs survive side by side.
/// * **Results are immutable.** Triggers reject every `DELETE` and every
///   `UPDATE` of a scientific column. Only `sync_state` stays writable, because
///   it is transport bookkeeping and not a finding.
/// * **Every result carries its own provenance**: `lala_engine_version`,
///   `method_id`, `method_version` and the input fingerprint of the exact data
///   state it was computed from.
const String _v2LalaDiagnostics = '''
-- ---------------------------------------------------------------- test head
-- Sport- and device-neutral. `device_id` stays nullable: a lactate test is a
-- complete, first-class test without Ercolina.
ALTER TABLE performance_test ADD COLUMN created_by_user_id TEXT REFERENCES app_user(id);
ALTER TABLE performance_test ADD COLUMN sport TEXT NOT NULL DEFAULT 'generic';
ALTER TABLE performance_test ADD COLUMN modality TEXT NOT NULL DEFAULT 'unspecified';
ALTER TABLE performance_test ADD COLUMN measurement_source TEXT NOT NULL DEFAULT 'manual';
ALTER TABLE performance_test ADD COLUMN status TEXT NOT NULL DEFAULT 'planned';
ALTER TABLE performance_test ADD COLUMN load_unit TEXT NOT NULL DEFAULT 'W';
ALTER TABLE performance_test ADD COLUMN stage_increment_hint REAL;
ALTER TABLE performance_test ADD COLUMN created_at_utc_us INTEGER NOT NULL DEFAULT 0;
CREATE INDEX idx_test_org ON performance_test(organization_id, started_at_utc_us);

-- ------------------------------------------------------------------- stages
-- `load_value` + `load_unit` are the sport-neutral intensity the science layer
-- consumes. The v1 power columns remain for Ercolina provenance; neither is
-- required, so a running or ski test does not carry empty cycling fields.
ALTER TABLE test_stage ADD COLUMN started_at_utc_us INTEGER;
ALTER TABLE test_stage ADD COLUMN ended_at_utc_us INTEGER;
ALTER TABLE test_stage ADD COLUMN target_value REAL;
ALTER TABLE test_stage ADD COLUMN load_value REAL;
ALTER TABLE test_stage ADD COLUMN load_unit TEXT;
ALTER TABLE test_stage ADD COLUMN speed_km_h REAL;
ALTER TABLE test_stage ADD COLUMN pace_s_per_km INTEGER;
ALTER TABLE test_stage ADD COLUMN cadence_per_min REAL;
ALTER TABLE test_stage ADD COLUMN excluded INTEGER NOT NULL DEFAULT 0;
ALTER TABLE test_stage ADD COLUMN exclusion_reason TEXT;
ALTER TABLE test_stage ADD COLUMN notes TEXT;

-- ------------------------------------------------------------------ samples
-- `stage_id` stays nullable: rest and recovery samples belong to the test but
-- to no regular stage.
ALTER TABLE lactate_sample ADD COLUMN athlete_id TEXT REFERENCES athlete(id);
ALTER TABLE lactate_sample ADD COLUMN sample_site TEXT NOT NULL DEFAULT 'unknown';
ALTER TABLE lactate_sample ADD COLUMN recorded_at_utc_us INTEGER NOT NULL DEFAULT 0;
ALTER TABLE lactate_sample ADD COLUMN note TEXT;
CREATE INDEX idx_lactate_sample_test ON lactate_sample(test_id, sampled_at_utc_us);

-- ---------------------------------------------------------- calculation run
-- One complete LaLa evaluation of one test. Insert-only and never superseded
-- in place: re-evaluating a test appends a run with a higher `run_index`.
CREATE TABLE lala_calculation_run (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organization(id),
  test_id TEXT NOT NULL REFERENCES performance_test(id),
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  triggered_by_user_id TEXT REFERENCES app_user(id),
  run_index INTEGER NOT NULL,
  lala_engine_version TEXT NOT NULL,
  engine_source_commit TEXT NOT NULL,
  created_at_utc_us INTEGER NOT NULL,
  selected_lt1_method_id TEXT,
  selected_lt2_method_id TEXT,
  input_fingerprint TEXT NOT NULL,
  output_fingerprint TEXT NOT NULL,
  core_input_hash TEXT NOT NULL,
  stage_count INTEGER NOT NULL,
  sport TEXT NOT NULL,
  load_unit TEXT NOT NULL,
  audit_record_json TEXT NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending',
  UNIQUE (test_id, run_index)
);
CREATE INDEX idx_run_test ON lala_calculation_run(test_id, run_index);
CREATE INDEX idx_run_athlete
  ON lala_calculation_run(athlete_id, created_at_utc_us);

-- ------------------------------------------------------------ threshold row
-- `load_value` + `load_unit` generalise the v1 `power_w`, which stays filled
-- whenever the unit really is watt so the existing history query keeps working.
ALTER TABLE threshold_result ADD COLUMN calculation_run_id TEXT REFERENCES lala_calculation_run(id);
ALTER TABLE threshold_result ADD COLUMN organization_id TEXT;
ALTER TABLE threshold_result ADD COLUMN lala_engine_version TEXT;
ALTER TABLE threshold_result ADD COLUMN status TEXT;
ALTER TABLE threshold_result ADD COLUMN load_value REAL;
ALTER TABLE threshold_result ADD COLUMN load_unit TEXT;
ALTER TABLE threshold_result ADD COLUMN is_selected_standard INTEGER NOT NULL DEFAULT 0;
ALTER TABLE threshold_result ADD COLUMN interpretation TEXT;
ALTER TABLE threshold_result ADD COLUMN used_stage_numbers TEXT;
ALTER TABLE threshold_result ADD COLUMN excluded_stage_numbers TEXT;
ALTER TABLE threshold_result ADD COLUMN method_details_json TEXT;
ALTER TABLE threshold_result ADD COLUMN input_data_hash TEXT;
CREATE INDEX idx_threshold_run ON threshold_result(calculation_run_id);

-- ---------------------------------------------------------------- zone sets
-- Several zone models coexist per run; none of them overwrites another.
ALTER TABLE training_zone_set ADD COLUMN calculation_run_id TEXT REFERENCES lala_calculation_run(id);
ALTER TABLE training_zone_set ADD COLUMN organization_id TEXT;
ALTER TABLE training_zone_set ADD COLUMN zone_model_id TEXT;
ALTER TABLE training_zone_set ADD COLUMN zone_model_name TEXT;
ALTER TABLE training_zone_set ADD COLUMN lala_engine_version TEXT;
ALTER TABLE training_zone_set ADD COLUMN quality TEXT;
ALTER TABLE training_zone_set ADD COLUMN load_unit TEXT;
ALTER TABLE training_zone_set ADD COLUMN sport_type TEXT;
ALTER TABLE training_zone_set ADD COLUMN issues_json TEXT;
ALTER TABLE training_zone_set ADD COLUMN sync_state TEXT NOT NULL DEFAULT 'pending';
CREATE INDEX idx_zone_set_run ON training_zone_set(calculation_run_id);

ALTER TABLE training_zone ADD COLUMN code TEXT;
ALTER TABLE training_zone ADD COLUMN physiological_domain TEXT;
ALTER TABLE training_zone ADD COLUMN lower_load_exact REAL;
ALTER TABLE training_zone ADD COLUMN upper_load_exact REAL;
ALTER TABLE training_zone ADD COLUMN lower_load_display REAL;
ALTER TABLE training_zone ADD COLUMN upper_load_display REAL;
ALTER TABLE training_zone ADD COLUMN lower_heart_rate_exact REAL;
ALTER TABLE training_zone ADD COLUMN upper_heart_rate_exact REAL;
ALTER TABLE training_zone ADD COLUMN lower_heart_rate_display INTEGER;
ALTER TABLE training_zone ADD COLUMN upper_heart_rate_display INTEGER;
ALTER TABLE training_zone ADD COLUMN lower_pace_seconds INTEGER;
ALTER TABLE training_zone ADD COLUMN upper_pace_seconds INTEGER;
ALTER TABLE training_zone ADD COLUMN provisional_boundary INTEGER NOT NULL DEFAULT 0;
ALTER TABLE training_zone ADD COLUMN boundary_rationale TEXT;
CREATE INDEX idx_zone_set_member ON training_zone(zone_set_id, ordinal);

-- ------------------------------------------------------------- immutability
-- A finding that can be edited afterwards is not a finding. `sync_state` is
-- deliberately excluded from the update guards: it carries no science.
CREATE TRIGGER trg_run_no_delete BEFORE DELETE ON lala_calculation_run
BEGIN
  SELECT RAISE(ABORT, 'lala_calculation_run ist unveraenderlich: kein DELETE');
END;
CREATE TRIGGER trg_run_no_update BEFORE UPDATE OF
  test_id, athlete_id, run_index, lala_engine_version, engine_source_commit,
  created_at_utc_us, selected_lt1_method_id, selected_lt2_method_id,
  input_fingerprint, output_fingerprint, core_input_hash, audit_record_json
ON lala_calculation_run
BEGIN
  SELECT RAISE(ABORT, 'lala_calculation_run ist unveraenderlich: kein UPDATE');
END;

CREATE TRIGGER trg_threshold_no_delete BEFORE DELETE ON threshold_result
BEGIN
  SELECT RAISE(ABORT, 'threshold_result ist unveraenderlich: kein DELETE');
END;
CREATE TRIGGER trg_threshold_no_update BEFORE UPDATE OF
  athlete_id, test_id, calculation_run_id, threshold_type, method,
  method_version, lala_engine_version, status, power_w, load_value, load_unit,
  heart_rate_bpm, lactate_mmol_l, effective_at_utc_us, computed_at_utc_us,
  method_details_json, input_data_hash
ON threshold_result
BEGIN
  SELECT RAISE(ABORT, 'threshold_result ist unveraenderlich: kein UPDATE');
END;

CREATE TRIGGER trg_zone_set_no_delete BEFORE DELETE ON training_zone_set
BEGIN
  SELECT RAISE(ABORT, 'training_zone_set ist unveraenderlich: kein DELETE');
END;
CREATE TRIGGER trg_zone_set_no_update BEFORE UPDATE OF
  athlete_id, calculation_run_id, zone_model_id, method, method_version,
  lala_engine_version, quality, effective_from_utc_us, created_at_utc_us
ON training_zone_set
BEGIN
  SELECT RAISE(ABORT, 'training_zone_set ist unveraenderlich: kein UPDATE');
END;

CREATE TRIGGER trg_zone_no_delete BEFORE DELETE ON training_zone
BEGIN
  SELECT RAISE(ABORT, 'training_zone ist unveraenderlich: kein DELETE');
END;
CREATE TRIGGER trg_zone_no_update BEFORE UPDATE ON training_zone
BEGIN
  SELECT RAISE(ABORT, 'training_zone ist unveraenderlich: kein UPDATE');
END;

-- Raw measurements are protected too: a later interpretation must never
-- rewrite what was measured.
CREATE TRIGGER trg_lactate_sample_no_delete BEFORE DELETE ON lactate_sample
BEGIN
  SELECT RAISE(ABORT, 'lactate_sample ist eine Rohmessung: kein DELETE');
END;
CREATE TRIGGER trg_lactate_sample_no_update BEFORE UPDATE OF
  test_id, stage_id, athlete_id, sampled_at_utc_us, lactate_mmol_l,
  sample_site, context
ON lactate_sample
BEGIN
  SELECT RAISE(ABORT, 'lactate_sample ist eine Rohmessung: kein UPDATE');
END;
''';

/// Migration 3 — workspaces, coaching notes and attributable best values.
///
/// Phase F makes the platform understandable before any hardware exists. Three
/// gaps had to be closed for that, all additively:
///
/// The demonstration described in point 1 no longer exists: it was removed in
/// v9, together with every row it had written. The paragraph stays as it was,
/// because a migration that has been applied to real archives must keep saying
/// what it did — see `_v9RemoveDemonstrationWorkspace` for what came after.
///
/// 1. **Demonstration data must be recognisable and separable.** The flag sits
///    on the organization, i.e. on the tenant, because that is where
///    separation is already enforced for everything else. A demo test is not a
///    special kind of test; it belongs to a tenant marked as demonstration
///    data, and every existing tenancy rule therefore applies to it unchanged.
///    Nothing downstream — not the engine, not the repositories, not the
///    screens — ever asks whether a row is a demo row.
/// 2. **The chosen workspace must survive a restart.** `app_state` is a small
///    key/value store for exactly that kind of local decision. It carries no
///    `organization_id` and no `sync_state` on purpose: which workspace this
///    installation last had open is a property of the installation, not of any
///    organisation, and must never be transmitted.
/// 3. **A coaching record needs words, not only numbers.** `coach_note` is
///    append-only like every other longitudinal fact.
const String _v3WorkspacesAndCoaching = '''
-- ------------------------------------------------------------ demonstration
-- 0 = real tenant, 1 = demonstration tenant. Defaulting to 0 means every row
-- that already exists is real data: a migration can never turn a customer's
-- organisation into a demo by accident.
ALTER TABLE organization ADD COLUMN is_demo INTEGER NOT NULL DEFAULT 0;
CREATE INDEX idx_organization_demo ON organization(is_demo);

-- -------------------------------------------------------------- local state
-- Which workspace this installation last had open, and whether the demo has
-- already been generated. Local by definition, therefore never synced.
CREATE TABLE app_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at_utc_us INTEGER NOT NULL
);

-- -------------------------------------------------------------- coach notes
-- Append-only, like every other longitudinal record. A note may refer to a
-- test or a session, or to neither. `visibility` separates what an athlete may
-- read from what stays internal to the coaching staff.
CREATE TABLE coach_note (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organization(id),
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  author_user_id TEXT REFERENCES app_user(id),
  test_id TEXT REFERENCES performance_test(id),
  session_id TEXT REFERENCES session(id),
  body TEXT NOT NULL,
  visibility TEXT NOT NULL DEFAULT 'coaching_staff',
  written_at_utc_us INTEGER NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);
CREATE INDEX idx_coach_note_athlete
  ON coach_note(athlete_id, written_at_utc_us);

-- A written observation records what someone thought at a point in time.
-- Editing it later would falsify that record; a further note is added instead.
CREATE TRIGGER trg_coach_note_no_update BEFORE UPDATE OF
  athlete_id, author_user_id, body, written_at_utc_us
ON coach_note
BEGIN
  SELECT RAISE(ABORT, 'coach_note ist unveraenderlich: kein UPDATE');
END;

-- ---------------------------------------------------------- personal record
-- The v1 table exists but carried no source attribution. A best value that
-- cannot be traced to the test or session that produced it is an anecdote.
ALTER TABLE personal_record ADD COLUMN organization_id TEXT
  REFERENCES organization(id);
ALTER TABLE personal_record ADD COLUMN test_id TEXT
  REFERENCES performance_test(id);
ALTER TABLE personal_record ADD COLUMN label TEXT;
CREATE INDEX idx_record_athlete_time
  ON personal_record(athlete_id, achieved_at_utc_us);
''';

// ---------------------------------------------------------------------------
// v4 — device measured steps
//
// A step test may now be measured by an Ercolina instead of being typed in.
// That changes nothing about the evaluation: the device only replaces the
// human who would otherwise have written the numbers down. What it does change
// is that a number now has a derivation, and a derivation that is not recorded
// is not reproducible.
//
// Three things are therefore added:
//
// 1. `load_semantics` — what the load axis of a test actually means. A step
//    whose load is the protocol target and a step whose load is the measured
//    mean of the same nominal stage are not the same quantity. Two tests may
//    only be compared numerically when this value agrees, so it is stored on
//    the test and not derived at read time.
// 2. `stage_aggregation` — the identifier of the rule that turned raw samples
//    into one number per step, plus the aggregate itself. Storing the rule id
//    per test makes it impossible for a later change of the rule to silently
//    reinterpret an old test.
// 3. `test_connectivity_event` — a lost radio link during a test is a fact
//    about the measurement, not a transient state of a screen. It is recorded
//    so that a later reader can see which step was measured under which
//    conditions.
const String _v4DeviceMeasuredSteps = '''
-- ------------------------------------------------------------ load semantics
-- Existing tests were entered by hand, and a hand-entered load is the nominal
-- load of the protocol. The default therefore describes the existing rows
-- correctly and does not reinterpret them.
ALTER TABLE performance_test ADD COLUMN load_semantics TEXT NOT NULL
  DEFAULT 'load.protocol_target';
ALTER TABLE performance_test ADD COLUMN stage_aggregation TEXT;

-- ------------------------------------------------------- measured aggregates
-- Everything a device contributed to one step, next to the value that went
-- into the evaluation. `load_value` remains the single input of LaLa; these
-- columns explain where it came from.
ALTER TABLE test_stage ADD COLUMN work_j REAL;
ALTER TABLE test_stage ADD COLUMN peak_power_w REAL;
ALTER TABLE test_stage ADD COLUMN stroke_count INTEGER;
ALTER TABLE test_stage ADD COLUMN left_work_share REAL;
ALTER TABLE test_stage ADD COLUMN steady_end_power_w REAL;
ALTER TABLE test_stage ADD COLUMN sample_count INTEGER;
ALTER TABLE test_stage ADD COLUMN window_start_us INTEGER;
ALTER TABLE test_stage ADD COLUMN window_end_us INTEGER;

-- A step that was interrupted is kept, but it must never look like a step the
-- athlete completed. It is handed to the evaluation only after a human has
-- decided to keep it.
ALTER TABLE test_stage ADD COLUMN partial INTEGER NOT NULL DEFAULT 0;

-- ------------------------------------------------------ connectivity events
CREATE TABLE test_connectivity_event (
  id TEXT PRIMARY KEY,
  test_id TEXT NOT NULL REFERENCES performance_test(id),
  stage_id TEXT REFERENCES test_stage(id),
  device_id TEXT REFERENCES device(id),
  occurred_at_utc_us INTEGER NOT NULL,
  state TEXT NOT NULL,
  detail TEXT
);
CREATE INDEX idx_connectivity_test
  ON test_connectivity_event(test_id, occurred_at_utc_us);

-- What happened during a measurement cannot be rewritten afterwards.
CREATE TRIGGER trg_connectivity_no_update BEFORE UPDATE ON
  test_connectivity_event
BEGIN
  SELECT RAISE(ABORT, 'test_connectivity_event ist unveraenderlich');
END;
CREATE TRIGGER trg_connectivity_no_delete BEFORE DELETE ON
  test_connectivity_event
BEGIN
  SELECT RAISE(ABORT, 'test_connectivity_event ist unveraenderlich');
END;
''';

// ---------------------------------------------------------------------------
// v5 — product management
//
// A minor's consent is an event, not an editable flag. The legacy timestamp
// remains on athlete for compatibility; this table records who confirmed what
// and when. Team membership was already time-bounded, so a second active row
// for the same athlete and team would be contradictory rather than history.
const String _v5ProductManagement = '''
CREATE TABLE athlete_consent (
  id TEXT PRIMARY KEY,
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  organization_id TEXT NOT NULL REFERENCES organization(id),
  confirmed_by_name TEXT NOT NULL,
  confirmed_at_utc_us INTEGER NOT NULL,
  statement_version TEXT NOT NULL,
  recorded_by_user_id TEXT REFERENCES app_user(id),
  recorded_at_utc_us INTEGER NOT NULL
);
CREATE INDEX idx_athlete_consent_athlete
  ON athlete_consent(athlete_id, confirmed_at_utc_us DESC);

CREATE TRIGGER trg_athlete_consent_no_update BEFORE UPDATE ON athlete_consent
BEGIN
  SELECT RAISE(ABORT, 'athlete_consent ist unveraenderlich');
END;
CREATE TRIGGER trg_athlete_consent_no_delete BEFORE DELETE ON athlete_consent
BEGIN
  SELECT RAISE(ABORT, 'athlete_consent ist unveraenderlich');
END;

CREATE UNIQUE INDEX idx_team_athlete_one_active
  ON team_athlete(team_id, athlete_id)
  WHERE left_at_utc_us IS NULL;
''';

// ---------------------------------------------------------------------------
// v6 — trainer-private observations
//
// `coach_note` was intentionally created with a textual visibility field, so
// the new `trainer_private` audience needs no destructive table rebuild. The
// author is already immutable data on every note. This index makes the
// repository-enforced "only its author" read rule inexpensive.
const String _v6TrainerPrivateNotes = '''
CREATE INDEX idx_coach_note_athlete_visibility_author
  ON coach_note(athlete_id, visibility, author_user_id, written_at_utc_us);
''';

// ---------------------------------------------------------------------------
// v7 — corrected diagnostic entries
//
// A typo must be correctable, but changing a measured row would erase the
// fact that it happened. Corrections are therefore append-only overlays: the
// original stage/sample remains intact, the newest correction is the current
// working value, and every previous calculation run remains reproducible.
const String _v7DiagnosticCorrections = '''
CREATE TABLE diagnostic_stage_correction (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organization(id),
  test_id TEXT NOT NULL REFERENCES performance_test(id),
  stage_id TEXT NOT NULL REFERENCES test_stage(id),
  corrected_load_value REAL,
  corrected_heart_rate_bpm INTEGER,
  corrected_rpe INTEGER,
  corrected_lactate_mmol_l REAL,
  reason TEXT NOT NULL,
  corrected_by_user_id TEXT NOT NULL REFERENCES app_user(id),
  corrected_at_utc_us INTEGER NOT NULL
);
CREATE INDEX idx_diagnostic_correction_stage
  ON diagnostic_stage_correction(stage_id, corrected_at_utc_us DESC);
CREATE TRIGGER trg_diagnostic_correction_no_update
BEFORE UPDATE ON diagnostic_stage_correction
BEGIN
  SELECT RAISE(ABORT, 'diagnostic_stage_correction ist unveraenderlich');
END;
CREATE TRIGGER trg_diagnostic_correction_no_delete
BEFORE DELETE ON diagnostic_stage_correction
BEGIN
  SELECT RAISE(ABORT, 'diagnostic_stage_correction ist unveraenderlich');
END;
''';

// ---------------------------------------------------------------------------
// v8 — explicit human method choice
//
// A non-standard selected method can either be the engine's fallback or a
// deliberate professional choice. Keeping both facts distinguishes them after
// the screen has been closed and makes the resulting run auditable.
const String _v8ExplicitMethodSelections = '''
ALTER TABLE lala_calculation_run ADD COLUMN expert_lt1_method_id TEXT;
ALTER TABLE lala_calculation_run ADD COLUMN expert_lt2_method_id TEXT;
''';

// ---------------------------------------------------------------------------
// v9 — the demonstration workspace is removed
//
// Until now the installation could open a demonstration tenant: an invented
// performance centre with eight athletes, generated on first use. It served a
// purpose while nobody had data of their own. That purpose has ended, and a
// tenant that nothing can open any more is not neutral — it is a body of
// invented measurements sitting next to real ones.
//
// This migration therefore removes it from an existing archive rather than
// merely hiding it. Three points deserve to be stated plainly:
//
// 1. **The immutability guards are lifted and restored inside this one
//    migration.** Results and raw samples are protected by triggers that
//    reject every DELETE, and that protection is the reason a finding can be
//    trusted. It is suspended here for the length of one transaction and
//    recreated verbatim afterwards, so no real measurement ever loses it. The
//    rows deleted in between were never measurements: they were generated.
// 2. **Only tenants flagged as demonstration are touched.** Every statement
//    selects through `organization.is_demo = 1`. An archive that never opened
//    the demonstration is left byte for byte as it was.
// 3. **`organization.is_demo` itself stays.** Dropping a column requires
//    SQLite 3.35 and this archive has to open on whatever version the device
//    ships. The column keeps its rows honest — everything left is real — and
//    no code reads it any more.
const String _v9RemoveDemonstrationWorkspace = '''
-- ------------------------------------------------------------- local state
-- Which workspace was open last, and the marker saying the demonstration had
-- been generated. Both are answers to questions that no longer exist.
DELETE FROM app_state WHERE key = 'demo.seeded.version';
DELETE FROM app_state WHERE key = 'workspace.active'
  AND value IN (SELECT id FROM organization WHERE is_demo = 1);

-- --------------------------------------------------- suspend the immutability
DROP TRIGGER IF EXISTS trg_run_no_delete;
DROP TRIGGER IF EXISTS trg_threshold_no_delete;
DROP TRIGGER IF EXISTS trg_zone_set_no_delete;
DROP TRIGGER IF EXISTS trg_zone_no_delete;
DROP TRIGGER IF EXISTS trg_lactate_sample_no_delete;
DROP TRIGGER IF EXISTS trg_connectivity_no_delete;
DROP TRIGGER IF EXISTS trg_athlete_consent_no_delete;
DROP TRIGGER IF EXISTS trg_diagnostic_correction_no_delete;

-- ------------------------------------------------------- interpreted results
DELETE FROM training_zone WHERE zone_set_id IN (
  SELECT id FROM training_zone_set WHERE athlete_id IN (
    SELECT id FROM athlete WHERE organization_id IN (
      SELECT id FROM organization WHERE is_demo = 1)));
DELETE FROM training_zone_set WHERE athlete_id IN (
  SELECT id FROM athlete WHERE organization_id IN (
    SELECT id FROM organization WHERE is_demo = 1));
DELETE FROM threshold_result WHERE athlete_id IN (
  SELECT id FROM athlete WHERE organization_id IN (
    SELECT id FROM organization WHERE is_demo = 1));
DELETE FROM diagnostic_stage_correction WHERE organization_id IN (
  SELECT id FROM organization WHERE is_demo = 1);
DELETE FROM lala_calculation_run WHERE organization_id IN (
  SELECT id FROM organization WHERE is_demo = 1);

-- ----------------------------------------------------------- the tests
DELETE FROM test_connectivity_event WHERE test_id IN (
  SELECT id FROM performance_test WHERE organization_id IN (
    SELECT id FROM organization WHERE is_demo = 1));
DELETE FROM lactate_sample WHERE test_id IN (
  SELECT id FROM performance_test WHERE organization_id IN (
    SELECT id FROM organization WHERE is_demo = 1));
DELETE FROM test_stage WHERE test_id IN (
  SELECT id FROM performance_test WHERE organization_id IN (
    SELECT id FROM organization WHERE is_demo = 1));

-- ------------------------------------------------- everything about a person
DELETE FROM athlete_metric WHERE athlete_id IN (
  SELECT id FROM athlete WHERE organization_id IN (
    SELECT id FROM organization WHERE is_demo = 1));
DELETE FROM personal_record WHERE athlete_id IN (
  SELECT id FROM athlete WHERE organization_id IN (
    SELECT id FROM organization WHERE is_demo = 1));
DELETE FROM athlete_attribute WHERE athlete_id IN (
  SELECT id FROM athlete WHERE organization_id IN (
    SELECT id FROM organization WHERE is_demo = 1));
DELETE FROM athlete_consent WHERE organization_id IN (
  SELECT id FROM organization WHERE is_demo = 1);
DELETE FROM coach_note WHERE organization_id IN (
  SELECT id FROM organization WHERE is_demo = 1);

DELETE FROM performance_test WHERE organization_id IN (
  SELECT id FROM organization WHERE is_demo = 1);

-- ------------------------------------------------------------- the sessions
DELETE FROM session_metrics WHERE session_id IN (
  SELECT id FROM session WHERE organization_id IN (
    SELECT id FROM organization WHERE is_demo = 1));
DELETE FROM heart_rate_sample WHERE session_id IN (
  SELECT id FROM session WHERE organization_id IN (
    SELECT id FROM organization WHERE is_demo = 1));
DELETE FROM stroke WHERE session_id IN (
  SELECT id FROM session WHERE organization_id IN (
    SELECT id FROM organization WHERE is_demo = 1));
DELETE FROM derived_sample WHERE session_id IN (
  SELECT id FROM session WHERE organization_id IN (
    SELECT id FROM organization WHERE is_demo = 1));
DELETE FROM raw_sensor_sample WHERE session_id IN (
  SELECT id FROM session WHERE organization_id IN (
    SELECT id FROM organization WHERE is_demo = 1));
DELETE FROM interval_record WHERE session_id IN (
  SELECT id FROM session WHERE organization_id IN (
    SELECT id FROM organization WHERE is_demo = 1));
DELETE FROM session WHERE organization_id IN (
  SELECT id FROM organization WHERE is_demo = 1);

DELETE FROM workout_step WHERE workout_id IN (
  SELECT id FROM workout WHERE organization_id IN (
    SELECT id FROM organization WHERE is_demo = 1));
DELETE FROM workout WHERE organization_id IN (
  SELECT id FROM organization WHERE is_demo = 1);

-- ---------------------------------------------------------- the device that
-- never had a radio: registered so the measured test was reachable at all.
DELETE FROM calibration WHERE sensor_id IN (
  SELECT id FROM sensor WHERE device_id IN (
    SELECT id FROM device WHERE organization_id IN (
      SELECT id FROM organization WHERE is_demo = 1)));
DELETE FROM sensor WHERE device_id IN (
  SELECT id FROM device WHERE organization_id IN (
    SELECT id FROM organization WHERE is_demo = 1));
DELETE FROM device WHERE organization_id IN (
  SELECT id FROM organization WHERE is_demo = 1);

-- ---------------------------------------------------------- squad and tenant
DELETE FROM coach_athlete_assignment WHERE organization_id IN (
  SELECT id FROM organization WHERE is_demo = 1);
DELETE FROM team_athlete WHERE team_id IN (
  SELECT id FROM team WHERE organization_id IN (
    SELECT id FROM organization WHERE is_demo = 1));
DELETE FROM membership WHERE organization_id IN (
  SELECT id FROM organization WHERE is_demo = 1);
DELETE FROM team WHERE organization_id IN (
  SELECT id FROM organization WHERE is_demo = 1);
DELETE FROM athlete WHERE organization_id IN (
  SELECT id FROM organization WHERE is_demo = 1);
DELETE FROM audit_log WHERE organization_id IN (
  SELECT id FROM organization WHERE is_demo = 1);
DELETE FROM sync_outbox WHERE organization_id IN (
  SELECT id FROM organization WHERE is_demo = 1);

-- The demonstration coach was a user of that tenant and of nothing else. The
-- guards are not decoration: a foreign key that still pointed here would abort
-- the whole migration, and an archive that refuses to open is worse than a
-- leftover row.
DELETE FROM app_user WHERE id = 'demo-coach'
  AND NOT EXISTS (SELECT 1 FROM membership WHERE user_id = app_user.id)
  AND NOT EXISTS (SELECT 1 FROM athlete WHERE user_id = app_user.id)
  AND NOT EXISTS (
    SELECT 1 FROM coach_athlete_assignment WHERE coach_user_id = app_user.id)
  AND NOT EXISTS (
    SELECT 1 FROM calibration WHERE performed_by_user_id = app_user.id)
  AND NOT EXISTS (
    SELECT 1 FROM athlete_attribute WHERE recorded_by_user_id = app_user.id)
  AND NOT EXISTS (
    SELECT 1 FROM workout WHERE created_by_user_id = app_user.id)
  AND NOT EXISTS (
    SELECT 1 FROM session WHERE recorded_by_user_id = app_user.id)
  AND NOT EXISTS (
    SELECT 1 FROM performance_test
     WHERE supervised_by_user_id = app_user.id
        OR created_by_user_id = app_user.id)
  AND NOT EXISTS (
    SELECT 1 FROM lactate_sample WHERE entered_by_user_id = app_user.id)
  AND NOT EXISTS (SELECT 1 FROM audit_log WHERE actor_user_id = app_user.id)
  AND NOT EXISTS (
    SELECT 1 FROM lala_calculation_run
     WHERE triggered_by_user_id = app_user.id)
  AND NOT EXISTS (SELECT 1 FROM coach_note WHERE author_user_id = app_user.id)
  AND NOT EXISTS (
    SELECT 1 FROM athlete_consent WHERE recorded_by_user_id = app_user.id)
  AND NOT EXISTS (
    SELECT 1 FROM diagnostic_stage_correction
     WHERE corrected_by_user_id = app_user.id);

DELETE FROM organization WHERE is_demo = 1;

-- ------------------------------------------------- restore the immutability
-- Verbatim from v2, v4, v5 and v7. What is protected after this migration is
-- exactly what was protected before it.
CREATE TRIGGER trg_run_no_delete BEFORE DELETE ON lala_calculation_run
BEGIN
  SELECT RAISE(ABORT, 'lala_calculation_run ist unveraenderlich: kein DELETE');
END;
CREATE TRIGGER trg_threshold_no_delete BEFORE DELETE ON threshold_result
BEGIN
  SELECT RAISE(ABORT, 'threshold_result ist unveraenderlich: kein DELETE');
END;
CREATE TRIGGER trg_zone_set_no_delete BEFORE DELETE ON training_zone_set
BEGIN
  SELECT RAISE(ABORT, 'training_zone_set ist unveraenderlich: kein DELETE');
END;
CREATE TRIGGER trg_zone_no_delete BEFORE DELETE ON training_zone
BEGIN
  SELECT RAISE(ABORT, 'training_zone ist unveraenderlich: kein DELETE');
END;
CREATE TRIGGER trg_lactate_sample_no_delete BEFORE DELETE ON lactate_sample
BEGIN
  SELECT RAISE(ABORT, 'lactate_sample ist eine Rohmessung: kein DELETE');
END;
CREATE TRIGGER trg_connectivity_no_delete BEFORE DELETE ON
  test_connectivity_event
BEGIN
  SELECT RAISE(ABORT, 'test_connectivity_event ist unveraenderlich');
END;
CREATE TRIGGER trg_athlete_consent_no_delete BEFORE DELETE ON athlete_consent
BEGIN
  SELECT RAISE(ABORT, 'athlete_consent ist unveraenderlich');
END;
CREATE TRIGGER trg_diagnostic_correction_no_delete
BEFORE DELETE ON diagnostic_stage_correction
BEGIN
  SELECT RAISE(ABORT, 'diagnostic_stage_correction ist unveraenderlich');
END;
''';

/// Device clocks and sequences restart with a new source epoch. Preserve all
/// old values and rowids while replacing the insufficient unique keys. NULL
/// remains unknown (not epoch zero); -1 is outside the uint32 wire epoch.
/// No table references these observation keys. SQLite runs this whole copy
/// inside the existing atomic migration, including unique-index creation.
const String _v28EpochScopedObservations = '''
CREATE TABLE raw_sensor_sample_v28 (
  session_id TEXT NOT NULL REFERENCES session(id),
  sensor_id TEXT NOT NULL REFERENCES sensor(id),
  device_time_us INTEGER NOT NULL,
  received_at_monotonic_us INTEGER NOT NULL,
  sequence INTEGER NOT NULL,
  payload BLOB,
  force_n REAL,
  velocity_m_s REAL,
  power_w REAL,
  battery_percent INTEGER,
  parser_valid INTEGER NOT NULL, pulling INTEGER, source_epoch INTEGER, mapped_time_us INTEGER, status_flags INTEGER, position_m REAL, optical_raw INTEGER, optical_min INTEGER, optical_max INTEGER, hall_passes INTEGER, flywheel_revolutions INTEGER, stroke_counter INTEGER, battery_mv INTEGER, missed_samples INTEGER, adc_errors INTEGER, angular_velocity_rad_s REAL, stroke_event_time_us INTEGER, stroke_source TEXT, stroke_events_supported INTEGER NOT NULL DEFAULT 0
);
INSERT INTO raw_sensor_sample_v28(rowid, session_id, sensor_id, device_time_us, received_at_monotonic_us, sequence, payload, force_n, velocity_m_s, power_w, battery_percent, parser_valid, pulling, source_epoch, mapped_time_us, status_flags, position_m, optical_raw, optical_min, optical_max, hall_passes, flywheel_revolutions, stroke_counter, battery_mv, missed_samples, adc_errors, angular_velocity_rad_s, stroke_event_time_us, stroke_source, stroke_events_supported)
SELECT rowid, session_id, sensor_id, device_time_us, received_at_monotonic_us, sequence, payload, force_n, velocity_m_s, power_w, battery_percent, parser_valid, pulling, source_epoch, mapped_time_us, status_flags, position_m, optical_raw, optical_min, optical_max, hall_passes, flywheel_revolutions, stroke_counter, battery_mv, missed_samples, adc_errors, angular_velocity_rad_s, stroke_event_time_us, stroke_source, stroke_events_supported FROM raw_sensor_sample;
DROP TABLE raw_sensor_sample;
ALTER TABLE raw_sensor_sample_v28 RENAME TO raw_sensor_sample;
CREATE UNIQUE INDEX idx_raw_sensor_sample_observation
ON raw_sensor_sample(session_id, sensor_id, COALESCE(source_epoch, -1), device_time_us, sequence);

CREATE TABLE derived_sample_v28 (
  session_id TEXT NOT NULL REFERENCES session(id),
  sensor_id TEXT NOT NULL REFERENCES sensor(id),
  aligned_time_us INTEGER NOT NULL,
  calibrated_force_n REAL NOT NULL,
  calibrated_velocity_m_s REAL NOT NULL,
  calibrated_power_w REAL NOT NULL,
  filtered_force_n REAL NOT NULL,
  filtered_power_w REAL NOT NULL,
  quality TEXT NOT NULL,
  algorithm_version TEXT NOT NULL
, source_epoch INTEGER
);
INSERT INTO derived_sample_v28(rowid, session_id, sensor_id, aligned_time_us, calibrated_force_n, calibrated_velocity_m_s, calibrated_power_w, filtered_force_n, filtered_power_w, quality, algorithm_version)
SELECT rowid, session_id, sensor_id, aligned_time_us, calibrated_force_n, calibrated_velocity_m_s, calibrated_power_w, filtered_force_n, filtered_power_w, quality, algorithm_version FROM derived_sample;
DROP TABLE derived_sample;
ALTER TABLE derived_sample_v28 RENAME TO derived_sample;
CREATE UNIQUE INDEX idx_derived_sample_observation
ON derived_sample(session_id, sensor_id, COALESCE(source_epoch, -1), aligned_time_us);
''';

const String _v29SignedWork = '''
ALTER TABLE raw_sensor_sample ADD COLUMN signed_work_mj INTEGER;
ALTER TABLE stroke ADD COLUMN signed_work_available INTEGER NOT NULL DEFAULT 0;
ALTER TABLE session ADD COLUMN signed_work_j REAL;
''';

const String _v31MeasurementSegments =
    "ALTER TABLE raw_sensor_sample ADD COLUMN measurement_generation INTEGER;";

const String _v32ScoutReadings = '''
CREATE TABLE xc_scout_revision (
  athlete_id TEXT NOT NULL REFERENCES athlete(id),
  sample_id TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK(revision > 0),
  recorded_at_utc_us INTEGER NOT NULL,
  recorded_by TEXT NOT NULL REFERENCES app_user(id),
  document TEXT NOT NULL,
  PRIMARY KEY (athlete_id, sample_id, revision)
);
''';
