import 'package:flutter/material.dart';
import 'package:xc_coach/ui/today/today_view_model.dart';

/// Both entry points show the same decision and the same dose, including rest.
class WorkoutHeader extends StatelessWidget {
  const WorkoutHeader({
    super.key,
    required this.workout,
    required this.label,
    required this.onPressed,
    this.planNote,
  });
  final TodayViewModel workout;
  final String label;
  final String? planNote;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final vm = workout;
    final suffix = ' (${vm.durationMinutes} min)';
    final title = vm.heroTitle.endsWith(suffix)
        ? vm.heroTitle.substring(0, vm.heroTitle.length - suffix.length)
        : vm.heroTitle;
    final compact = MediaQuery.sizeOf(context).width < 670;
    return Container(
      constraints: const BoxConstraints(minHeight: 218),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 20 : 28,
        vertical: compact ? 20 : 25,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xff112a29),
        image: const DecorationImage(
          image: AssetImage('assets/nordic-dawn.jpg'),
          fit: BoxFit.cover,
          alignment: Alignment(.69, 0),
        ),
      ),

      clipBehavior: Clip.antiAlias,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -36,
            right: -36,
            top: -36,
            bottom: -36,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xf10b2429),
                    Color(0xa00a2026),
                    Color(0x1911282e),
                  ],
                  stops: [0, .55, 1],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Tooltip(
                message: vm.decisionVersion == null
                    ? 'Tagesempfehlung'
                    : '${vm.decisionId} · ${vm.decisionVersion!.substring(0, 10)}',
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.nordic_walking,
                      color: Color(0xffd7f07a),
                      size: 18,
                    ),
                    SizedBox(width: 7),
                    Text(
                      'COACH · HEUTE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                        color: Color(0xffd7f07a),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 500),
                child: Text(
                  title,
                  key: const ValueKey('daily-workout-title'),
                  style: TextStyle(
                    fontSize: MediaQuery.sizeOf(context).width < 380 ? 24 : (compact ? 29 : 37),
                    height: 1.03,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.3,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (vm.durationMinutes > 0)
                    _detail(Icons.timer_outlined, '${vm.durationMinutes} min'),
                  _detail(Icons.terrain_outlined, vm.modalityLabel),
                  if (!vm.isRestDay)
                    _detail(Icons.tune, vm.qualitativeIntensity.label),
                ],
              ),
              if (planNote != null) ...[
                const SizedBox(height: 8),
                Text(
                  planNote!,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
              const SizedBox(height: 17),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xffd9ef86),
                  foregroundColor: const Color(0xff122829),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                onPressed: onPressed,
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: Text(label),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detail(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: Colors.white70),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}
