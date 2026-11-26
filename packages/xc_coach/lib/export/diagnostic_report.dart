/// The diagnostic report: one test, on paper, in the athlete's hands.
///
/// ## Why this is not «print the screen»
///
/// A report leaves the building. It is read months later, next to a report
/// from another laboratory, by somebody who was not in the room. Three things
/// therefore have to survive the trip that a screen may leave implicit:
///
/// 1. **The method.** A threshold without the method that produced it cannot
///    be compared with anything. Every value here names its method, and a
///    fallback says that it was one.
/// 2. **The provenance.** Engine version, run id and both fingerprints. Two
///    reports of the same measurement that disagree must be traceable to the
///    engine that produced them, not argued about.
/// 3. **The limits.** What the numbers do not say is printed, not omitted:
///    a provisional zone boundary, an excluded stage, an estimated LT2.
///
/// ## What it deliberately does not do
///
/// It states no verdict. There is no «gut», no traffic light and no comparison
/// against a population norm the data cannot carry. The report describes one
/// measurement and how it was evaluated; the judgement belongs to the coach
/// who knows the athlete.
library;

import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter/services.dart' show rootBundle;
import 'package:xc_coach/branding.dart';
import 'package:xc_coach/charts/lactate_curve_chart.dart';
import 'package:xc_coach/database/diagnostics_repository.dart';
import 'package:xc_coach/domain/diagnostics.dart';
import 'package:xc_coach/lala/application/lala_view_models.dart';
import 'package:xc_coach/lala/application/threshold_summary.dart';
import 'package:xc_coach/ui/design_system.dart';
import 'package:xc_coach/ui/load_language.dart';
import 'package:xc_coach/ui/orthography.dart';
import 'package:xc_coach/ui/vocabulary.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The size the curve is rendered at, and the ratio the page reserves for it.
///
/// Wide and flat, unlike the screen's near-square plot.
///
/// On A4 the curve gets the full text column, so a phone's aspect ratio would
/// spend a third of the page on one picture and push the audit trail onto a
/// second sheet. At this ratio the whole report — values, curve, zones and
/// provenance — is one page, which is what gets handed over and filed.
///
/// One constant, so the renderer and the page layout cannot disagree.
const Size reportCurveSize = Size(1020, 390);

/// Everything the report prints, already resolved.
///
/// A value object rather than a repository call: the builder must be testable
/// without a database, and a report that silently re-queried could print
/// something other than what the screen showed.
class DiagnosticReport {
  const DiagnosticReport({
    required this.athleteName,
    required this.test,
    required this.run,
    required this.curvePng,
    required this.summary,
    this.zoneSet,
    this.bodyMassKg,
    this.organisationName,
  });

  final String athleteName;
  final LalaTestView test;
  final LalaRunView run;

  /// The curve exactly as the screen draws it, see [renderLactateCurvePng].
  final Uint8List curvePng;

  /// The «Schwellen und Maximalwerte» ladder, derived once.
  final ThresholdSummary summary;

  /// The zone model the coach had selected. Null prints no zone table rather
  /// than silently picking one.
  final LalaZoneSetView? zoneSet;
  final double? bodyMassKg;
  final String? organisationName;

  String get loadUnit => test.head.loadUnit;
}

