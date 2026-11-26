import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:xc_coach/domain/normalized_session.dart';
import 'package:xc_coach/domain/training_plan.dart';
import 'package:xc_coach/domain/training_sessions.dart';
import 'coach_store.dart';

class TrainingHistory extends StatefulWidget {
  const TrainingHistory({
    super.key,
    required this.store,
    required this.athlete,
    required this.week,
    required this.onWeek,
  });
  final CoachStore store;
  final String athlete;
  final CalendarDay week;
  final ValueChanged<CalendarDay> onWeek;
  @override
  State<TrainingHistory> createState() => _TrainingHistoryState();
}

class _TrainingHistoryState extends State<TrainingHistory> {
  bool distance = false;
  int selected = 7;
  late List<List<NormalizedSession>> weeks = _read();
  @override
  void didUpdateWidget(TrainingHistory old) {
    super.didUpdateWidget(old);
    if (old.week != widget.week ||
        old.athlete != widget.athlete ||
        old.store != widget.store) {
      weeks = _read();
      selected = 7;
    }
  }

  List<List<NormalizedSession>> _read() {
    final start = widget.week.addDays(-49), end = widget.week.addDays(7);
    int local(CalendarDay d) =>
        DateTime(d.year, d.month, d.day).microsecondsSinceEpoch;
    final rows = trainingSessions(
      widget.store.storage.loadNormalizedSessions(
        widget.athlete,
        fromUtcUs: local(start),
        toUtcUs: local(end) - 1,
        limit: null,
      ),
    );
    final result = List.generate(8, (_) => <NormalizedSession>[]);
    for (final row in rows) {
      result[start.daysUntil(CalendarDay.ofUtcUs(row.startedAtUtcUs)) ~/ 7].add(
        row,
      );
    }
    return result;
  }

  String fmt(double n) => n.toStringAsFixed(1).replaceFirst('.', ',');
  @override
  Widget build(BuildContext context) {
    final values = weeks
        .map(
          (week) => distance
              ? week
                        .map((s) => s.distanceMetres)
                        .whereType<double>()
                        .fold(0.0, (a, b) => a + b) /
                    1000
              : week.fold(0.0, (a, s) => a + s.movingTimeSeconds) / 3600,
        )
        .toList();
    final measured = [
      for (final wk in weeks)
        distance ? wk.any((s) => s.distanceMetres != null) : wk.isNotEmpty,
    ];
    final highest = values.reduce(math.max);
    final range = widget.week.addDays((selected - 7) * 7);
    final sessions = weeks[selected];
    final unit = distance ? 'km' : 'h';
    final total = values.reduce((a, b) => a + b);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xffeff4ef),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffd4dfd5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Trainingsumfang',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.7,
                ),
              ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: false, label: Text('Zeit')),
                  ButtonSegment(value: true, label: Text('Distanz')),
                ],
                selected: {distance},
                onSelectionChanged: (s) => setState(() => distance = s.single),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            measured.contains(true) ? '${fmt(total)} $unit' : '—',
            style: const TextStyle(
              fontSize: 35,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.5,
              height: 1.08,
              color: Color(0xff123b3c),
            ),
          ),
          Text(
            '${weeks.fold(0, (int sum, week) => sum + week.length)} Einheiten in acht Wochen',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Stack(
            children: [
              const Positioned.fill(
                bottom: 23,
                child: CustomPaint(painter: _Grid()),
              ),
              Row(
                children: [
                  for (var i = 0; i < 8; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == selected,
                        label:
                            'Woche ab ${widget.week.addDays(7 * (i - 7)).key}, ${measured[i] ? '${fmt(values[i])} $unit' : 'keine Messung'}',
                        child: InkWell(
                          onTap: () => setState(() => selected = i),
                          borderRadius: BorderRadius.circular(6),
                          child: Column(
                            children: [
                              SizedBox(
                                height: 66,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    width: 19,
                                    height: measured[i] && highest > 0
                                        ? math.max(2, values[i] / highest * 63)
                                        : 2,
                                    decoration: BoxDecoration(
                                      color: !measured[i]
                                          ? const Color(0xffa7b9af)
                                          : i == selected
                                          ? const Color(0xff155d53)
                                          : const Color(0xff73a492),
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${widget.week.addDays(7 * (i - 7)).day}.${widget.week.addDays(7 * (i - 7)).month}.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: i == selected
                                        ? FontWeight.w800
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const Divider(height: 22),
          Text(
            'Woche ab ${range.day}.${range.month}.',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          Text(
            sessions.isEmpty
                ? 'Keine Einheit erfasst.'
                : '${sessions.length} ${sessions.length == 1 ? 'Einheit' : 'Einheiten'} · ${measured[selected] ? '${fmt(values[selected])} $unit' : 'Distanz fehlt'}',
            style: const TextStyle(fontSize: 13),
          ),
          if (selected != 7)
            TextButton.icon(
              onPressed: () => widget.onWeek(range),
              icon: const Icon(Icons.arrow_forward, size: 15),
              label: const Text('Trainingswoche ansehen'),
            )
          else if (sessions.isEmpty && weeks.any((week) => week.isNotEmpty))
            TextButton.icon(
              onPressed: () => widget.onWeek(
                widget.week.addDays(
                  (weeks.lastIndexWhere((week) => week.isNotEmpty) - 7) * 7,
                ),
              ),
              icon: const Icon(Icons.history, size: 15),
              label: const Text('Letzte aktive Woche'),
            ),
        ],
      ),
    );
  }
}

class _Grid extends CustomPainter {
  const _Grid();
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = const Color(0xffd1ddd5);
    for (final f in [0.05, .5, 1.0]) {
      c.drawLine(Offset(0, s.height * f), Offset(s.width, s.height * f), p);
    }
  }

  @override
  bool shouldRepaint(_Grid old) => false;
}
