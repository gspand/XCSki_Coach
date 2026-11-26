import 'dart:convert';

import '../domain/platform.dart';
import 'giulia_database.dart';

/// Identity, tenancy, equipment ownership and longitudinal athlete records.
class PlatformRepository {
  PlatformRepository(this.database);

  final GiuliaDatabase database;

  // ---------------------------------------------------------------- tenancy

  void createOrganization({
    required String id,
    required String name,
    required OrganizationKind kind,
    required int nowUtcUs,
  }) {
    // `is_demo` is not written. The column survives as a tombstone of the
    // removed demonstration tenant (see `_v9RemoveDemonstrationWorkspace`) and
    // defaults to 0: everything this installation holds is real data.
    database.raw.execute(
      '''INSERT INTO organization(
           id, name, kind, created_at_utc_us, updated_at_utc_us)
         VALUES (?, ?, ?, ?, ?)''',
      [id, name, kind.name, nowUtcUs, nowUtcUs],
    );
    _enqueue(id, 'organization', id, 'insert', nowUtcUs);
  }

  void createUser({
    required String id,
    required String displayName,
    required int nowUtcUs,
    String? email,
  }) {
    database.raw.execute(
      '''INSERT INTO app_user(id, display_name, email, created_at_utc_us, updated_at_utc_us)
         VALUES (?, ?, ?, ?, ?)''',
      [id, displayName, email, nowUtcUs, nowUtcUs],
    );
  }

  void grantMembership({
    required String id,
    required String organizationId,
    required String userId,
    required PlatformRole role,
    required int nowUtcUs,
    String? teamId,
  }) {
    database.raw.execute(
      '''INSERT INTO membership(
           id, organization_id, user_id, role, team_id, granted_at_utc_us)
         VALUES (?, ?, ?, ?, ?, ?)''',
      [id, organizationId, userId, role.name, teamId, nowUtcUs],
    );
    _audit(
      organizationId,
      userId,
      'grant_membership',
      'membership',
      id,
      nowUtcUs,
    );
  }

  void revokeMembership({required String id, required int nowUtcUs}) {
    database.raw.execute(
      'UPDATE membership SET revoked_at_utc_us = ? WHERE id = ? AND revoked_at_utc_us IS NULL',
      [nowUtcUs, id],
    );
  }

  /// Active roles of a user **within one organization**. A user without an
  /// active membership receives an empty set and therefore no access.
  Set<PlatformRole> rolesOf({
    required String userId,
    required String organizationId,
  }) => database.raw
      .select(
        '''SELECT DISTINCT role FROM membership
            WHERE user_id = ? AND organization_id = ? AND revoked_at_utc_us IS NULL''',
        [userId, organizationId],
      )
      .map((row) => PlatformRole.values.byName(row['role'] as String))
      .toSet();

  /// Organizations the user currently belongs to. A user can legitimately work
  /// for several clubs; data never crosses between them.
  List<String> organizationsOf(String userId) => database.raw
      .select(
        '''SELECT DISTINCT organization_id FROM membership
            WHERE user_id = ? AND revoked_at_utc_us IS NULL
            ORDER BY organization_id''',
        [userId],
      )
      .map((row) => row['organization_id'] as String)
      .toList(growable: false);

  /// Users who currently hold an active membership in an organization.
  ///
  /// Ordered by how much responsibility the role carries, so a caller that
  /// needs *an* identity for an organization — a workspace switcher, for
  /// example — gets the one that can actually see the organization's work
  /// rather than an arbitrary row. Callers that need all of them still get
  /// all of them.
  List<OrganizationMember> membersOf(String organizationId) {
    final members = database.raw
        .select(
          '''SELECT user_id, role FROM membership
              WHERE organization_id = ? AND revoked_at_utc_us IS NULL''',
          [organizationId],
        )
        .map(
          (row) => OrganizationMember(
            userId: row['user_id'] as String,
            role: PlatformRole.values.byName(row['role'] as String),
          ),
        )
        .toList();
    members.sort((a, b) {
      final byRole = _roleRank(a.role).compareTo(_roleRank(b.role));
      return byRole != 0 ? byRole : a.userId.compareTo(b.userId);
    });
    return List.unmodifiable(members);
  }

  static int _roleRank(PlatformRole role) => switch (role) {
    PlatformRole.admin => 0,
    PlatformRole.headCoach => 1,
    PlatformRole.coach => 2,
    PlatformRole.diagnostician => 3,
    PlatformRole.athlete => 4,
    PlatformRole.support => 5,
  };

  // --------------------------------------------------------------- athletes