/// Builds the report as PDF bytes.
///
/// The product's own typeface is embedded rather than using a PDF standard
/// font. The standard fourteen cover no Unicode beyond WinAnsi: an en dash and
/// an ellipsis are already missing, and a zone table whose every boundary
/// needs a dash cannot be set without one. Embedding also means paper and
/// screen set the same line the same way — see [GiuliaTokens.fontFamily].
Future<Uint8List> buildDiagnosticReportPdf(DiagnosticReport report) async {
  final theme = pw.ThemeData.withFont(
    base: pw.Font.ttf(await rootBundle.load('packages/xc_coach/assets/fonts/Roboto-Regular.ttf')),
    bold: pw.Font.ttf(await rootBundle.load('packages/xc_coach/assets/fonts/Roboto-Bold.ttf')),
  );
  final document = pw.Document(
    title: 'Leistungsdiagnostik ${report.athleteName}',
    author: giuliaWordmark,
    subject: 'Laktatstufentest ${_date(report.test.head.startedAtUtcUs)}',
    theme: theme,
  );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(38, 40, 38, 44),
      header: (context) =>
          context.pageNumber == 1 ? pw.SizedBox() : _runningHead(report),
      footer: _footerFor(report),
      build: (context) => <pw.Widget>[
        _title(report),
        pw.SizedBox(height: 13),
        _metadata(report),
        pw.SizedBox(height: 14),
        _thresholds(report),
        pw.SizedBox(height: 14),
        _curve(report),
        pw.SizedBox(height: 15),
        _ladder(report),
        // Ein bewusster Umbruch: Seite eins ist die Messung, Seite zwei die
        // Trainingssteuerung. Ohne ihn beginnt die Bereichstabelle irgendwo
        // und ihre Ueberschrift bleibt als Waise am Fuss der ersten Seite
        // stehen -- `MultiPage` kennt keine Witwen- und Waisenregelung.
        pw.NewPage(),
        if (report.zoneSet case final zones?) ...[
          _zoneTable(report, zones),
          pw.SizedBox(height: 15),
        ],
        _methodOverview(report),
        pw.SizedBox(height: 15),
        _foundation(report),
        if (report.test.head.notes case final notes?
            when notes.trim().isNotEmpty) ...[
          pw.SizedBox(height: 15),
          _remarks(notes.trim()),
        ],
        pw.SizedBox(height: 15),
        _limits(report),
      ],
    ),
  );

  return document.save();
}

// --- Bausteine --------------------------------------------------------------

const _ink = PdfColor.fromInt(0xFF10233F);
const _muted = PdfColor.fromInt(0xFF6C7F99);
const _rule = PdfColor.fromInt(0xFFD9E4F2);
const _accent = PdfColor.fromInt(0xFF1565C0);

pw.TextStyle _label() => pw.TextStyle(
  fontSize: 7.5,
  color: _muted,
  letterSpacing: 1,
  fontWeight: pw.FontWeight.bold,
);

pw.TextStyle _body([double size = 9.5]) =>
    pw.TextStyle(fontSize: size, color: _ink, lineSpacing: 1.6);

pw.Widget _title(DiagnosticReport report) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('LEISTUNGSDIAGNOSTIK', style: _label()),
            pw.SizedBox(height: 4),
            pw.Text(
              report.athleteName,
              style: pw.TextStyle(
                fontSize: 22,
                color: _ink,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              giuliaWordmark,
              style: pw.TextStyle(
                fontSize: 13,
                color: _accent,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            if (report.organisationName case final name?)
              pw.Text(name, style: _body(8)),
          ],
        ),
      ],
    ),
    pw.SizedBox(height: 10),
    pw.Divider(color: _rule, thickness: 1, height: 1),
  ],
);

pw.Widget _runningHead(DiagnosticReport report) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 12),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(report.athleteName, style: _label()),
      pw.Text(
        _date(report.test.head.startedAtUtcUs).toUpperCase(),
        style: _label(),
      ),
    ],
  ),
);

/// The foot of the page, and the whole of the audit trail.
///
/// The full provenance block — run id and two 64-character fingerprints — used
/// to stand on the page. It is the right thing to *store* and the wrong thing
/// to hand an athlete: four lines of hex in the middle of a training document
/// say nothing to the person reading it. What has to survive is that the
/// report can be tied back to the calculation that produced it, and the engine
/// version plus the run's short id do that. The complete fingerprints stay in
/// the app, on the test's detail screen, where whoever needs to verify looks.
pw.BuildCallback _footerFor(DiagnosticReport report) => (pw.Context context) {
  final run = report.run;
  return pw.Column(
    children: [
      pw.Divider(color: _rule, thickness: 1, height: 1),
      pw.SizedBox(height: 5),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '$giuliaWordmark · Trainingssteuerung, kein Medizinprodukt',
            style: const pw.TextStyle(fontSize: 7, color: _muted),
          ),
          pw.Text(
            'LaLa ${run.engineVersion} · Auswertung ${_shortRun(run.id)}',
            style: const pw.TextStyle(fontSize: 7, color: _muted),
          ),
          pw.Text(
            'Seite ${context.pageNumber} von ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7, color: _muted),
          ),
        ],
      ),
    ],
  );
};

/// The tail of a run id: long enough to identify, short enough for a footer.
String _shortRun(String id) =>
    id.length <= 14 ? id : id.substring(id.length - 14);

