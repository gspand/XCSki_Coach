library;

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../charts/nice_scale.dart';
import '../../core/models.dart';
import '../../database/session_repository.dart';
import '../../export/session_export.dart';
import '../../metrics/cumulative_counter.dart';
import '../design_system.dart';

/// Vollständige, gespeicherte Messanalyse einer abgeschlossenen Einheit.
class SessionInspectorScreen extends StatelessWidget {
  const SessionInspectorScreen({
    super.key,
    required this.sessionId,
    required this.sessions,
  });

  final String sessionId;
  final SessionRepository sessions;

  @override
  Widget build(BuildContext context) {
    final inspection = sessions.inspectSession(sessionId);
    final samples = sessions.loadRawSamples(sessionId);
    final strokes = sessions.loadStrokes(sessionId);
    final quality = inspection.quality;
    return Scaffold(
      appBar: AppBar(title: const Text('Datenanalyse')),
      body: ListView(
        padding: GiuliaDensity.of(context).pageInsets,
        children: [
          _Section(
            title: 'Aufzeichnung',
            rows: {
              'Session': inspection.sessionId,
              'Status': inspection.recordingState.name,
              'Dauer': '${inspection.duration.inSeconds} s',
              'RAW-Systemframes': '${inspection.rawDeviceFrameCount}',
              'Dekodierte Samples': '${inspection.rawSampleCount}',
              'Erkannte Züge': '${inspection.strokeCount}',
              'Datenformat': inspection.dataFormatVersion,
              'Algorithmus': inspection.algorithmVersion,
              'App': inspection.appVersion ?? 'unbekannt',
            },
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Datenqualität',
            rows: {
              'Empfangen / erwartet':
                  '${quality.receivedPackets} / ${quality.expectedPackets}',
              'Verloren':
                  '${quality.lostPackets} (${quality.packetLossPercent.toStringAsFixed(3)} %)',
              'Ungültig / doppelt':
                  '${quality.invalidPackets} / ${quality.duplicatePackets}',
              'Außer Reihenfolge': '${quality.outOfOrderPackets}',
              'BLE-Unterbrechungen': '${quality.bleInterruptions}',
              'Längste Lücke':
                  '${(quality.longestGapUs / 1000).toStringAsFixed(1)} ms',
              'Datenmenge': '${quality.byteCount} Bytes',
              'Nicht gespeicherte Aufzeichnungsereignisse':
                  '${quality.recordingFailureCount}',
              'Systemrate': quality.observedRateHz == null
                  ? '—'
                  : '${quality.observedRateHz!.toStringAsFixed(1)} Hz',
            },
          ),
          const SizedBox(height: 16),
          for (final side in SensorSide.values) ...[
            _SideSection(
              side: side,
              statistics: inspection.sideStatistics[side]!,
            ),
            const SizedBox(height: 16),
          ],
          _RawPowerChart(samples: samples),
          const SizedBox(height: 16),
          _OpticalStrokeSection(samples: samples, strokes: strokes),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _exportComplete(context, inspection),
                icon: const Icon(Icons.save_alt),
                label: const Text('GIULIA RAW exportieren'),
              ),
              OutlinedButton.icon(
                onPressed: () => _exportCsv(context),
                icon: const Icon(Icons.table_view_outlined),
                label: const Text('Samples als CSV'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _exportComplete(
    BuildContext context,
    SessionInspection inspection,
  ) async {
    final chunks = SessionExport.completeSessionChunks(
      inspection: inspection,
      deviceFrames: sessions.iterateRawDeviceFrames(sessionId),
      sensorFrames: sessions.iterateRawFrames(sessionId),
      samples: sessions.iterateRawSamples(sessionId),
      strokes: sessions.loadStrokes(sessionId),
      events: sessions.loadEvents(sessionId),
      heartRates: sessions.loadHeartRates(sessionId),
      intervals: sessions.loadIntervals(sessionId),
      derivedSamples: sessions.database.readPages(
        'SELECT * FROM derived_sample WHERE session_id = ? ORDER BY rowid',
        [sessionId],
      ),
      storedSession: sessions.database.raw.select(
        'SELECT * FROM xc_session WHERE id = ?',
        [sessionId],
      ).single,
    );
    Directory? temporary;
    try {
      temporary = await (await getTemporaryDirectory()).createTemp(
        'giulia-export-',
      );
      final name = '$sessionId.giulia-raw.json';
      final output = File('${temporary.path}/$name').openWrite();
      try {
        var pendingChars = 0;
        for (final chunk in chunks) {
          output.write(chunk);
          pendingChars += chunk.length;
          if (pendingChars >= 65536) {
            await output.flush();
            pendingChars = 0;
            // Yield between bounded batches; the share screen stays responsive.
            await Future<void>.delayed(Duration.zero);
          }
        }
        await output.flush();
      } finally {
        await output.close();
      }
      if (!context.mounted) return;
      await _saveFile(
        context,
        name,
        XFile('${temporary.path}/$name', mimeType: 'application/json'),
      );
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export fehlgeschlagen: $error')),
        );
      }
    } finally {
      if (temporary != null) await temporary.delete(recursive: true);
    }
  }

  Future<void> _exportCsv(BuildContext context) => _save(
    context,
    '$sessionId.samples.csv',
    SessionExport.rawSamplesCsv(sessions.loadRawSamples(sessionId)),
  );

  static Future<void> _save(
    BuildContext context,
    String name,
    String contents,
  ) async {
    final file = XFile.fromData(
      Uint8List.fromList(utf8.encode(contents)),
      name: name,
      mimeType: name.endsWith('.csv') ? 'text/csv' : 'application/json',
    );
    await _saveFile(context, name, file);
  }

  static Future<void> _saveFile(
    BuildContext context,
    String name,
    XFile file,
  ) async {
    // iOS bietet für `getSaveLocation` keinen Desktop-Dateidialog. Das
    // Teilen-Blatt übergibt die Datei an Dateien, AirDrop oder Mail, ohne
    // dass die App einen unzugänglichen Sandbox-Pfad behauptet.
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      final box = context.findRenderObject() as RenderBox?;
      final result = await Share.shareXFiles(
        [file],
        subject: name,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.status == ShareResultStatus.dismissed
                ? 'Export abgebrochen.'
                : 'Export an Teilen übergeben.',
          ),
        ),
      );
      return;
    }
    final location = await getSaveLocation(suggestedName: name);
    if (location == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export nicht gespeichert.')),
      );
      return;
    }
    await file.saveTo(location.path);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Export gespeichert: ${location.path}')),
    );
  }
}

