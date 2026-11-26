import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'garmin_personal.dart';

enum HealthMeasure {
  battery(
    'Body Battery',
    Icons.battery_charging_full_outlined,
    Color(0xff357968),
    '',
    {
      'summary': r'$.bodyBatteryMostRecentValue',
      'dailyV2': r'$.bodyBattery.latestValue',
    },
    max: 100,
  ),
  sleep('Schlaf', Icons.bedtime_outlined, Color(0xff5b619b), '', {
    'sleep': r'$.sleepTimeSeconds',
  }, positive: true),
  hrv('HRV nachts', Icons.monitor_heart_outlined, Color(0xff206c7a), ' ms', {
    'hrv': r'$.hrvSummary.lastNightAvg',
  }, positive: true),
  pulse('Ruhepuls', Icons.favorite_border, Color(0xffa35c48), ' bpm', {
    'summary': r'$.restingHeartRate',
    'dailyV2': r'$.heartRate.restingValue',
  }, positive: true),
  stress('Stress', Icons.spa_outlined, Color(0xff926e2d), '', {
    'summary': r'$.averageStressLevel',
    'dailyV2': r'$.stress.avgLevel',
  }, max: 100),
  oxygen(
    'SpO₂',
    Icons.air_outlined,
    Color(0xff397399),
    ' %',
    {'summary': r'$.averageSpo2', 'dailyV2': r'$.pulseOx.avgValue'},
    max: 100,
    positive: true,
  ),
  cycle('Zyklustag', Icons.calendar_today_outlined, Color(0xff94546f), '', {
    'cycle': r'$.dayInCycle',
  }, positive: true);

  const HealthMeasure(
    this.label,
    this.icon,
    this.color,
    this.unit,
    this.paths, {
    this.positive = false,
    this.max,
  });
  final String label, unit;
  final IconData icon;
  final Color color;
  final Map<String, String> paths;
  final bool positive;
  final int? max;
  String format(double? value) {
    if (value == null) return '—';
    if (this == sleep) {
      final minutes = (value / 60).round();
      return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')} min';
    }
    return '${value.round()}$unit';
  }

  List<double?> series(GarminArchive archive, CalendarDay end) {
    final values = List<double?>.filled(7, null);
    if (this == cycle && !archive.cycleEnabled) return values;
    for (final source in {
      (this == cycle ? 'cycleConnectMetrics' : 'connectMetrics'): '\$.$name',
      ...paths,
    }.entries) {
      final keys = List.generate(
        7,
        (i) => '${archive.prefix}day.${end.addDays(i - 6).key}.${source.key}',
      );
      final rows = archive.store.db.raw.select(
        'SELECT key,json_extract(value,?) AS measurement FROM app_state WHERE key IN (?,?,?,?,?,?,?)',
        [source.value, ...keys],
      );
      for (final row in rows) {
        final number = row['measurement'];
        if (number is! num ||
            !number.isFinite ||
            number < 0 ||
            (positive && number == 0) ||
            (max != null && number > max!))
          continue;
        values[keys.indexOf(row['key'] as String)] ??= number.toDouble();
      }
    }
    return values;
  }
}

class HealthTrendTile extends StatelessWidget {
  const HealthTrendTile({
    super.key,
    required this.metric,
    required this.values,
    required this.end,
  });
  final HealthMeasure metric;
  final List<double?> values;
  final CalendarDay end;
  @override
  Widget build(BuildContext context) {
    final count = values.whereType<double>().length;
    return Material(
      color: Color.lerp(metric.color, Colors.white, .95),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Color.lerp(metric.color, Colors.white, .77)!),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (c) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              children: [
                Text(metric.label, style: Theme.of(c).textTheme.titleLarge),
                for (var i = 6; i >= 0; i--)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(end.addDays(i - 6).key),
                    trailing: Text(metric.format(values[i])),
                  ),
              ],
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(metric.icon, color: metric.color, size: 18),
              const SizedBox(height: 8),
              Text(
                metric.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xff445a56),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                metric.format(values.last),
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.7,
                ),
              ),
              const SizedBox(height: 8),
              Semantics(
                label: '$count von sieben Messtagen vorhanden',
                child: SizedBox(
                  height: 25,
                  width: double.infinity,
                  child: CustomPaint(painter: _Sparkline(values, metric.color)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sparkline extends CustomPainter {
  const _Sparkline(this.values, this.color);
  final List<double?> values;
  final Color color;
  @override
  void paint(Canvas c, Size size) {
    final measured = values.whereType<double>();
    final grid = Paint()
      ..color = color.withValues(alpha: .15)
      ..strokeWidth = 1;
    c.drawLine(
      Offset(0, size.height - 2),
      Offset(size.width, size.height - 2),
      grid,
    );
    if (measured.isEmpty) return;
    final lo = measured.reduce(math.min), hi = measured.reduce(math.max);
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    Offset? previous;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) {
        previous = null;
        continue;
      }
      final dot = Offset(
        2 + (size.width - 4) * i / 6,
        hi == lo
            ? size.height / 2
            : 2 + (size.height - 4) * (hi - v) / (hi - lo),
      );
      if (previous != null) c.drawLine(previous, dot, line);
      c.drawCircle(dot, i == 6 ? 2.7 : 1.8, line);
      previous = dot;
    }
  }

  @override
  bool shouldRepaint(_Sparkline old) =>
      values != old.values || color != old.color;
}