pw.Widget _metadata(DiagnosticReport report) {
  final head = report.test.head;
  final entries = <(String, String)>[
    ('ZEITPUNKT', _dateTime(head.startedAtUtcUs)),
    ('SPORTART', sportLabel(head.sport)),
    ('PROTOKOLL', protocolLabel(head.protocol)),
    ('MESSQUELLE', measurementSourceLabel(head.measurementSource)),
    if (report.bodyMassKg case final mass?)
      ('KÖRPERMASSE', '${_decimal(mass, 1)} kg'),
  ];
  return pw.Wrap(
    spacing: 26,
    runSpacing: 10,
    children: [
      for (final entry in entries)
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(entry.$1, style: _label()),
            pw.SizedBox(height: 2),
            pw.Text(entry.$2, style: _body()),
          ],
        ),
    ],
  );
}

pw.Widget _thresholds(DiagnosticReport report) => pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Expanded(child: _thresholdBlock(report, report.run.lt1)),
    pw.SizedBox(width: 14),
    pw.Expanded(child: _thresholdBlock(report, report.run.lt2)),
  ],
);

pw.Widget _thresholdBlock(DiagnosticReport report, LalaThresholdView? value) {
  if (value == null) {
    return _panel(
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('—', style: pw.TextStyle(fontSize: 24, color: _muted)),
          pw.SizedBox(height: 4),
          pw.Text(
            'Für diesen Test wurde keine Schwelle bestimmt.',
            style: _body(8.5),
          ),
        ],
      ),
    );
  }
  final spoken = secondaryLoad(
    value.loadValue,
    value.loadUnit,
    bodyMassKg: report.bodyMassKg,
  );
  return _panel(
    pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(value.typeLabel, style: _label()),
            if (value.origin != LalaMethodOrigin.standard)
              pw.Text(
                value.origin == LalaMethodOrigin.fallback
                    ? 'FALLBACK'
                    : 'EXPERTENWAHL',
                style: _label().copyWith(color: _accent),
              ),
          ],
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          value.loadLabel,
          style: pw.TextStyle(
            fontSize: 21,
            color: _ink,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        if (spoken != null)
          pw.Text(spoken, style: _body(11).copyWith(color: _muted)),
        pw.SizedBox(height: 6),
        // The method belongs *next to* the value, never in a legend: a
        // threshold read without its method is not comparable with anything.
        pw.Text(germanLabel(value.methodLabel), style: _body(9)),
        pw.SizedBox(height: 6),
        pw.Text(
          <String>[
            if (value.heartRateBpm case final hr?) '$hr bpm',
            if (value.lactateMmolPerLitre case final la?)
              '${_decimal(la, 2)} mmol/l',
          ].join('  ·  '),
          style: _body(9).copyWith(color: _muted),
        ),
      ],
    ),
  );
}

pw.Widget _curve(DiagnosticReport report) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Text('LAKTAT-LEISTUNGS-KURVE', style: _label()),
    pw.SizedBox(height: 6),
    // Ueber das Seitenverhaeltnis, nicht ueber `fit`: Ein `pw.Image` nimmt
    // ohne Vorgabe seine Pixelmasse als Punkte an. Die Kurve wird mit
    // dreifacher Aufloesung gerendert und waere damit 1140 pt hoch -- hoeher
    // als eine A4-Seite. Der Fehler kommt dann als Umbruchabbruch heraus und
    // nicht als das, was er ist.
    pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _rule)),
      child: pw.AspectRatio(
        aspectRatio: reportCurveSize.width / reportCurveSize.height,
        child: pw.Image(pw.MemoryImage(report.curvePng), fit: pw.BoxFit.fill),
      ),
    ),
    pw.SizedBox(height: 5),
    pw.Text(
      'Messpunkte sind geradlinig verbunden; es wird bewusst keine geglättete '
      'Kurve gezeichnet. Eine ausgeschlossene Stufe ist hohl eingezeichnet.',
      style: _body(8).copyWith(color: _muted),
    ),
  ],
);