class _SideSection extends StatelessWidget {
  const _SideSection({required this.side, required this.statistics});

  final SensorSide side;
  final SessionSideStatistics statistics;

  @override
  Widget build(BuildContext context) => _Section(
    title: side == SensorSide.left ? 'LEFT' : 'RIGHT',
    rows: {
      'Samples': '${statistics.sampleCount}',
      'Kraft min / max': _range(
        statistics.minForceNewton,
        statistics.maxForceNewton,
        'N',
      ),
      'Geschwindigkeit min / max': _range(
        _kmh(statistics.minVelocityMetresPerSecond),
        _kmh(statistics.maxVelocityMetresPerSecond),
        'km/h',
      ),
      'Leistung min / max': _range(
        statistics.minPowerWatt,
        statistics.maxPowerWatt,
        'W',
      ),
      'QRE/ADC roh min / max': statistics.minOpticalRaw == null
          ? 'vom Firmwareformat nicht geliefert'
          : '${statistics.minOpticalRaw} – ${statistics.maxOpticalRaw}',
      'Hall-Events':
          statistics.hallEventCount?.toString() ??
          'vom Firmwareformat nicht geliefert',
      'Batterie': statistics.batteryMillivolts == null
          ? '—'
          : '${statistics.batteryMillivolts} mV',
      'Verpasste Samples / ADC-Fehler':
          '${statistics.missedSamples ?? '—'} / ${statistics.adcErrors ?? '—'}',
    },
  );

  static String _range(double? min, double? max, String unit) => min == null
      ? '—'
      : '${min.toStringAsFixed(2)} – ${max!.toStringAsFixed(2)} $unit';
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final row in rows.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(row.key)),
                const SizedBox(width: 12),
                Flexible(child: Text(row.value, textAlign: TextAlign.end)),
              ],
            ),
          ),
      ],
    ),
  );
}

class _RawPowerChart extends StatelessWidget {
  const _RawPowerChart({required this.samples});
  final List<RawSensorSample> samples;

