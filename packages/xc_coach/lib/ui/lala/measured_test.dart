/// Der Gerätezugang — als Loch, nicht als Typ.
///
/// ## Warum LaLa das Gerät nicht nennt
///
/// LaLa ist geräteunabhängig. Ein gemessener Stufentest ist ein Angebot, kein
/// Bestandteil: Wo ein Gerät im Arbeitsbereich liegt, wird gemessen; wo keins
/// liegt, wird derselbe Test von Hand eingetragen und von derselben Auswertung
/// bewertet.
///
/// Stünde hier `ErcolinaTestLauncher`, zöge das Produkt LaLa über diesen einen
/// Typ den Ercolina-Treiber, den Funk und die Sensorkette mit — für einen
/// Bildschirm, den es nie zeigt. Deshalb steht hier nur, **was** der Zugang
/// kann, und der Bildschirm, den er öffnet, kommt von dem, der das Gerät
/// mitbringt (siehe `products/workbench_surface.dart`).
library;

import 'package:flutter/material.dart';

import '../../lala/application/lala_controller.dart';
import '../../measurement/contracts/test_protocol.dart';

/// Was ein gemessener Vorgang braucht: für wen, womit, und wohin danach.
class MeasuredTestRequest {
  const MeasuredTestRequest({
    required this.lala,
    required this.athleteId,
    required this.athleteName,
    required this.protocol,
    this.onOpenResult,
  });

  final LalaController lala;
  final String athleteId;
  final String athleteName;
  final TestProtocol protocol;

  /// Was geschieht, wenn der Vorgang ein Ergebnis hat.
  final ValueChanged<String>? onOpenResult;
}

/// Ob und wie dieses Produkt messen kann.
class MeasuredTestAccess {
  const MeasuredTestAccess({
    required this.hasDevices,
    required this.session,
    required this.stepTest,
  });

  /// Ob überhaupt ein Gerät eingerichtet ist. Ohne Gerät bleibt der gemessene
  /// Weg sichtbar verschlossen, statt still zu fehlen.
  final bool hasDevices;

  /// Der geführte Vorgang: Vorbereitung · Messung · Ergebnis.
  final Widget Function(MeasuredTestRequest request) session;

  /// Derselbe Test, kürzer: nur der Stufentest am Gerät.
  final Widget Function(MeasuredTestRequest request) stepTest;
}