/// «Schwellen und Maximalwerte»: the ladder from exhaustion downwards.
///
/// Two numbers do not describe an athlete. The same LT2 above two different
/// maxima calls for two different training plans, and only the ladder — every
/// rung as a share of *this* test's maximum — makes that visible.
///
/// The rows are typed, and the typography says which is which: the maximum is
/// measured, a fixed concentration is a convention, and only LT1 and LT2 are
/// the product of a method. Printing them in one undifferentiated table would
/// suggest they carry the same weight.
pw.Widget _ladder(DiagnosticReport report) {
  final summary = report.summary;
  if (summary.isEmpty) return pw.SizedBox();
  final unit = report.loadUnit;
  final isPower = LoadUnits.isPower(unit);
  // Die zweite Lesart auch hier: W/kg beim Radfahren, Tempo beim Laufen. Eine
  // Leiter, die einem Laufcoach nur km/h zeigt, laesst ihn sechs Zeilen lang
  // umrechnen.
  final secondUnit = secondaryLoadUnit(unit, bodyMassKg: report.bodyMassKg);

  String percent(double? share) => share == null
      ? ''
      : '${(share * 100).toStringAsFixed(1).replaceAll('.', ',')} %';

  pw.Widget cell(
    String text,
    int flex, {
    bool head = false,
    bool bold = false,
  }) => pw.Expanded(
    flex: flex,
    child: pw.Text(
      text,
      style: head
          ? _label()
          : _body(9).copyWith(
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
    ),
  );

  pw.Widget line(ThresholdSummaryRow row) {
    final isThreshold = row.kind == ThresholdSummaryKind.threshold;
    final isMaximum = row.kind == ThresholdSummaryKind.maximum;
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 1.5),
      padding: const pw.EdgeInsets.fromLTRB(8, 4.5, 6, 4.5),
      decoration: pw.BoxDecoration(
        color: isMaximum
            ? const PdfColor.fromInt(0xFFF0F4FA)
            : isThreshold
            ? const PdfColor.fromInt(0xFFEAF2FF)
            : null,
      ),
      child: pw.Row(
        children: [
          cell(row.label, 4, bold: isThreshold || isMaximum),
          cell(germanLabel(row.methodLabel ?? ''), 6),
          cell(
            row.heartRateBpm == null ? '' : '${row.heartRateBpm}',
            2,
            bold: isThreshold,
          ),
          cell(percent(row.heartRatePercentOfMaximum), 2),
          cell(_decimal(row.load, isPower ? 0 : 1), 2, bold: isThreshold),
          cell(percent(row.loadPercentOfMaximum), 2),
          cell(row.lactate == null ? '' : _decimal(row.lactate!, 2), 2),
          if (secondUnit != null)
            cell(
              secondaryLoadNumber(
                    row.load,
                    unit,
                    bodyMassKg: report.bodyMassKg,
                  ) ??
                  '',
              2,
            ),
        ],
      ),
    );
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('SCHWELLEN UND MAXIMALWERTE', style: _label()),
      pw.SizedBox(height: 5),
      pw.Padding(
        padding: const pw.EdgeInsets.only(left: 8, right: 6, bottom: 2),
        child: pw.Row(
          children: [
            cell('', 4, head: true),
            cell('METHODE', 6, head: true),
            cell('HF', 2, head: true),
            cell('% HFmax', 2, head: true),
            cell(isPower ? 'WATT' : unit.toUpperCase(), 2, head: true),
            cell('% MAX', 2, head: true),
            cell('LAKTAT', 2, head: true),
            if (secondUnit != null)
              cell(secondUnit.toUpperCase(), 2, head: true),
          ],
        ),
      ),
      for (final row in summary.rows) line(row),
      pw.SizedBox(height: 5),
      pw.Text(
        <String>[
          if (summary.anaerobicReserve case final reserve?)
            'Anaerobe Reserve  ${_decimal(reserve, isPower ? 0 : 1)} $unit'
                '${summary.anaerobicReserveRelative == null ? '' : ' · '
                          '${_decimal(summary.anaerobicReserveRelative!, 2)} W/kg'}'
                '${summary.anaerobicReservePercent == null ? '' : ' · '
                          '${percent(summary.anaerobicReservePercent)} des Maximums'}',
          if (summary.maximumHeartRateBpm case final hr?)
            'Ausbelastung  $hr bpm'
                '${summary.maximumLactate == null ? '' : ' · '
                          '${_decimal(summary.maximumLactate!, 1)} mmol/l Maximallaktat'}',
        ].join('\n'),
        style: _body(8.5).copyWith(color: _muted),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        'Die Zeilen mit fester Laktatkonzentration sind eine Konvention, keine '
        'Schwellenbestimmung: Sie sagen, bei welcher Belastung dieser Athlet '
        'diesen Wert erreicht hat. Nur LT1 und LT2 tragen eine Methode.',
        style: _body(7.5).copyWith(color: _muted),
      ),
    ],
  );
}

