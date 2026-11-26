/// Platform domain model.
///
/// The system is explicitly **not** built on the assumption that one account
/// equals one athlete. A [Organization] owns athletes, teams, devices and
/// measured data. Users hold role-based [Membership]s inside an organization,
/// and an athlete record exists independently of any login.
library;

enum OrganizationKind { private, club, academy, performanceCentre }

/// Wofür ein registriertes Gerät eingesetzt werden darf.
///
/// Ein Laktatmessgerät gehört zum Bestand, ist aber keine Quelle für eine
/// Trainingseinheit. Diese Trennung ist Datenmodell und nicht Namensheuristik:
/// «Scout» im Anzeigenamen darf nie darüber entscheiden, was verbunden wird.
enum DeviceKind { training, lactateMeter, simulator }

/// A role is granted per organization, never globally.
enum PlatformRole { athlete, coach, headCoach, admin, diagnostician, support }

enum Capability {
  viewOwnData,
  viewAthleteData,
  recordSession,
  recordDiagnostics,
  manageAthletes,
  manageTeams,
  manageDevices,
  manageMembers,
  exportData,
  deleteData,
}

/// Explicit capability matrix. Permissions are data, not scattered `if` checks.
const Map<PlatformRole, Set<Capability>> roleCapabilities = {
  PlatformRole.athlete: {
    Capability.viewOwnData,
    Capability.recordSession,
    Capability.exportData,
  },
  PlatformRole.coach: {
    Capability.viewOwnData,
    Capability.viewAthleteData,
    Capability.recordSession,
    Capability.manageAthletes,
    Capability.exportData,
  },
  PlatformRole.headCoach: {
    Capability.viewOwnData,
    Capability.viewAthleteData,
    Capability.recordSession,
    Capability.recordDiagnostics,
    Capability.manageAthletes,
    Capability.manageTeams,
    Capability.manageDevices,
    Capability.exportData,
  },
  PlatformRole.admin: {
    Capability.viewOwnData,
    Capability.viewAthleteData,
    Capability.recordSession,
    Capability.recordDiagnostics,
    Capability.manageAthletes,
    Capability.manageTeams,
    Capability.manageDevices,
    Capability.manageMembers,
    Capability.exportData,
    Capability.deleteData,
  },
  PlatformRole.diagnostician: {
    Capability.viewAthleteData,
    Capability.recordDiagnostics,
    Capability.exportData,
  },
  PlatformRole.support: {Capability.viewAthleteData},
};

/// Roles that may see every athlete of their own organization without an
/// explicit coach assignment or shared team. `headCoach` is the sports
/// director role: broad operational access must still not bypass a trainer's
/// explicitly private observations.
const Set<PlatformRole> organizationWideRoles = {
  PlatformRole.headCoach,
  PlatformRole.admin,
};

class Membership {
  const Membership({
    required this.id,
    required this.organizationId,
    required this.userId,
    required this.role,
    required this.grantedAtUtcUs,
    this.teamId,
    this.revokedAtUtcUs,
  });

  final String id;
  final String organizationId;
  final String userId;
  final PlatformRole role;
  final String? teamId;
  final int grantedAtUtcUs;
  final int? revokedAtUtcUs;

  bool get isActive => revokedAtUtcUs == null;
}

/// Everything the access policy needs about one (user, athlete) pair. The
/// repository resolves these facts from persisted relations; the decision
/// itself stays a pure, unit-testable function.
class AthleteAccessContext {
  const AthleteAccessContext({
    required this.userOrganizationId,
    required this.athleteOrganizationId,
    required this.activeRoles,
    this.isSelf = false,
    this.hasCoachAssignment = false,
    this.sharesTeam = false,
  });

  final String userOrganizationId;
  final String athleteOrganizationId;
  final Set<PlatformRole> activeRoles;
  final bool isSelf;
  final bool hasCoachAssignment;
  final bool sharesTeam;

  bool get sameOrganization => userOrganizationId == athleteOrganizationId;
}

abstract final class AccessPolicy {
  static Set<Capability> capabilitiesOf(Set<PlatformRole> roles) => {
    for (final role in roles) ...?roleCapabilities[role],
  };

  static bool hasCapability(Set<PlatformRole> roles, Capability capability) =>
      capabilitiesOf(roles).contains(capability);

  /// Cross-tenant reads are impossible by construction: a mismatching
  /// organization is rejected before any role is considered.
  static bool canViewAthlete(AthleteAccessContext context) {
    if (!context.sameOrganization) return false;
    if (context.isSelf) {
      return context.activeRoles.contains(PlatformRole.athlete) ||
          hasCapability(context.activeRoles, Capability.viewOwnData);
    }
    if (!hasCapability(context.activeRoles, Capability.viewAthleteData)) {
      return false;
    }
    if (context.activeRoles.any(organizationWideRoles.contains)) return true;
    return context.hasCoachAssignment || context.sharesTeam;
  }

  static bool canRecordSessionFor(AthleteAccessContext context) =>
      canViewAthlete(context) &&
      hasCapability(context.activeRoles, Capability.recordSession);

  static bool canRecordDiagnosticsFor(AthleteAccessContext context) =>
      canViewAthlete(context) &&
      hasCapability(context.activeRoles, Capability.recordDiagnostics);
}

/// Longitudinal athlete facts are versioned, never overwritten.
enum AthleteAttribute {
  bodyMassKg,
  heightCm,
  maxHeartRateBpm,
  restingHeartRateBpm,
}

enum ThresholdType { lt1, lt2 }

enum ZoneBasis { power, heartRate }

/// Sync bookkeeping for the offline-first pipeline.
enum SyncState { pending, synced, conflict }

class PlatformAccessException implements Exception {
  const PlatformAccessException(this.message);
  final String message;
  @override
  String toString() => 'PlatformAccessException: $message';
}