  void createAthlete({
    required String id,
    required String organizationId,
    required String name,
    required int nowUtcUs,
    String? userId,
    int? birthYear,
    String? sex,
    bool isMinor = false,
    int? consentRecordedAtUtcUs,
  }) {
    database.raw.execute(
      '''INSERT INTO athlete(
           id, organization_id, user_id, name, birth_year, sex, is_minor,
           consent_recorded_at_utc_us, created_at_utc_us, updated_at_utc_us)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        organizationId,
        userId,
        name,
        birthYear,
        sex,
        isMinor ? 1 : 0,
        consentRecordedAtUtcUs,
        nowUtcUs,
        nowUtcUs,
      ],
    );
    _enqueue(organizationId, 'athlete', id, 'insert', nowUtcUs);
  }

  /// One athlete's mutable profile fields and current teams.
  ///
  /// A list or chart only needs [AthleteSummary]; an editing form needs the
  /// actual stored minor/consent state too. Keeping that richer read separate
  /// avoids casually putting personal data into every picker.
  AthleteProfileRecord athleteProfile(String athleteId) {
    final rows = database.raw.select(
      '''SELECT id, organization_id, name, birth_year, sex, is_minor,
                consent_recorded_at_utc_us
           FROM athlete WHERE id = ? AND archived_at_utc_us IS NULL''',
      [athleteId],
    );
    if (rows.isEmpty) throw StateError('Unknown athlete $athleteId');
    final row = rows.first;
    return AthleteProfileRecord(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      name: row['name'] as String,
      birthYear: row['birth_year'] as int?,
      sex: row['sex'] as String?,
      isMinor: (row['is_minor'] as int) == 1,
      consentRecordedAtUtcUs: row['consent_recorded_at_utc_us'] as int?,
      teamIds: teamsOfAthlete(athleteId),
    );
  }

  /// Changes the profile and replaces only the *current* team memberships.
  /// Past memberships are closed, never deleted. A minor requires a fresh,
  /// named confirmation; the confirmation itself is an immutable event.
  void updateAthleteProfile({
    required String athleteId,
    required String actorUserId,
    required String name,
    required int nowUtcUs,
    int? birthYear,
    String? sex,
    required Set<String> teamIds,
    String? consentConfirmedByName,
    int? consentConfirmedAtUtcUs,
  }) {
    final current = athleteProfile(athleteId);
    _assertCapability(
      userId: actorUserId,
      organizationId: current.organizationId,
      capability: Capability.manageAthletes,
    );
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const PlatformAccessException('An athlete needs a name.');
    }
    final isMinor = _isMinor(birthYear, nowUtcUs);
    final consentName = consentConfirmedByName?.trim();
    final consentTime = consentConfirmedAtUtcUs;
    final confirmsMinor =
        consentName?.isNotEmpty == true && consentTime != null;
    if (isMinor && !confirmsMinor && !current.isMinor) {
      throw const PlatformAccessException(
        'A minor athlete needs a named consent confirmation.',
      );
    }
    for (final teamId in teamIds) {
      if (_teamOrganization(teamId) != current.organizationId) {
        throw const PlatformAccessException(
          'An athlete can only join teams of their own organization.',
        );
      }
    }

    database.transaction(() {
      database.raw.execute(
        '''UPDATE athlete
              SET name = ?, birth_year = ?, sex = ?, is_minor = ?,
                  consent_recorded_at_utc_us = CASE
                    WHEN ? IS NULL THEN consent_recorded_at_utc_us ELSE ? END,
                  updated_at_utc_us = ?, sync_state = 'pending'
            WHERE id = ?''',
        [
          trimmedName,
          birthYear,
          sex,
          isMinor ? 1 : 0,
          consentConfirmedAtUtcUs,
          consentConfirmedAtUtcUs,
          nowUtcUs,
          athleteId,
        ],
      );
      _replaceTeams(
        athleteId: athleteId,
        currentTeamIds: current.teamIds.toSet(),
        desiredTeamIds: teamIds,
        nowUtcUs: nowUtcUs,
      );
      if (isMinor && confirmsMinor) {
        recordMinorConsent(
          id: 'consent-$athleteId-$nowUtcUs',
          athleteId: athleteId,
          actorUserId: actorUserId,
          confirmedByName: consentName!,
          confirmedAtUtcUs: consentTime,
          recordedAtUtcUs: nowUtcUs,
        );
      }
      _enqueue(
        current.organizationId,
        'athlete',
        athleteId,
        'update',
        nowUtcUs,
      );
      _audit(
        current.organizationId,
        actorUserId,
        'update_athlete_profile',
        'athlete',
        athleteId,
        nowUtcUs,
      );
    });
  }

  /// Records a consent event. It cannot be edited or deleted afterwards.
  void recordMinorConsent({
    required String id,
    required String athleteId,
    required String actorUserId,
    required String confirmedByName,
    required int confirmedAtUtcUs,
    required int recordedAtUtcUs,
    String statementVersion = 'minor-consent.v1',
  }) {
    final organizationId = organizationOfAthlete(athleteId);
    _assertCapability(
      userId: actorUserId,
      organizationId: organizationId,
      capability: Capability.manageAthletes,
    );
    if (confirmedByName.trim().isEmpty) {
      throw const PlatformAccessException(
        'The confirming person needs a name.',
      );
    }
    database.raw.execute(
      '''INSERT INTO athlete_consent(
           id, athlete_id, organization_id, confirmed_by_name,
           confirmed_at_utc_us, statement_version, recorded_by_user_id,
           recorded_at_utc_us)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        athleteId,
        organizationId,
        confirmedByName.trim(),
        confirmedAtUtcUs,
        statementVersion,
        actorUserId,
        recordedAtUtcUs,
      ],
    );
    _audit(
      organizationId,
      actorUserId,
      'record_minor_consent',
      'athlete_consent',
      id,
      recordedAtUtcUs,
    );
  }

  String organizationOfAthlete(String athleteId) {
    final rows = database.raw.select(
      'SELECT organization_id FROM athlete WHERE id = ?',
      [athleteId],
    );
    if (rows.isEmpty) throw StateError('Unknown athlete $athleteId');
    return rows.first['organization_id'] as String;
  }

  void createTeam({
    required String id,
    required String organizationId,
    required String name,
    required int nowUtcUs,
    String? ageClass,
    String? season,
  }) {
    database.raw.execute(
      '''INSERT INTO team(id, organization_id, name, age_class, season,
                          created_at_utc_us, updated_at_utc_us)
         VALUES (?, ?, ?, ?, ?, ?, ?)''',
      [id, organizationId, name, ageClass, season, nowUtcUs, nowUtcUs],
    );
  }

  /// Interactive counterpart of [createTeam]. Seeds and imports use the
  /// low-level method above; screens must pass an actor and are checked here.
  void createManagedTeam({
    required String id,
    required String organizationId,
    required String actorUserId,
    required String name,
    required int nowUtcUs,
  }) {
    _assertCapability(
      userId: actorUserId,
      organizationId: organizationId,
      capability: Capability.manageTeams,
    );
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const PlatformAccessException('A team needs a name.');
    }
    createTeam(
      id: id,
      organizationId: organizationId,
      name: trimmed,
      nowUtcUs: nowUtcUs,
    );
    _audit(organizationId, actorUserId, 'create_team', 'team', id, nowUtcUs);
  }

  void renameTeam({
    required String teamId,
    required String actorUserId,
    required String name,
    required int nowUtcUs,
  }) {
    final organizationId = _teamOrganization(teamId);
    _assertCapability(
      userId: actorUserId,
      organizationId: organizationId,
      capability: Capability.manageTeams,
    );
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const PlatformAccessException('A team needs a name.');
    }
    database.raw.execute(
      '''UPDATE team SET name = ?, updated_at_utc_us = ?, sync_state = 'pending'
          WHERE id = ?''',
      [trimmed, nowUtcUs, teamId],
    );
    _audit(
      organizationId,
      actorUserId,
      'rename_team',
      'team',
      teamId,
      nowUtcUs,
    );
  }

  /// Team membership is time-bounded so a squad change never rewrites the
  /// history of past sessions.
  void addAthleteToTeam({
    required String teamId,
    required String athleteId,
    required int joinedAtUtcUs,
  }) {
    if (_teamOrganization(teamId) != organizationOfAthlete(athleteId)) {
      throw const PlatformAccessException(
        'An athlete can only join a team of the same organization.',
      );
    }
    database.raw.execute(
      'INSERT INTO team_athlete(team_id, athlete_id, joined_at_utc_us) VALUES (?, ?, ?)',
      [teamId, athleteId, joinedAtUtcUs],
    );
  }

  void assignCoach({
    required String id,
    required String coachUserId,
    required String athleteId,
    required int nowUtcUs,
  }) {
    final organizationId = organizationOfAthlete(athleteId);
    database.raw.execute(
      '''INSERT INTO coach_athlete_assignment(
           id, organization_id, coach_user_id, athlete_id, assigned_at_utc_us)
         VALUES (?, ?, ?, ?, ?)''',
      [id, organizationId, coachUserId, athleteId, nowUtcUs],
    );
    _audit(
      organizationId,
      coachUserId,
      'assign_coach',
      'athlete',
      athleteId,
      nowUtcUs,
    );
  }

  // ---------------------------------------------------------------- access

  AthleteAccessContext accessContext({
    required String userId,
    required String athleteId,
  }) {
    final athleteOrganizationId = organizationOfAthlete(athleteId);
    final athleteUserId =
        database.raw.select('SELECT user_id FROM athlete WHERE id = ?', [
              athleteId,
            ]).first['user_id']
            as String?;
    final userOrganizations = organizationsOf(userId);
    return AthleteAccessContext(
      // Only an active membership places the user inside the athlete's
      // organization; without one the tenancy check fails immediately.
      userOrganizationId: userOrganizations.contains(athleteOrganizationId)
          ? athleteOrganizationId
          : (userOrganizations.isEmpty ? '' : userOrganizations.first),
      athleteOrganizationId: athleteOrganizationId,
      activeRoles: rolesOf(
        userId: userId,
        organizationId: athleteOrganizationId,
      ),
      isSelf: athleteUserId == userId,
      hasCoachAssignment: _hasAssignment(userId, athleteId),
      sharesTeam: _sharesTeam(userId, athleteId),
    );
  }

  bool canViewAthlete({required String userId, required String athleteId}) =>
      AccessPolicy.canViewAthlete(
        accessContext(userId: userId, athleteId: athleteId),
      );

  void assertCanRecordFor({required String userId, required String athleteId}) {
    final context = accessContext(userId: userId, athleteId: athleteId);
    if (!AccessPolicy.canRecordSessionFor(context)) {
      throw const PlatformAccessException(
        'The user may not record a session for this athlete.',
      );
    }
  }

  /// Diagnostics are a separate capability: recording a training session does
  /// not entitle a user to enter or evaluate a performance test.
  void assertCanRecordDiagnosticsFor({
    required String userId,
    required String athleteId,
  }) {
    final context = accessContext(userId: userId, athleteId: athleteId);
    if (!AccessPolicy.canRecordDiagnosticsFor(context)) {
      throw const PlatformAccessException(
        'The user may not record diagnostics for this athlete.',
      );
    }
  }

  /// Athletes the caller may actually see. Used by the coach dashboard and by
  /// the shared-device athlete picker.
  List<String> visibleAthletes({
    required String userId,
    required String organizationId,
  }) => database.raw
      .select(
        'SELECT id FROM athlete WHERE organization_id = ? AND archived_at_utc_us IS NULL ORDER BY name',
        [organizationId],
      )
      .map((row) => row['id'] as String)
      .where(
        (athleteId) => canViewAthlete(userId: userId, athleteId: athleteId),
      )
      .toList(growable: false);

  /// Visible athletes with the data a picker needs.
  ///
  /// Same access rule as [visibleAthletes]; this variant exists so a selection
  /// surface does not have to issue one extra query per athlete.
  List<AthleteSummary> visibleAthleteSummaries({
    required String userId,
    required String organizationId,
  }) => database.raw
      .select(
        '''SELECT id, name, birth_year, sex FROM athlete
            WHERE organization_id = ? AND archived_at_utc_us IS NULL
            ORDER BY name''',
        [organizationId],
      )
      .where(
        (row) => canViewAthlete(userId: userId, athleteId: row['id'] as String),
      )
      .map(
        (row) => AthleteSummary(
          id: row['id'] as String,
          name: row['name'] as String,
          birthYear: row['birth_year'] as int?,
          sex: row['sex'] as String?,
        ),
      )
      .toList(growable: false);

  // ------------------------------------------------------------ workspaces

  /// Every organization this installation knows about.
  ///
  /// Deliberately not access-filtered: this is the list of tenants the device
  /// itself holds, which is what a workspace switcher needs. What may be *read*
  /// inside one of them is still decided per athlete by [canViewAthlete].
  List<OrganizationSummary> organizations() => database.raw
      .select('''SELECT id, name, kind, created_at_utc_us FROM organization
            ORDER BY name''')
      .map(
        (row) => OrganizationSummary(
          id: row['id'] as String,
          name: row['name'] as String,
          kind: OrganizationKind.values.byName(row['kind'] as String),
          createdAtUtcUs: row['created_at_utc_us'] as int,
        ),
      )
      .toList(growable: false);

  OrganizationSummary? organization(String id) {
    final match = organizations().where((entry) => entry.id == id);
    return match.isEmpty ? null : match.first;
  }

  /// Teams of one organization.
  List<TeamSummary> teamsOf(String organizationId) => database.raw
      .select(
        '''SELECT t.id, t.name, t.age_class, t.season,
                  (SELECT COUNT(*) FROM team_athlete ta
                    WHERE ta.team_id = t.id AND ta.left_at_utc_us IS NULL)
                  AS member_count
             FROM team t
            WHERE t.organization_id = ?
            ORDER BY t.name''',
        [organizationId],
      )
      .map(
        (row) => TeamSummary(
          id: row['id'] as String,
          name: row['name'] as String,
          ageClass: row['age_class'] as String?,
          season: row['season'] as String?,
          memberCount: row['member_count'] as int,
        ),
      )
      .toList(growable: false);

  /// Athlete ids of one team, current members only.
  List<String> athletesOfTeam(String teamId) => database.raw
      .select(
        '''SELECT athlete_id FROM team_athlete
            WHERE team_id = ? AND left_at_utc_us IS NULL''',
        [teamId],
      )
      .map((row) => row['athlete_id'] as String)
      .toList(growable: false);

  /// Teams an athlete currently belongs to.
  List<String> teamsOfAthlete(String athleteId) => database.raw
      .select(
        '''SELECT team_id FROM team_athlete
            WHERE athlete_id = ? AND left_at_utc_us IS NULL''',
        [athleteId],
      )
      .map((row) => row['team_id'] as String)
      .toList(growable: false);

  // ------------------------------------------------------------ local state

  /// Reads a local, never-synced setting.
  String? appState(String key) {
    final rows = database.raw.select(
      'SELECT value FROM app_state WHERE key = ?',
      [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  /// Writes a local, never-synced setting.
  void setAppState({
    required String key,
    required String value,
    required int nowUtcUs,
  }) => database.raw.execute(
    '''INSERT INTO app_state(key, value, updated_at_utc_us) VALUES (?, ?, ?)
       ON CONFLICT(key) DO UPDATE SET value = excluded.value,
                                      updated_at_utc_us = excluded.updated_at_utc_us''',
    [key, value, nowUtcUs],
  );

  void clearAppState(String key) =>
      database.raw.execute('DELETE FROM app_state WHERE key = ?', [key]);

  // ----------------------------------------------------------- coach notes

  /// Records what a coach observed. Append-only: a later view is a new note.
  void writeCoachNote({
    required String id,
    required String athleteId,
    required String body,
    required int writtenAtUtcUs,
    String? authorUserId,
    String? testId,
    String? sessionId,
    String visibility = 'coaching_staff',
  }) {
    final organizationId = organizationOfAthlete(athleteId);
    if (authorUserId != null) {
      _assertCapability(
        userId: authorUserId,
        organizationId: organizationId,
        capability: Capability.manageAthletes,
      );
    }
    if (body.trim().isEmpty) {
      throw const PlatformAccessException('A coaching note needs text.');
    }
    if (visibility != 'coaching_staff' &&
        visibility != 'athlete' &&
        visibility != 'trainer_private') {
      throw const PlatformAccessException('Unknown coaching-note visibility.');
    }
    if (visibility == 'trainer_private' && authorUserId == null) {
      throw const PlatformAccessException(
        'A trainer-private note needs its trainer as author.',
      );
    }
    database.raw.execute(
      '''INSERT INTO coach_note(
           id, organization_id, athlete_id, author_user_id, test_id,
           session_id, body, visibility, written_at_utc_us)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        organizationId,
        athleteId,
        authorUserId,
        testId,
        sessionId,
        body.trim(),
        visibility,
        writtenAtUtcUs,
      ],
    );
    _enqueue(organizationId, 'coach_note', id, 'insert', writtenAtUtcUs);
  }

  /// Notes about one athlete, newest first.
  List<CoachNote> coachNotesOf(String athleteId) => database.raw
      .select(
        '''SELECT id, author_user_id, test_id, session_id, body, visibility,
                  written_at_utc_us
             FROM xc_coach_note WHERE athlete_id = ?
            ORDER BY written_at_utc_us DESC''',
        [athleteId],
      )
      .map(
        (row) => CoachNote(
          id: row['id'] as String,
          athleteId: athleteId,
          body: row['body'] as String,
          writtenAtUtcUs: row['written_at_utc_us'] as int,
          authorUserId: row['author_user_id'] as String?,
          testId: row['test_id'] as String?,
          sessionId: row['session_id'] as String?,
          visibility: row['visibility'] as String,
        ),
      )
      .toList(growable: false);

  /// Notes [userId] may read for one athlete.
  ///
  /// The sports director (`headCoach`) may open every athlete in the
  /// organisation, but not a `trainer_private` observation. That restriction
  /// is made here, at the persistence boundary, instead of relying on a UI
  /// checkbox being hidden. The author may read their own private note as
  /// long as they still have access to the athlete.
  List<CoachNote> visibleCoachNotes({
    required String athleteId,
    required String userId,
  }) {
    final context = accessContext(userId: userId, athleteId: athleteId);
    if (!AccessPolicy.canViewAthlete(context)) return const [];
    final isAthlete =
        context.isSelf && context.activeRoles.contains(PlatformRole.athlete);
    return coachNotesOf(athleteId)
        .where((note) {
          if (isAthlete) return note.visibleToAthlete;
          return !note.trainerPrivate || note.authorUserId == userId;
        })
        .toList(growable: false);
  }

  // ------------------------------------------------------- personal records

  /// Stores a best value together with what produced it.
  ///
  /// A best value without a source is an anecdote, so [testId] or [sessionId]
  /// should be given wherever one exists.
  void recordPersonalRecord({
    required String id,
    required String athleteId,
    required String recordType,
    required double value,
    required String unit,
    required int achievedAtUtcUs,
    required String algorithmVersion,
    String? sessionId,
    String? testId,
    String? label,
  }) {
    final organizationId = organizationOfAthlete(athleteId);
    database.raw.execute(
      '''INSERT INTO personal_record(
           id, athlete_id, organization_id, record_type, value, unit,
           achieved_at_utc_us, session_id, test_id, label, algorithm_version)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        athleteId,
        organizationId,
        recordType,
        value,
        unit,
        achievedAtUtcUs,
        sessionId,
        testId,
        label,
        algorithmVersion,
      ],
    );
  }

  /// Current best values of an athlete, newest first, superseded ones omitted.
  List<PersonalRecord> personalRecordsOf(String athleteId) => database.raw
      .select(
        '''SELECT id, record_type, value, unit, achieved_at_utc_us,
                  session_id, test_id, label
             FROM xc_personal_record
            WHERE athlete_id = ? AND superseded_at_utc_us IS NULL
            ORDER BY achieved_at_utc_us DESC''',
        [athleteId],
      )
      .map(
        (row) => PersonalRecord(
          id: row['id'] as String,
          athleteId: athleteId,
          recordType: row['record_type'] as String,
          value: row['value'] as double,
          unit: row['unit'] as String,
          achievedAtUtcUs: row['achieved_at_utc_us'] as int,
          sessionId: row['session_id'] as String?,
          testId: row['test_id'] as String?,
          label: row['label'] as String?,
        ),
      )
      .toList(growable: false);

  // --------------------------------------------------------------- devices

  /// Devices belong to an organization. Any athlete of that organization can
  /// train on any of its devices.
  void registerDevice({
    required String id,
    required String organizationId,
    required String bleIdentifier,
    required String displayName,
    required int nowUtcUs,
    DeviceKind kind = DeviceKind.training,
    String? location,
    String? model,
    String? hardwareVersion,
    String? firmwareVersion,
    String? serialNumber,
  }) {
    database.raw.execute(
      '''INSERT INTO device(
           id, organization_id, ble_identifier, display_name, kind, location, model,
           hardware_version, firmware_version, serial_number,
           created_at_utc_us, updated_at_utc_us)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        organizationId,
        bleIdentifier,
        displayName,
        kind.name,
        location,
        model,
        hardwareVersion,
        firmwareVersion,
        serialNumber,
        nowUtcUs,
        nowUtcUs,
      ],
    );
  }

  /// Hält ein erreichbares Gerät fest, ohne eine bestehende Registrierung zu
  /// duplizieren. Der Mandant ist Teil der Kennung des Aufrufers; ein Gerät
  /// wird beim Konflikt niemals still in einen anderen Mandanten verschoben.
  void rememberDevice({
    required String id,
    required String organizationId,
    required String bleIdentifier,
    required String displayName,
    required DeviceKind kind,
    required int nowUtcUs,
    String? model,
    String? serialNumber,
  }) {
    database.raw.execute(
      '''INSERT INTO device(
           id, organization_id, ble_identifier, display_name, kind, model,
           serial_number, last_seen_at_utc_us, created_at_utc_us,
           updated_at_utc_us)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           ble_identifier = excluded.ble_identifier,
           display_name = excluded.display_name,
           kind = excluded.kind,
           model = COALESCE(excluded.model, device.model),
           serial_number = COALESCE(excluded.serial_number, device.serial_number),
           last_seen_at_utc_us = excluded.last_seen_at_utc_us,
           updated_at_utc_us = excluded.updated_at_utc_us
         WHERE device.organization_id = excluded.organization_id''',
      [
        id,
        organizationId,
        bleIdentifier,
        displayName,
        kind.name,
        model,
        serialNumber,
        nowUtcUs,
        nowUtcUs,
        nowUtcUs,
      ],
    );
  }

  void registerSensor({
    required String id,
    required String deviceId,
    required String side,
    required String serviceUuid,
    required String measurementUuid,
  }) {
    database.raw.execute(
      '''INSERT INTO sensor(id, device_id, side, service_uuid, measurement_uuid)
         VALUES (?, ?, ?, ?, ?)''',
      [id, deviceId, side, serviceUuid, measurementUuid],
    );
  }

  /// Stores the fixed physical roles carried by an Ercolina PRIMARY manifest.
  void rememberErcolinaPair({
    required String primaryId,
    required String secondaryId,
    required String organizationId,
    required String bleIdentifier,
    required int nowUtcUs,
    required String serviceUuid,
    required String measurementUuid,
    required String firmwareVersion,
    required String hardwareVersion,
  }) {
    database.transaction(() {
      rememberDevice(
        id: primaryId,
        organizationId: organizationId,
        bleIdentifier: bleIdentifier,
        displayName: 'Ercolina',
        kind: DeviceKind.training,
        model: 'GIULIA Ercolina',
        serialNumber: primaryId,
        nowUtcUs: nowUtcUs,
      );
      database.raw.execute(
        '''UPDATE device
              SET firmware_version = ?, hardware_version = ?
            WHERE id = ? AND organization_id = ?''',
        [firmwareVersion, hardwareVersion, primaryId, organizationId],
      );
      for (final sensor in [
        (id: primaryId, side: 'left'),
        (id: secondaryId, side: 'right'),
      ]) {
        database.raw.execute(
          '''INSERT INTO sensor(id, device_id, side, service_uuid, measurement_uuid)
             VALUES (?, ?, ?, ?, ?)
             ON CONFLICT(id) DO UPDATE SET
               device_id = excluded.device_id,
               side = excluded.side,
               service_uuid = excluded.service_uuid,
               measurement_uuid = excluded.measurement_uuid''',
          [sensor.id, primaryId, sensor.side, serviceUuid, measurementUuid],
        );
      }
    });
  }

  void rememberVerifiedDeviceFirmware({
    required String deviceId,
    required String organizationId,
    required String firmwareVersion,
    required int verifiedAtUtcUs,
  }) {
    database.transaction(() {
      final registered = database.raw.select(
        'SELECT 1 FROM device WHERE id = ? AND organization_id = ?',
        [deviceId, organizationId],
      );
      if (registered.isEmpty) return;
      database.raw.execute(
        '''UPDATE device
              SET firmware_version = ?, last_seen_at_utc_us = ?,
                  updated_at_utc_us = ?, sync_state = 'pending'
            WHERE id = ? AND organization_id = ?''',
        [
          firmwareVersion,
          verifiedAtUtcUs,
          verifiedAtUtcUs,
          deviceId,
          organizationId,
        ],
      );
      enqueueSync(
        organizationId: organizationId,
        entity: 'device',
        entityId: deviceId,
        operation: 'update',
        nowUtcUs: verifiedAtUtcUs,
      );
      writeAudit(
        organizationId: organizationId,
        action: 'firmware_verified',
        entity: 'device',
        entityId: deviceId,
        nowUtcUs: verifiedAtUtcUs,
      );
    });
  }

  /// Devices of an organization, by display name.
  ///
  /// A device is offered to a coach because it belongs to the organization,
  /// not because it happens to be within radio range. Range is a question the
  /// connection answers later; ownership is a question the database answers
  /// now.
  List<DeviceRecord> devicesOf(String organizationId) => database.raw
      .select(
        '''SELECT id, organization_id, ble_identifier, display_name, kind, location,
                  model, firmware_version, serial_number, last_seen_at_utc_us
             FROM device WHERE organization_id = ?
            ORDER BY display_name, id''',
        [organizationId],
      )
      .map(
        (row) => DeviceRecord(
          id: row['id'] as String,
          organizationId: row['organization_id'] as String,
          bleIdentifier: row['ble_identifier'] as String,
          displayName: row['display_name'] as String,
          kind: _deviceKind(row['kind'] as String?),
          location: row['location'] as String?,
          model: row['model'] as String?,
          firmwareVersion: row['firmware_version'] as String?,
          serialNumber: row['serial_number'] as String?,
          lastSeenAtUtcUs: row['last_seen_at_utc_us'] as int?,
        ),
      )
      .toList(growable: false);

  /// Nur Geräte, die Leistung für Training und gemessene Stufentests liefern.
  /// Ein Lactate Scout bleibt dadurch in der Geräteverwaltung sichtbar, wird
  /// aber nie an eine Ercolina-Verbindung übergeben.
  List<DeviceRecord> trainingDevicesOf(
    String organizationId, {
    bool includeSimulator = true,
  }) => devicesOf(organizationId)
      .where(
        (device) =>
            device.kind == DeviceKind.training ||
            (includeSimulator && device.kind == DeviceKind.simulator),
      )
      .toList(growable: false);

  static DeviceKind _deviceKind(String? stored) {
    for (final kind in DeviceKind.values) {
      if (kind.name == stored) return kind;
    }
    return DeviceKind.training;
  }

  DeviceRecord? deviceById(String deviceId) {
    final rows = database.raw.select(
      'SELECT organization_id FROM device WHERE id = ?',
      [deviceId],
    );
    if (rows.isEmpty) return null;
    final organizationId = rows.first['organization_id'] as String;
    for (final device in devicesOf(organizationId)) {
      if (device.id == deviceId) return device;
    }
    return null;
  }

  /// The sensors of a device, left before right.
  List<SensorRecord> sensorsOf(String deviceId) => database.raw
      .select(
        '''SELECT id, device_id, side, service_uuid, measurement_uuid
             FROM sensor WHERE device_id = ? ORDER BY side, id''',
        [deviceId],
      )
      .map(
        (row) => SensorRecord(
          id: row['id'] as String,
          deviceId: row['device_id'] as String,
          side: row['side'] as String,
          serviceUuid: row['service_uuid'] as String,
          measurementUuid: row['measurement_uuid'] as String,
        ),
      )
      .toList(growable: false);

  /// Remembers that a device was reachable. Purely informational.
  void markDeviceSeen({required String deviceId, required int nowUtcUs}) {
    database.raw.execute(
      '''UPDATE device SET last_seen_at_utc_us = ?, updated_at_utc_us = ?
          WHERE id = ?''',
      [nowUtcUs, nowUtcUs, deviceId],
    );
  }

  void recordCalibration({
    required String id,
    required String sensorId,
    required double forceOffsetNewton,
    required double forceScale,
    required String protocolVersion,
    required int nowUtcUs,
    String? performedByUserId,
    String calibrationType = 'force_linear',
    int? effectiveFromUtcUs,
    int? validUntilUtcUs,
    Map<String, Object?> additionalParameters = const <String, Object?>{},
  }) {
    final effective = effectiveFromUtcUs ?? nowUtcUs;
    if (!forceOffsetNewton.isFinite ||
        !forceScale.isFinite ||
        forceScale <= 0 ||
        calibrationType.trim().isEmpty ||
        protocolVersion.trim().isEmpty ||
        (validUntilUtcUs != null && validUntilUtcUs <= effective)) {
      throw ArgumentError('Invalid calibration parameters or validity.');
    }
    final sensor = database.raw.select('SELECT 1 FROM sensor WHERE id = ?', [
      sensorId,
    ]);
    if (sensor.isEmpty) throw StateError('Unknown sensor $sensorId');
    final parameters = <String, Object?>{
      'force_offset_n': forceOffsetNewton,
      'force_scale': forceScale,
      ...additionalParameters,
    };
    database.raw.execute(
      '''INSERT INTO calibration(
           id, sensor_id, created_at_utc_us, effective_from_utc_us,
           force_offset_n, force_scale, protocol_version,
           performed_by_user_id, calibration_type, parameters_json,
           valid_until_utc_us)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        sensorId,
        nowUtcUs,
        effective,
        forceOffsetNewton,
        forceScale,
        protocolVersion,
        performedByUserId,
        calibrationType,
        jsonEncode(parameters),
        validUntilUtcUs,
      ],
    );
  }

  CalibrationRecord? calibrationAt({
    required String sensorId,
    required String calibrationType,
    required int atUtcUs,
  }) {
    final rows = database.raw.select(
      '''SELECT id, sensor_id, calibration_type, parameters_json,
                created_at_utc_us, effective_from_utc_us,
                valid_until_utc_us, protocol_version, force_offset_n,
                force_scale, valid
           FROM calibration
          WHERE sensor_id = ? AND calibration_type = ?
            AND effective_from_utc_us <= ?
            AND (valid_until_utc_us IS NULL OR valid_until_utc_us > ?)
            AND valid = 1
          ORDER BY effective_from_utc_us DESC, created_at_utc_us DESC
          LIMIT 1''',
      [sensorId, calibrationType, atUtcUs, atUtcUs],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final decoded = jsonDecode(row['parameters_json'] as String);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Corrupt calibration parameters.');
    }
    return CalibrationRecord(
      id: row['id'] as String,
      sensorId: row['sensor_id'] as String,
      type: row['calibration_type'] as String,
      parameters: Map<String, Object?>.unmodifiable(decoded),
      createdAtUtcUs: row['created_at_utc_us'] as int,
      effectiveFromUtcUs: row['effective_from_utc_us'] as int,
      validUntilUtcUs: row['valid_until_utc_us'] as int?,
      protocolVersion: row['protocol_version'] as String,
      forceOffsetNewton: row['force_offset_n'] as double,
      forceScale: row['force_scale'] as double,
    );
  }

  // ------------------------------------------------- longitudinal athlete data

  /// Insert-only athlete facts. Reading always asks "what was true at time t".
  void recordAttribute({
    required String id,
    required String athleteId,
    required AthleteAttribute attribute,
    required double value,
    required String unit,
    required int effectiveFromUtcUs,
    required int recordedAtUtcUs,
    String source = 'manual',
    String? recordedByUserId,
  }) {
    database.raw.execute(
      '''INSERT INTO athlete_attribute(
           id, athlete_id, attribute, value_numeric, unit,
           effective_from_utc_us, recorded_at_utc_us, recorded_by_user_id, source)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        athleteId,
        attribute.name,
        value,
        unit,
        effectiveFromUtcUs,
        recordedAtUtcUs,
        recordedByUserId,
        source,
      ],
    );
  }

  double? attributeAt({
    required String athleteId,
    required AthleteAttribute attribute,
    required int asOfUtcUs,
  }) {
    final rows = database.raw.select(
      '''SELECT value_numeric FROM athlete_attribute
          WHERE lower(trim(source)) NOT LIKE 'strava%' AND athlete_id = ? AND attribute = ? AND effective_from_utc_us <= ?
          ORDER BY effective_from_utc_us DESC, recorded_at_utc_us DESC LIMIT 1''',
      [athleteId, attribute.name, asOfUtcUs],
    );
    return rows.isEmpty ? null : rows.first['value_numeric'] as double?;
  }

  void recordThreshold({
    required String id,
    required String athleteId,
    required ThresholdType type,
    required String method,
    required String methodVersion,
    required int effectiveAtUtcUs,
    required int computedAtUtcUs,
    String? testId,
    double? powerWatt,
    int? heartRateBpm,
    double? lactateMmolPerLitre,
  }) {
    database.raw.execute(
      '''INSERT INTO threshold_result(
           id, athlete_id, test_id, threshold_type, method, method_version,
           power_w, heart_rate_bpm, lactate_mmol_l, effective_at_utc_us,
           computed_at_utc_us)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        athleteId,
        testId,
        type.name,
        method,
        methodVersion,
        powerWatt,
        heartRateBpm,
        lactateMmolPerLitre,
        effectiveAtUtcUs,
        computedAtUtcUs,
      ],
    );
  }

  /// Ordered threshold history for one method. Comparing two diagnostics is a
  /// query, not a recalculation, because every result stores its own method.
  List<ThresholdPoint> thresholdHistory({
    required String athleteId,
    required ThresholdType type,
    required String method,
  }) => database.raw
      .select(
        '''SELECT power_w, heart_rate_bpm, effective_at_utc_us, method_version
             FROM xc_threshold_result
            WHERE athlete_id = ? AND threshold_type = ? AND method = ?
            ORDER BY effective_at_utc_us''',
        [athleteId, type.name, method],
      )
      .map(
        (row) => ThresholdPoint(
          powerWatt: row['power_w'] as double?,
          heartRateBpm: row['heart_rate_bpm'] as int?,
          effectiveAtUtcUs: row['effective_at_utc_us'] as int,
          methodVersion: row['method_version'] as String,
        ),
      )
      .toList(growable: false);

  void recordAthleteMetric({
    required String id,
    required String athleteId,
    required String metric,
    required double value,
    required String unit,
    required int effectiveAtUtcUs,
    required String algorithmVersion,
    String? sessionId,
    String? testId,
  }) {
    database.raw.execute(
      '''INSERT INTO athlete_metric(
           id, athlete_id, session_id, test_id, metric, value, unit,
           effective_at_utc_us, algorithm_version)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        athleteId,
        sessionId,
        testId,
        metric,
        value,
        unit,
        effectiveAtUtcUs,
        algorithmVersion,
      ],
    );
  }

  List<({int atUtcUs, double value})> metricSeries({
    required String athleteId,
    required String metric,
    int? fromUtcUs,
    int? toUtcUs,
  }) => database.raw
      .select(
        '''SELECT effective_at_utc_us, value FROM xc_athlete_metric
            WHERE athlete_id = ? AND metric = ?
              AND effective_at_utc_us >= ? AND effective_at_utc_us <= ?
            ORDER BY effective_at_utc_us''',
        [
          athleteId,
          metric,
          fromUtcUs ?? -9223372036854775808,
          toUtcUs ?? 9223372036854775807,
        ],
      )
      .map(
        (row) => (
          atUtcUs: row['effective_at_utc_us'] as int,
          value: row['value'] as double,
        ),
      )
      .toList(growable: false);

  // ---------------------------------------------------------- sync + audit

  List<({int id, String entity, String entityId, String operation})>
  pendingSyncOperations() => database.raw
      .select(
        'SELECT id, entity, entity_id, operation FROM sync_outbox WHERE acknowledged_at_utc_us IS NULL ORDER BY id',
      )
      .map(
        (row) => (
          id: row['id'] as int,
          entity: row['entity'] as String,
          entityId: row['entity_id'] as String,
          operation: row['operation'] as String,
        ),
      )
      .toList(growable: false);

  void acknowledgeSync({required int outboxId, required int nowUtcUs}) {
    database.raw.execute(
      'UPDATE sync_outbox SET acknowledged_at_utc_us = ? WHERE id = ?',
      [nowUtcUs, outboxId],
    );
  }

  /// Queues one mutation for the offline-first sync pipeline.
  ///
  /// Public so sibling repositories feed the **same** outbox. There is exactly
  /// one sync mechanism in this system; a second one would silently create a
  /// class of data that never leaves the device.
  void enqueueSync({
    required String organizationId,
    required String entity,
    required String entityId,
    required String operation,
    required int nowUtcUs,
  }) => database.raw.execute(
    '''INSERT INTO sync_outbox(
         organization_id, entity, entity_id, operation, queued_at_utc_us)
       VALUES (?, ?, ?, ?, ?)''',
    [organizationId, entity, entityId, operation, nowUtcUs],
  );

  /// Appends one entry to the single, shared audit trail.
  ///
  /// Public for the same reason as [enqueueSync]: LaLa evaluations are audited
  /// here, not in a second audit world of their own.
  void writeAudit({
    required String organizationId,
    required String action,
    required String entity,
    required String entityId,
    required int nowUtcUs,
    String? actorUserId,
    String? detail,
  }) => database.raw.execute(
    '''INSERT INTO audit_log(
         id, organization_id, actor_user_id, action, entity, entity_id,
         at_utc_us, detail)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
    [
      '$entity-$entityId-$nowUtcUs-$action',
      organizationId,
      actorUserId,
      action,
      entity,
      entityId,
      nowUtcUs,
      detail,
    ],
  );

  /// Audit entries of one organization, oldest first.
  List<({String action, String entity, String entityId, String? detail})>
  auditTrail(String organizationId) => database.raw
      .select(
        '''SELECT action, entity, entity_id, detail FROM audit_log
            WHERE organization_id = ? ORDER BY at_utc_us, id''',
        [organizationId],
      )
      .map(
        (row) => (
          action: row['action'] as String,
          entity: row['entity'] as String,
          entityId: row['entity_id'] as String,
          detail: row['detail'] as String?,
        ),
      )
      .toList(growable: false);

  void _enqueue(
    String organizationId,
    String entity,
    String entityId,
    String operation,
    int nowUtcUs,
  ) => enqueueSync(
    organizationId: organizationId,
    entity: entity,
    entityId: entityId,
    operation: operation,
    nowUtcUs: nowUtcUs,
  );

  void _audit(
    String organizationId,
    String? actorUserId,
    String action,
    String entity,
    String entityId,
    int nowUtcUs,
  ) => writeAudit(
    organizationId: organizationId,
    actorUserId: actorUserId,
    action: action,
    entity: entity,
    entityId: entityId,
    nowUtcUs: nowUtcUs,
  );

  void _assertCapability({
    required String userId,
    required String organizationId,
    required Capability capability,
  }) {
    if (!AccessPolicy.hasCapability(
      rolesOf(userId: userId, organizationId: organizationId),
      capability,
    )) {
      throw PlatformAccessException(
        'The user may not ${capability.name} in this organization.',
      );
    }
  }

  static bool _isMinor(int? birthYear, int nowUtcUs) {
    if (birthYear == null) return false;
    final year = DateTime.fromMicrosecondsSinceEpoch(
      nowUtcUs,
      isUtc: true,
    ).year;
    return year - birthYear < 18;
  }

  void _replaceTeams({
    required String athleteId,
    required Set<String> currentTeamIds,
    required Set<String> desiredTeamIds,
    required int nowUtcUs,
  }) {
    for (final teamId in currentTeamIds.difference(desiredTeamIds)) {
      database.raw.execute(
        '''UPDATE team_athlete SET left_at_utc_us = ?
            WHERE team_id = ? AND athlete_id = ? AND left_at_utc_us IS NULL''',
        [nowUtcUs, teamId, athleteId],
      );
    }
    for (final teamId in desiredTeamIds.difference(currentTeamIds)) {
      database.raw.execute(
        'INSERT INTO team_athlete(team_id, athlete_id, joined_at_utc_us) VALUES (?, ?, ?)',
        [teamId, athleteId, nowUtcUs],
      );
    }
  }

  String _teamOrganization(String teamId) {
    final rows = database.raw.select(
      'SELECT organization_id FROM team WHERE id = ?',
      [teamId],
    );
    if (rows.isEmpty) throw StateError('Unknown team $teamId');
    return rows.first['organization_id'] as String;
  }

  bool _hasAssignment(String userId, String athleteId) => database.raw
      .select(
        '''SELECT 1 FROM coach_athlete_assignment
                WHERE coach_user_id = ? AND athlete_id = ? AND revoked_at_utc_us IS NULL
                LIMIT 1''',
        [userId, athleteId],
      )
      .isNotEmpty;

  bool _sharesTeam(String userId, String athleteId) => database.raw
      .select(
        '''SELECT 1 FROM membership m
                 JOIN team_athlete ta ON ta.team_id = m.team_id
                WHERE m.user_id = ? AND ta.athlete_id = ?
                  AND m.revoked_at_utc_us IS NULL AND ta.left_at_utc_us IS NULL
                LIMIT 1''',
        [userId, athleteId],
      )
      .isNotEmpty;
}