pw.Widget _zoneTable(DiagnosticReport report, LalaZoneSetView zones) {
  final caption = secondaryLoadCaption(
    zones.loadUnit,
    bodyMassKg: report.bodyMassKg,
  );
  final isPower = LoadUnits.isPower(zones.loadUnit);
  final count = zones.zones.length;

  pw.Widget cell(String text, {bool head = false, int flex = 1}) => pw.Expanded(
    flex: flex,
    child: pw.Text(text, style: head ? _label() : _body(9)),
  );

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('INDIVIDUELLE TRAININGSBEREICHE', style: _label()),
          pw.Text(zones.modelName, style: _body(9)),
        ],
      ),
      pw.SizedBox(height: 5),
      pw.Padding(
        padding: const pw.EdgeInsets.only(left: 9, right: 6, bottom: 3),
        child: pw.Row(
          children: [
            cell('BEREICH', head: true, flex: 5),
            cell(isPower ? 'LEISTUNG' : 'GESCHWINDIGKEIT', head: true, flex: 3),
            if (caption != null) cell(caption, head: true, flex: 3),
            cell('HERZFREQUENZ', head: true, flex: 3),
          ],
        ),
      ),
      // Farbige Baender ueber die volle Breite: Die Intensitaet ist damit
      // ablesbar, bevor eine einzige Zahl gelesen wurde. Der Farbbalken links
      // ist gesaettigt, die Flaeche nur getoent -- ein volltoniges Band traegt
      // keinen dunklen Text mehr.
      for (final entry in zones.zones.indexed)
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 2),
          decoration: pw.BoxDecoration(
            color: _pdf(giuliaZoneTint(entry.$1, count)),
            border: pw.Border(
              left: pw.BorderSide(
                color: _pdf(giuliaZoneColour(entry.$1, count)),
                width: 5,
              ),
            ),
          ),
          padding: const pw.EdgeInsets.fromLTRB(9, 6, 6, 6),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(
                flex: 5,
                child: pw.RichText(
                  text: pw.TextSpan(
                    children: [
                      pw.TextSpan(
                        text: entry.$2.name,
                        style: _body(
                          9,
                        ).copyWith(fontWeight: pw.FontWeight.bold),
                      ),
                      if (entry.$2.code case final code?)
                        pw.TextSpan(
                          text: '  $code',
                          style: _body(8.5).copyWith(color: _muted),
                        ),
                      if (entry.$2.provisionalBoundary)
                        pw.TextSpan(text: '  °', style: _body(9)),
                    ],
                  ),
                ),
              ),
              cell(
                _range(
                  entry.$2.lowerLoadDisplay,
                  entry.$2.upperLoadDisplay,
                  zones.loadUnit,
                ),
                flex: 3,
              ),
              if (caption != null)
                cell(
                  secondaryLoadRange(
                        entry.$2.lowerLoadDisplay,
                        entry.$2.upperLoadDisplay,
                        zones.loadUnit,
                        bodyMassKg: report.bodyMassKg,
                      ) ??
                      '',
                  flex: 3,
                ),
              cell(
                _rangeInt(
                  entry.$2.lowerHeartRateDisplay,
                  entry.$2.upperHeartRateDisplay,
                  'bpm',
                ),
                flex: 3,
              ),
            ],
          ),
        ),
      if (zones.hasProvisionalBoundary) ...[
        pw.SizedBox(height: 4),
        pw.Text(
          '°  Diese Grenze hat LaLa als vorläufig gekennzeichnet.',
          style: _body(8).copyWith(color: _muted),
        ),
      ],
    ],
  );
}

/// A Flutter colour as a PDF colour. One conversion, so the zone ramp is
/// literally the same values on screen and on paper.
PdfColor _pdf(Color colour) => PdfColor(colour.r, colour.g, colour.b, colour.a);

