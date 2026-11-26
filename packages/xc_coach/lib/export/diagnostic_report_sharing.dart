/// Turning a stored test into a report somebody can hold.
///
/// Kept apart from [buildDiagnosticReportPdf] on purpose: that function is a
/// pure transformation and is tested as one. This file is the part that talks
/// to the device — it renders the curve, assembles the data and hands the
/// finished document to the operating system's share sheet.
///
/// Nothing here uploads anything. The PDF is built in memory and passed to the
/// system sheet; where it goes from there is the coach's decision, which is
/// exactly where that decision belongs.
library;

import 'dart:typed_data';

import 'package:xc_coach/branding.dart';
import 'package:xc_coach/charts/lactate_curve_chart.dart';
import 'package:xc_coach/export/diagnostic_report.dart';
import 'package:xc_coach/lala/application/lala_view_models.dart';
import 'package:xc_coach/lala/application/threshold_summary.dart';
import 'package:xc_coach/ui/design_system.dart';
import 'dart:ui' show Rect;
import 'package:share_plus/share_plus.dart';

/// Renders and shares the report for one evaluated test.
///
/// Returns false when the test carries no run to report — the caller shows the
/// reason rather than a document that would claim an evaluation happened.
Future<bool> shareDiagnosticReport({
  required Rect origin,
  required String athleteName,
  required LalaTestView test,
  required LalaRunView? run,
  LalaZoneSetView? zoneSet,
  String? organisationName,
}) async {
  final bytes = await buildDiagnosticReportBytes(
    athleteName: athleteName,
    test: test,
    run: run,
    zoneSet: zoneSet,
    organisationName: organisationName,
  );
  if (bytes == null) return false;

  final name = reportFileName(athleteName, test.head.startedAtUtcUs);
  await Share.shareXFiles([XFile.fromData(bytes, mimeType:'application/pdf',name:name)], fileNameOverrides:[name], sharePositionOrigin:origin);
  return true;
}

/// The document itself, without the sharing step. Exposed so a test can check
/// the bytes and so a later «save to files» path does not duplicate this.
Future<Uint8List?> buildDiagnosticReportBytes({
  required String athleteName,
  required LalaTestView test,
  required LalaRunView? run,
  LalaZoneSetView? zoneSet,
  String? organisationName,
}) async {
  if (run == null || test.curve.length < 2) return null;

  final bodyMass = test.data.bodyMassKg;
  final png = await renderLactateCurvePng(
    size: reportCurveSize,
    loadUnit: test.head.loadUnit,
    bodyMassKg: bodyMass,
    series: <LactateSeries>[
      LactateSeries(
        samples: <LactateSample>[
          for (final point in test.curve)
            LactateSample(
              load: point.load,
              lactate: point.lactate,
              heartRateBpm: point.heartRateBpm,
              stageNumber: point.stageNumber,
              excluded: point.excluded,
            ),
        ],
        thresholds: <LactateThreshold>[
          if (run.lt1?.loadValue case final load?)
            LactateThreshold(
              label: 'LT1',
              load: load,
              colour: GiuliaTokens.success,
              lactate: run.lt1?.lactateMmolPerLitre,
            ),
          if (run.lt2?.loadValue case final load?)
            LactateThreshold(
              label: 'LT2',
              load: load,
              colour: GiuliaTokens.warning,
              lactate: run.lt2?.lactateMmolPerLitre,
            ),
        ],
      ),
    ],
  );

  return buildDiagnosticReportPdf(
    DiagnosticReport(
      athleteName: athleteName,
      test: test,
      run: run,
      curvePng: png,
      summary: buildThresholdSummary(
        test: test,
        run: run,
        bodyMassKg: bodyMass,
      ),
      zoneSet: zoneSet ?? (run.zoneSets.isEmpty ? null : run.zoneSets.first),
      bodyMassKg: bodyMass,
      organisationName: organisationName,
    ),
  );
}

/// A file name a coach can find again in a folder of forty of them.
///
/// Name first, then date: sorted alphabetically, one athlete's reports end up
/// together and in chronological order inside that group.
String reportFileName(String athleteName, int startedAtUtcUs) {
  final date = DateTime.fromMicrosecondsSinceEpoch(
    startedAtUtcUs,
    isUtc: true,
  ).toLocal();
  final slug = athleteName
      .trim()
      .replaceAll(RegExp('[^A-Za-zÄÖÜäöüß0-9]+'), '-')
      .replaceAll(RegExp('^-+|-+\$'), '');
  final stamp = '${date.year}-${_two(date.month)}-${_two(date.day)}';
  return '$giuliaWordmark-${slug.isEmpty ? 'Athlet' : slug}-$stamp.pdf';
}

String _two(int value) => value.toString().padLeft(2, '0');