class ThresholdPoint {
  const ThresholdPoint({
    required this.effectiveAtUtcUs,
    required this.methodVersion,
    this.powerWatt,
    this.heartRateBpm,
  });

  final int effectiveAtUtcUs;
  final String methodVersion;
  final double? powerWatt;
  final int? heartRateBpm;
}

/// Identity of an athlete for selection surfaces. Deliberately minimal: a
/// picker needs a name, not a medical record.
class AthleteSummary {
  const AthleteSummary({
    required this.id,
    required this.name,
    this.birthYear,
    this.sex,
  });

  final String id;
  final String name;
  final int? birthYear;
  final String? sex;
}

/// Profile data that may be edited. It is intentionally not used by selection
/// lists, which must not pull consent state into every read.
class AthleteProfileRecord {
  const AthleteProfileRecord({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.isMinor,
    required this.teamIds,
    this.birthYear,
    this.sex,
    this.consentRecordedAtUtcUs,
  });

  final String id;
  final String organizationId;
  final String name;
  final int? birthYear;
  final String? sex;
  final bool isMinor;
  final int? consentRecordedAtUtcUs;
  final List<String> teamIds;
}

/// A tenant as a workspace switcher needs to see it.
/// One active membership, reduced to who it is and what they may do.
class OrganizationMember {
  const OrganizationMember({required this.userId, required this.role});