/// Every method the engine ran, and what it produced.
///
/// This is the section a second laboratory reads first. LT2 determined by
/// Modified Dmax and LT2 determined by Dickhuth are not the same number for
/// the same athlete — here they stand under each other, so the reader sees how
/// much of the result is the measurement and how much is the choice of method.
///
/// Hiding that spread would make the report look more certain than the data
/// is. A method that could not be determined is listed too, with the reason
/// in one word, because «not applicable to this protocol» is a finding.
pw.Widget _methodOverview(DiagnosticReport report) {
  final unit = report.loadUnit;
  final digits = LoadUnits.isPower(unit) ? 0 : 1;
  final determined =
      report.run.allThresholds.where((t) => t.loadValue != null).toList()
        ..sort((a, b) {
          final byType = a.type.compareTo(b.type);
          return byType != 0 ? byType : a.loadValue!.compareTo(b.loadValue!);
        });
  if (determined.isEmpty) return pw.SizedBox();

  final missing = report.run.methodsWithoutResult.length;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('ALLE BERECHNETEN METHODEN', style: _label()),
      pw.SizedBox(height: 5),
      for (final type in <String>['lt1', 'lt2'])
        if (determined.any((t) => t.type == type)) ...[
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3, bottom: 2),
            child: pw.Text(
              type == 'lt1' ? 'Untere Schwelle (LT1)' : 'Obere Schwelle (LT2)',
              style: _body(9).copyWith(fontWeight: pw.FontWeight.bold),
            ),
          ),
          for (final threshold in determined.where((t) => t.type == type))
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 1.5),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    flex: 9,
                    child: pw.Text(
                      germanLabel(threshold.methodLabel),
                      style: _body(8.5).copyWith(
                        color: _isSelected(report, threshold) ? _ink : _muted,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(
                      '${_decimal(threshold.loadValue!, digits)} $unit',
                      style: _body(8.5).copyWith(
                        fontWeight: _isSelected(report, threshold)
                            ? pw.FontWeight.bold
                            : pw.FontWeight.normal,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(
                      threshold.heartRateBpm == null
                          ? ''
                          : '${threshold.heartRateBpm} bpm',
                      style: _body(8.5).copyWith(color: _muted),
                    ),
                  ),
                  pw.Expanded(
                    flex: 4,
                    child: pw.Text(
                      _isSelected(report, threshold)
                          ? 'im Bericht verwendet'
                          : '',
                      style: _body(7.5).copyWith(color: _accent),
                    ),
                  ),
                ],
              ),
            ),
        ],
      pw.SizedBox(height: 5),
      pw.Text(
        'Die Spannweite zwischen diesen Werten gehört zum Ergebnis: Sie zeigt, '
        'wie stark die Zahl von der Wahl des Verfahrens abhängt. Ein Vergleich '
        'mit einem früheren Test ist nur innerhalb derselben Methode gültig.'
        '${missing == 0 ? '' : ' $missing weitere Verfahren waren mit diesem '
                  'Stufenprotokoll nicht bestimmbar.'}',
        style: _body(7.5).copyWith(color: _muted),
      ),
    ],
  );
}

bool _isSelected(DiagnosticReport report, LalaThresholdView threshold) =>
    threshold.methodId == report.run.lt1?.methodId ||
    threshold.methodId == report.run.lt2?.methodId;

/// What the evaluation stood on: stages, samples, protocol.
pw.Widget _foundation(DiagnosticReport report) {
  final points = report.test.curve;
  final excluded = points.where((p) => p.excluded).length;
  final durations = report.test.data.stages
      .map((stage) => stage.durationSeconds)
      .toSet();
  final facts = <(String, String)>[
    (
      'MESSPUNKTE',
      '${points.length} von ${report.run.stageCount} Stufen '
          'mit Laktatprobe',
    ),
    (
      'EINBEZOGENE STUFEN',
      excluded == 0
          ? 'Keine Stufe ausgeschlossen'
          : '$excluded Stufe${excluded == 1 ? '' : 'n'} ausgeschlossen',
    ),
    if (durations.length == 1) ('STUFENDAUER', '${durations.first} s'),
    if (report.test.head.stageIncrementHint case final step?)
      (
        'STEIGERUNG',
        '${_decimal(step, LoadUnits.isPower(report.loadUnit) ? 0 : 1)} '
            '${report.loadUnit} je Stufe',
      ),
  ];
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('DATENGRUNDLAGE', style: _label()),
      pw.SizedBox(height: 5),
      pw.Wrap(
        spacing: 24,
        runSpacing: 7,
        children: [
          for (final fact in facts)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(fact.$1, style: _label()),
                pw.SizedBox(height: 2),
                pw.Text(fact.$2, style: _body(8.5)),
              ],
            ),
        ],
      ),
    ],
  );
}

