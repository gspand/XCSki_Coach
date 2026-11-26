/// Ein Messvertrag der GIULIA-Plattform.
///
/// ## Warum diese Verträge nicht in LaLa liegen
///
/// Weil sonst kein Gerät gebaut werden kann, ohne die Diagnostik mitzuliefern.
/// Die Gerätesoftware schreibt Stufen, Proben und Sitzungen; die Diagnostik
/// liest sie. Beide sprechen diesen Vertrag, und keines der beiden kennt das
/// andere:
///
/// ```text
///   Ercolina ──▶  Measurement  ◀── LaLa
/// ```
///
/// Für einen OEM-Vertrag ist das der Unterschied zwischen «die Diagnostik ist
/// unsichtbar» und «die Diagnostik ist nicht im Artefakt».
library;

import 'package:xc_coach/domain/diagnostics.dart';

/// One lactate measurement.
///
/// [stageId] is nullable because rest, warm-up and recovery samples belong to
/// the test but to no regular step. Only stage-bound samples take part in the
/// analysis.
class PersistedLactateSample {
  const PersistedLactateSample({
    required this.id,
    required this.lactateMmolPerLitre,
    required this.sampledAtUtcUs,
    required this.context,
    this.stageId,
    this.site = LactateSampleSite.unknown,
    this.enteredByUserId,
    this.note,
  });

  final String id;
  final String? stageId;
  final double lactateMmolPerLitre;
  final int sampledAtUtcUs;
  final LactateSampleContext context;
  final LactateSampleSite site;
  final String? enteredByUserId;
  final String? note;
}