  final String userId;
  final PlatformRole role;
}

/// A measuring device as it is owned, not as it is currently reachable.
class DeviceRecord {
  const DeviceRecord({
    required this.id,
    required this.organizationId,
    required this.bleIdentifier,
    required this.displayName,
    this.kind = DeviceKind.training,
    this.location,
    this.model,
    this.firmwareVersion,
    this.serialNumber,
    this.lastSeenAtUtcUs,
  });

  final String id;
  final String organizationId;

  /// Address or advertised identifier used to find the device over the air.
  final String bleIdentifier;

  final String displayName;
  final DeviceKind kind;
  final String? location;
  final String? model;
  final String? firmwareVersion;
  final String? serialNumber;

  /// When the device was last reachable. Informational only — a device that
  /// was never seen is still a device of this organization.
  final int? lastSeenAtUtcUs;
}

/// One sensor of a device. An Ercolina carries a left and a right one.
class SensorRecord {
  const SensorRecord({
    required this.id,
    required this.deviceId,
    required this.side,
    required this.serviceUuid,
    required this.measurementUuid,
  });

  final String id;
  final String deviceId;

  /// `left` or `right`, as registered.
  final String side;

  final String serviceUuid;
  final String measurementUuid;
}

class CalibrationRecord {
  const CalibrationRecord({
    required this.id,
    required this.sensorId,
    required this.type,
    required this.parameters,
    required this.createdAtUtcUs,
    required this.effectiveFromUtcUs,
    required this.protocolVersion,
    required this.forceOffsetNewton,
    required this.forceScale,
    this.validUntilUtcUs,
  });

