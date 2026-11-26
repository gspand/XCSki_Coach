/// Sportartspezifische Taxonomie für den Skilanglauf und Ausdauersport in GIULIA.
///
/// Differenziert zwischen Skating, Klassisch, Skiroller, Doppelstock und Ercolina.
/// Ein Zustand «unknown» ist ausdrücklich vorgesehen und wird niemals künstlich
/// zu einer spezifischen Technik erraten.
library;

enum XcModality {
  skiNordicUnknown('ski_nordic_unknown', 'Langlauf (Technik unbekannt)', sportGroup: 'skiing'),
  skiSkating('ski_skating', 'Langlauf Skating', sportGroup: 'skiing'),
  skiClassic('ski_classic', 'Langlauf Klassisch', sportGroup: 'skiing'),
  doublePoling('double_poling', 'Doppelstock (Schnee)', sportGroup: 'skiing'),
  rollerSkiUnknown('roller_ski_unknown', 'Skiroller (Technik unbekannt)', sportGroup: 'skiing'),
  rollerSkiSkating('roller_ski_skating', 'Skiroller Skating', sportGroup: 'skiing'),
  rollerSkiClassic('roller_ski_classic', 'Skiroller Klassisch', sportGroup: 'skiing'),
  rollerSkiDoublePoling('roller_ski_double_poling', 'Skiroller Doppelstock', sportGroup: 'skiing'),
  ercolinaDoublePoling('ercolina_double_poling', 'Ercolina Doppelstock', sportGroup: 'skiing'),
  cycling('cycling', 'Radfahren', sportGroup: 'cycling'),
  running('running', 'Laufen', sportGroup: 'running'),
  strength('strength', 'Krafttraining', sportGroup: 'strength'),
  other('other', 'Sonstige Aktivität', sportGroup: 'generic'),
  unknown('unknown', 'Unbekannte Sportart', sportGroup: 'generic');

  const XcModality(this.key, this.label, {required this.sportGroup});

  final String key;
  final String label;

  /// Übergeordnete Sportartgruppe für Abwärtskompatibilität.
  final String sportGroup;

  bool get isSkiing => sportGroup == 'skiing';
  bool get isErcolina => this == ercolinaDoublePoling;
  bool get isSnowSkiing =>
      this == skiNordicUnknown ||
      this == skiSkating ||
      this == skiClassic ||
      this == doublePoling;
  bool get isRollerSkiing =>
      this == rollerSkiUnknown ||
      this == rollerSkiSkating ||
      this == rollerSkiClassic ||
      this == rollerSkiDoublePoling;
}

enum XcTechnique {
  unknown('unknown', 'Unbekannt'),

  // Skating-Techniken (Gänge 2 bis 5)
  skatingG2('g2_v1', 'Führarm-Skating (G2 / V1 / Berggang)'),
  skatingG3('g3_v2', 'Eintakter (G3 / V2 / 1:1)'),
  skatingG4('g4_v2_alt', 'Zweitakter (G4 / V2 alternate / 2:1)'),
  skatingG5('g5_v_skate', 'Schlittschuhschritt (G5 / ohne Stöcke)'),

  // Doppelstock als eigenständiges Bewegungsmuster (nicht zwingend Classic-Schnee)
  doublePoling('double_poling', 'Doppelstock'),

  // Klassisch-Techniken
  classicDiagonal('diagonal_stride', 'Diagonalschritt'),
  classicDoublePoling('classic_double_poling', 'Klassisch Doppelstock (Schnee)'),
  classicDoublePoleKick('double_pole_kick', 'Doppelstock mit Zwischenschritt'),
  classicHerringbone('herringbone', 'Grätenschritt');

  const XcTechnique(this.key, this.label);

  final String key;
  final String label;
}

/// Herkunft und Evidenzklasse einer Sportart- oder Technikzuordnung.
enum ClassificationProvenance {
  explicitSourceMetadata('explicit_source_metadata', 'Explizite Metadaten'),
  manual('manual', 'Manuelle Eingabe / Korrektur'),
  titleInferred('title_inferred', 'Aus Titel oder Tags abgeleitet'),
  classifierInferred('classifier_inferred', 'Durch Modell klassifiziert'),
  unknown('unknown', 'Unbekannt / Keine Evidenz');

  const ClassificationProvenance(this.key, this.label);

  final String key;
  final String label;
}

