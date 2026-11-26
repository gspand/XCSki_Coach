/// Rollierender Belastungszustand (Training Load State) im XCAthleteState.
///
/// WICHTIGE SPORTWISSENSCHAFTLICHE LEITPLANKEN:
/// - Kein universeller GIULIA-TSS.
/// - Getrennte Zeitreihen je Methode (Banister TRIMP, sRPE, Work kJ) mit eigener Provenienz.
/// - LoadBalance = Chronic - Acute bleibt eine rein deskriptive Kennzahl!
/// - Keine automatische Gleichsetzung: «LoadBalance negativ = müde» oder «positiv = fit».
library;

import '../load/ewma_load_tracker.dart';

class TrainingLoadState {
  const TrainingLoadState({
    this.banisterTrimpSeries,
    this.srpeSeries,
    this.workKjSeries,
    this.dataCoverageRatio28d = 1.0,
  });

  /// Zeitreihe nach Banister TRIMP (kardiovaskulärer Proxy).
  final EwmaSeries? banisterTrimpSeries;

  /// Zeitreihe nach Session-RPE (subjektiv empfundene Belastung).
  final EwmaSeries? srpeSeries;

  /// Zeitreihe nach mechanischer Arbeit (kJ).
  final EwmaSeries? workKjSeries;

  /// Datenabdeckung der letzten 28 Tage (1.0 = lückenlos, < 0.8 = signifikante Lücken).
  final double dataCoverageRatio28d;

  EwmaDailyState? get latestBanisterState =>
      banisterTrimpSeries?.states.isNotEmpty == true
          ? banisterTrimpSeries!.states.last
          : null;

  EwmaDailyState? get latestSrpeState =>
      srpeSeries?.states.isNotEmpty == true ? srpeSeries!.states.last : null;

  EwmaDailyState? get latestWorkKjState =>
      workKjSeries?.states.isNotEmpty == true ? workKjSeries!.states.last : null;

  /// Rein deskriptive Zusammenfassung der aktuellen Belastungsbalance.
  /// Enthält bewusst KEIN medizinisches oder Ermüdungs-Urteil.
  String get descriptiveSummary {
    final b = latestBanisterState;
    if (b == null) {
      return 'Keine rollierende Banister-TRIMP Zeitreihe verfügbar';
    }
    final balance = b.loadBalance;
    final relation = balance >= 0
        ? 'Chronische Last übersteigt akute Last (+${balance.toStringAsFixed(1)})'
        : 'Akute Last übersteigt chronische Last (${balance.toStringAsFixed(1)})';

    return 'Banister TRIMP: Akut ${b.acuteLoad.toStringAsFixed(1)}, Chronisch ${b.chronicLoad.toStringAsFixed(1)} | $relation (rein deskriptiv)';
  }

  Map<String, dynamic> toJson() => {
    if (banisterTrimpSeries != null)
      'banisterTrimpSeries': banisterTrimpSeries!.toJson(),
    if (srpeSeries != null) 'srpeSeries': srpeSeries!.toJson(),
    if (workKjSeries != null) 'workKjSeries': workKjSeries!.toJson(),
    'dataCoverageRatio28d': dataCoverageRatio28d,
  };

  factory TrainingLoadState.fromJson(Map<String, dynamic> json) =>
      TrainingLoadState(
        banisterTrimpSeries: json['banisterTrimpSeries'] != null
            ? EwmaSeries.fromJson(
                json['banisterTrimpSeries'] as Map<String, dynamic>,
              )
            : null,
        srpeSeries: json['srpeSeries'] != null
            ? EwmaSeries.fromJson(
                json['srpeSeries'] as Map<String, dynamic>,
              )
            : null,
        workKjSeries: json['workKjSeries'] != null
            ? EwmaSeries.fromJson(
                json['workKjSeries'] as Map<String, dynamic>,
              )
            : null,
        dataCoverageRatio28d:
            (json['dataCoverageRatio28d'] as num?)?.toDouble() ?? 1.0,
      );
}