  final String id;
  final String sensorId;
  final String type;
  final Map<String, Object?> parameters;
  final int createdAtUtcUs;
  final int effectiveFromUtcUs;
  final int? validUntilUtcUs;
  final String protocolVersion;
  final double forceOffsetNewton;
  final double forceScale;

  bool isValidAt(int utcUs) =>
      utcUs >= effectiveFromUtcUs &&
      (validUntilUtcUs == null || utcUs < validUntilUtcUs!);
}

class OrganizationSummary {
  const OrganizationSummary({
    required this.id,
    required this.name,
    required this.kind,
    required this.createdAtUtcUs,
  });

  final String id;
  final String name;
  final OrganizationKind kind;
  final int createdAtUtcUs;
}

/// A team with its current head count.
class TeamSummary {
  const TeamSummary({
    required this.id,
    required this.name,
    required this.memberCount,
    this.ageClass,
    this.season,
  });

  final String id;
  final String name;
  final int memberCount;
  final String? ageClass;
  final String? season;
}

/// One written coaching observation.
class CoachNote {
  const CoachNote({
    required this.id,
    required this.athleteId,
    required this.body,
    required this.writtenAtUtcUs,
    required this.visibility,
    this.authorUserId,
    this.testId,
    this.sessionId,
  });

  final String id;
  final String athleteId;
  final String body;
  final int writtenAtUtcUs;

  /// `coaching_staff`, `athlete` or `trainer_private`. A note the athlete may
  /// read is a different act from an internal one; private notes are visible
  /// only to their author, including when a sports director opens the athlete.
  final String visibility;

  final String? authorUserId;
  final String? testId;
  final String? sessionId;

  bool get visibleToAthlete => visibility == 'athlete';

  bool get trainerPrivate => visibility == 'trainer_private';
}

/// A best value with the record that produced it.
class PersonalRecord {
  const PersonalRecord({
    required this.id,
    required this.athleteId,
    required this.recordType,
    required this.value,
    required this.unit,
    required this.achievedAtUtcUs,
    this.sessionId,
    this.testId,
    this.label,
  });

  final String id;
  final String athleteId;
  final String recordType;
  final double value;
  final String unit;
  final int achievedAtUtcUs;
  final String? sessionId;
  final String? testId;

  /// Human-readable name, e.g. "Bester 20-min-Schnitt".
  final String? label;

  /// A record that can be traced back to the measurement that produced it.
  bool get hasSource => sessionId != null || testId != null;
}