  @override
  Widget build(BuildContext context) {
    if (samples.length < 2) {
      return const _Section(
        title: 'Leistung über der Zeit',
        rows: {'Zeitreihe': 'Zu wenig gespeicherte Samples.'},
      );
    }
    final maximum = samples.fold<double>(
      0,
      (value, sample) => value > sample.powerWatt ? value : sample.powerWatt,
    );
    final scale = NiceScale.forRange(0, maximum, includeZero: true);
    final firstUs = samples.first.receivedAtUs;
    final lastUs = samples.last.receivedAtUs;
    final elapsedUs = (lastUs - firstUs).clamp(1, 1 << 62);
    final text = Theme.of(context).textTheme;
    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Leistung über der Zeit', style: text.titleMedium),
          const SizedBox(height: 4),
          Row(
            children: [
              const _ChartLegend(label: 'LINKS', color: GiuliaTokens.sideLeft),
              const SizedBox(width: 12),
              const _ChartLegend(
                label: 'RECHTS',
                color: GiuliaTokens.sideRight,
              ),
              const Spacer(),
              Text(
                '${scale.format(scale.min)}–${scale.format(scale.max)} W',
                style: text.bodySmall?.copyWith(
                  color: GiuliaTokens.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 210,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 42,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final tick in scale.ticks.reversed)
                        Text(
                          scale.format(tick),
                          style: text.labelSmall?.copyWith(
                            color: GiuliaTokens.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: CustomPaint(
                          painter: _RawPowerPainter(
                            samples: samples,
                            scale: scale,
                            firstUs: firstUs,
                            elapsedUs: elapsedUs,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _TimeLabel(value: 0),
                          _TimeLabel(value: elapsedUs ~/ 2),
                          _TimeLabel(value: elapsedUs),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Zeit seit Aufzeichnungsbeginn · Leistung in Watt',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: GiuliaTokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 10, height: 10, color: color),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel({required this.value});
  final int value;

  @override
  Widget build(BuildContext context) {
    final seconds = value ~/ Duration.microsecondsPerSecond;
    return Text(
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: GiuliaTokens.textSecondary),
    );
  }
}

class _RawPowerPainter extends CustomPainter {
  _RawPowerPainter({
    required this.samples,
    required this.scale,
    required this.firstUs,
    required this.elapsedUs,
  });
  final List<RawSensorSample> samples;
  final NiceScale scale;
  final int firstUs;
  final int elapsedUs;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = GiuliaTokens.chartGrid
      ..strokeWidth = 1;
    final ticks = scale.ticks;
    for (var index = 0; index < ticks.length; index++) {
      final y = size.height * index / (ticks.length - 1);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (final side in SensorSide.values) {
      final path = Path();
      var started = false;
      // At most one point per horizontal pixel; this affects only the picture,
      // never the stored or exported stream.
      var priorX = -2.0;
      for (final sample in samples) {
        if (sample.side != side) continue;
        final x = (sample.receivedAtUs - firstUs) / elapsedUs * size.width;
        if (x - priorX < 1 && sample != samples.last) continue;
        final y = size.height * (1 - scale.normalize(sample.powerWatt));
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
        priorX = x;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = side == SensorSide.left
              ? GiuliaTokens.sideLeft
              : GiuliaTokens.sideRight
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_RawPowerPainter oldDelegate) =>
      oldDelegate.samples != samples || oldDelegate.scale != scale;
}

class _OpticalStrokeSection extends StatelessWidget {
  const _OpticalStrokeSection({required this.samples, required this.strokes});

  final List<RawSensorSample> samples;
  final List<Stroke> strokes;

  @override
  Widget build(BuildContext context) {
    final hasOptical = samples.any(
      (sample) => sample.opticalRaw != null && sample.mappedTimeUs != null,
    );
    final counterSamples = samples
        .where((sample) => sample.flywheelRevolutions != null)
        .toList(growable: false);
    final hasCounter = counterSamples.length > 1;
    final hasAngularVelocity = samples.any(
      (sample) =>
          sample.angularVelocityRadPerSecond != null &&
          sample.mappedTimeUs != null,
    );
    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Zug und Optik', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          _StrokeTechniqueSummary(strokes: strokes),
          const SizedBox(height: 6),
          Text(
            hasOptical
                ? 'Bänder: gespeicherte Züge. Vertikale Marker: Firmware-Zugereignisse. Linien: optischer ADC-Rohwert.'
                : 'Dieses Archiv enthält keine ausgerichteten optischen ADC-Rohwerte.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 210,
            child: _OpticalStrokeChart(samples: samples, strokes: strokes),
          ),
          const SizedBox(height: 10),
          Text(
            hasAngularVelocity
                ? 'Mechanische Drehzahl aus validierten optischen Perioden'
                : 'Mechanische Drehzahl: erst ab Firmware 0.21 verfügbar.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (hasAngularVelocity) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 130,
              child: _AngularVelocityChart(samples: samples),
            ),
          ],
          const SizedBox(height: 10),
          _CounterSummary(samples: counterSamples, hasCounter: hasCounter),
          const SizedBox(height: 6),
          Text(
            'Die Rohwerte und Zugbänder sind archiviert. Die dargestellten '
            'Zuggrenzen stammen ab Firmware 0.21 aus eindeutigen Firmware-'
            'Ereignissen; ältere Sitzungen wurden aus dem 10-Hz-BLE-Strom '
            'segmentiert.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _StrokeTechniqueSummary extends StatelessWidget {
  const _StrokeTechniqueSummary({required this.strokes});

  final List<Stroke> strokes;

  @override
  Widget build(BuildContext context) {
    int count(StrokeTechnique technique) =>
        strokes.where((stroke) => stroke.technique == technique).length;
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        _TechniqueCount(
          label: 'LINKS',
          count: count(StrokeTechnique.leftArm),
          color: GiuliaTokens.sideLeft,
        ),
        _TechniqueCount(
          label: 'RECHTS',
          count: count(StrokeTechnique.rightArm),
          color: GiuliaTokens.sideRight,
        ),
        _TechniqueCount(
          label: 'DOPPELSTOCK',
          count: count(StrokeTechnique.doublePole),
          color: GiuliaTokens.success,
        ),
      ],
    );
  }
}

class _TechniqueCount extends StatelessWidget {
  const _TechniqueCount({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 10, height: 10, color: color),
      const SizedBox(width: 5),
      Text('$label $count', style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}

class _CounterSummary extends StatelessWidget {
  const _CounterSummary({required this.samples, required this.hasCounter});

  final List<RawSensorSample> samples;
  final bool hasCounter;

  @override
  Widget build(BuildContext context) {
    if (!hasCounter) {
      return const Text('Optikzähler: vom Firmwareformat nicht geliefert.');
    }
    final values = <SensorSide, int>{
      for (final side in SensorSide.values) side: _deltaFor(side),
    };
    return Text(
      'Reset-sichere Zählerdifferenz: LEFT ${values[SensorSide.left]} · '
      'RIGHT ${values[SensorSide.right]}. Nur Firmware 0.20+ zählt '
      'vollständig validierte Umdrehungen; ältere Archive bleiben unbestätigt.',
      style: const TextStyle(color: GiuliaTokens.warning),
    );
  }

  int _deltaFor(SensorSide side) {
    return cumulativeCounterDelta(
      samples
          .where((sample) => sample.side == side)
          .map((sample) => sample.flywheelRevolutions!),
    );
  }
}

class _OpticalStrokeChart extends StatelessWidget {
  const _OpticalStrokeChart({required this.samples, required this.strokes});

  final List<RawSensorSample> samples;
  final List<Stroke> strokes;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _OpticalStrokePainter(samples, strokes),
    child: const SizedBox.expand(),
  );
}

class _OpticalStrokePainter extends CustomPainter {
  _OpticalStrokePainter(this.samples, this.strokes);

  final List<RawSensorSample> samples;
  final List<Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = GiuliaTokens.surface2);
    final aligned = samples
        .where((sample) => sample.mappedTimeUs != null)
        .toList(growable: false);
    if (aligned.length < 2) return;
    final first = aligned.first.mappedTimeUs!;
    final last = aligned.last.mappedTimeUs!;
    final span = (last - first).clamp(1, 1 << 62);
    for (final stroke in strokes) {
      final start = ((stroke.startUs - first) / span * size.width).clamp(
        0.0,
        size.width,
      );
      final end = ((stroke.endUs - first) / span * size.width).clamp(
        0.0,
        size.width,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          start,
          0,
          (end - start).abs().clamp(1, size.width),
          size.height,
        ),
        Paint()
          ..color = switch (stroke.technique) {
            StrokeTechnique.leftArm => GiuliaTokens.sideLeft.withValues(
              alpha: .18,
            ),
            StrokeTechnique.rightArm => GiuliaTokens.sideRight.withValues(
              alpha: .18,
            ),
            StrokeTechnique.doublePole => GiuliaTokens.success.withValues(
              alpha: .18,
            ),
            StrokeTechnique.legacy => GiuliaTokens.chartGrid.withValues(
              alpha: .6,
            ),
          },
      );
    }
    for (final side in SensorSide.values) {
      final sideSamples = aligned
          .where((sample) => sample.side == side && sample.opticalRaw != null)
          .toList(growable: false);
      if (sideSamples.length < 2) continue;
      final minimum = sideSamples
          .map((sample) => sample.opticalRaw!)
          .reduce((a, b) => a < b ? a : b);
      final maximum = sideSamples
          .map((sample) => sample.opticalRaw!)
          .reduce((a, b) => a > b ? a : b);
      final range = (maximum - minimum).clamp(1, 1 << 30);
      final path = Path();
      for (var index = 0; index < sideSamples.length; index++) {
        final sample = sideSamples[index];
        final x = (sample.mappedTimeUs! - first) / span * size.width;
        final y =
            size.height - (sample.opticalRaw! - minimum) / range * size.height;
        if (index == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = side == SensorSide.left ? Colors.cyan : Colors.orange
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    final previousCounters = <SensorSide, int>{};
    for (final sample in aligned) {
      final counter = sample.strokeCounter;
      if (!sample.firmwareStrokeEventsAvailable || counter == null) continue;
      final previous = previousCounters[sample.side];
      previousCounters[sample.side] = counter;
      if (previous == null || previous == counter) continue;
      final sourceEventUs = sample.strokeEventTimeUs;
      if (sourceEventUs == null) continue;
      final eventUs =
          sample.mappedTimeUs! - (sample.deviceTimeUs - sourceEventUs);
      final x = ((eventUs - first) / span * size.width).clamp(0.0, size.width);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = sample.side == SensorSide.left
              ? GiuliaTokens.sideLeft
              : GiuliaTokens.sideRight
          ..strokeWidth = 2,
      );
    }
    final boundaryPaint = Paint()
      ..color = GiuliaTokens.textMuted
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      boundaryPaint,
    );
  }

  @override
  bool shouldRepaint(_OpticalStrokePainter oldDelegate) =>
      oldDelegate.samples != samples || oldDelegate.strokes != strokes;
}

class _AngularVelocityChart extends StatelessWidget {
  const _AngularVelocityChart({required this.samples});

  final List<RawSensorSample> samples;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _AngularVelocityPainter(samples),
    child: const SizedBox.expand(),
  );
}

class _AngularVelocityPainter extends CustomPainter {
  _AngularVelocityPainter(this.samples);

  final List<RawSensorSample> samples;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = GiuliaTokens.surface2);
    final aligned = samples
        .where(
          (sample) =>
              sample.mappedTimeUs != null &&
              sample.angularVelocityRadPerSecond != null,
        )
        .toList(growable: false);
    if (aligned.length < 2) return;
    final first = aligned.first.mappedTimeUs!;
    final last = aligned.last.mappedTimeUs!;
    final span = (last - first).clamp(1, 1 << 62);
    final maximumRpm = aligned
        .map(_rpm)
        .reduce((a, b) => a > b ? a : b)
        .clamp(1.0, double.infinity);
    for (final side in SensorSide.values) {
      final sideSamples = aligned
          .where((sample) => sample.side == side)
          .toList(growable: false);
      if (sideSamples.length < 2) continue;
      final path = Path();
      for (var index = 0; index < sideSamples.length; index++) {
        final sample = sideSamples[index];
        final x = (sample.mappedTimeUs! - first) / span * size.width;
        final y = size.height - _rpm(sample) / maximumRpm * size.height;
        if (index == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = side == SensorSide.left
              ? GiuliaTokens.sideLeft
              : GiuliaTokens.sideRight
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    final label = TextPainter(
      text: TextSpan(
        text: '${maximumRpm.round()} RPM',
        style: const TextStyle(color: GiuliaTokens.textMuted, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, const Offset(6, 4));
  }

  double _rpm(RawSensorSample sample) =>
      sample.angularVelocityRadPerSecond! * 60 / (2 * 3.141592653589793);

  @override
  bool shouldRepaint(_AngularVelocityPainter oldDelegate) =>
      oldDelegate.samples != samples;
}

/// Meter je Sekunde in Kilometer je Stunde. Null bleibt null: «nicht
/// geliefert» ist keine Geschwindigkeit.
double? _kmh(double? metresPerSecond) =>
    metresPerSecond == null ? null : metresPerSecond * 3.6;