/// The diagnostician's own words.
///
/// GIULIA states no verdict — «mittelmäßig» or «ausbaufähig» is a judgement,
/// and a judgement needs an author who knows the athlete. What the report can
/// do is carry that author's text and mark it as theirs.
pw.Widget _remarks(String notes) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Text('BEMERKUNGEN UND HINWEISE', style: _label()),
    pw.SizedBox(height: 5),
    pw.Container(
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        border: pw.Border(left: pw.BorderSide(color: _accent, width: 3)),
        color: const PdfColor.fromInt(0xFFF5F8FD),
      ),
      // Ohne Rechtschreibkorrektur, anders als bei Text aus dem Kern.
      //
      // Der Unterschied ist kein technischer: Die Zeichenketten des Kerns sind
      // eingefroren und niemand hat sie fuer diesen Bericht geschrieben. Diese
      // Zeilen dagegen hat ein Mensch getippt, und sie stehen unter seiner
      // Ueberschrift. Sie im Druck stillschweigend umzuschreiben hiesse, den
      // Verfasser zu korrigieren, ohne ihn zu fragen.
      child: pw.Text(notes, style: _body(9)),
    ),
  ],
);

/// What this report does **not** say — printed, not left out.
pw.Widget _limits(DiagnosticReport report) {
  final excluded = report.test.curve.where((point) => point.excluded).toList();
  final notices = <String>[
    for (final threshold in <LalaThresholdView?>[
      report.run.lt1,
      report.run.lt2,
    ])
      if (threshold?.originNotice case final notice?) germanSpelling(notice),
    if (excluded.isNotEmpty)
      '${excluded.length} Stufe${excluded.length == 1 ? '' : 'n'} '
          'wurde${excluded.length == 1 ? '' : 'n'} von der Auswertung '
          'ausgeschlossen und ist in der Kurve hohl eingezeichnet.',
    for (final issue in report.zoneSet?.issues ?? const <PersistedZoneIssue>[])
      germanSpelling(issue.message),
    'Dieser Bericht beschreibt eine Messung und ihre Auswertung. Er enthält '
        'keine sportwissenschaftliche Beurteilung des Testtags und keine '
        'medizinische Aussage.',
  ];
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('WAS DIESER BERICHT NICHT SAGT', style: _label()),
      pw.SizedBox(height: 6),
      for (final notice in notices)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('·  ', style: _body(8.5).copyWith(color: _muted)),
              pw.Expanded(
                child: pw.Text(
                  notice,
                  style: _body(8.5).copyWith(color: _muted),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

// Ohne `width: double.infinity`: In einer `MultiPage` bekommt ein Kind keine
// feste Breite vorgegeben, und ein Container, der unendlich breit sein will,
// passt dort auf keine Seite -- die Umbruchschleife endet dann in
// `TooManyPagesException` statt in einem Fehler, der sagt, was los ist.
pw.Widget _panel(pw.Widget child) => pw.Container(
  padding: const pw.EdgeInsets.all(11),
  decoration: pw.BoxDecoration(
    border: pw.Border.all(color: _rule),
    borderRadius: pw.BorderRadius.circular(7),
  ),
  child: child,
);

// --- Formatierung -----------------------------------------------------------

String _range(double? from, double? to, String unit) {
  if (from == null && to == null) return '—';
  final digits = LoadUnits.isPower(unit) ? 0 : 1;
  if (from == null) return 'bis ${_decimal(to!, digits)} $unit';
  if (to == null) return 'ab ${_decimal(from, digits)} $unit';
  return '${_decimal(from, digits)} – ${_decimal(to, digits)} $unit';
}

String _rangeInt(int? from, int? to, String unit) {
  if (from == null && to == null) return '—';
  if (from == null) return 'bis $to $unit';
  if (to == null) return 'ab $from $unit';
  return '$from – $to $unit';
}

String _decimal(double value, int digits) =>
    value.toStringAsFixed(digits).replaceAll('.', ',');

String _date(int utcMicroseconds) {
  final date = DateTime.fromMicrosecondsSinceEpoch(
    utcMicroseconds,
    isUtc: true,
  ).toLocal();
  return '${_two(date.day)}.${_two(date.month)}.${date.year}';
}

String _dateTime(int utcMicroseconds) {
  final date = DateTime.fromMicrosecondsSinceEpoch(
    utcMicroseconds,
    isUtc: true,
  ).toLocal();
  return '${_date(utcMicroseconds)}, ${_two(date.hour)}:${_two(date.minute)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
