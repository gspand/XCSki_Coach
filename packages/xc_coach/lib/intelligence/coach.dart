/// GIULIA's grounded natural-language coach.
///
/// The wording layer never receives raw database access. It sees only the
/// structured context assembled by [GiuliaContextBuilder]. Its production
/// implementation is deterministic and local; an LLM adapter may later use
/// the same context contract, but may not alter any value in it.
library;

import '../domain/diagnostic_catalogue.dart';
import '../domain/training_plan.dart';
import 'coach_context.dart';
import 'models.dart';
import 'tools.dart';
import 'workout_selection/daily_coaching_decision.dart';

abstract interface class GiuliaCoach {
  CoachAnswer answer({
    required String question,
    required String athleteId,
    required int nowUtcUs,
  });
}

class GroundedGiuliaCoach implements GiuliaCoach {
  GroundedGiuliaCoach(this.contextBuilder, {this.todayFor});

  final DailyCoachingDecision Function(String)? todayFor;

  final GiuliaContextBuilder contextBuilder;

  @override
  CoachAnswer answer({
    required String question,
    required String athleteId,
    required int nowUtcUs,
  }) {
    final context = contextBuilder.build(
      question: question,
      athleteId: athleteId,
      nowUtcUs: nowUtcUs,
    );
    if (context.athlete == null) return _noProfile(context);
    if (todayFor != null && question.toLowerCase().contains('heute') &&
        (context.intent == IntelligenceIntent.plan || context.intent == IntelligenceIntent.readiness)) {
      final decision = todayFor!(athleteId);
      final workout = decision.prescribedWorkout;
      return CoachAnswer(
        kind: CoachAnswerKind.recommendation,
        title: 'Deine Tagesempfehlung',
        recommendation: workout == null ? decision.actionType.label : '${workout.title} · ${workout.totalDurationMinutes} min',
        reasoning: [decision.coachingReason, ...decision.safetyConstraintsApplied.map((c) => c.reason)],
        evidence: const [],
        uncertainty: decision.dataLimitations,
        confidence: IntelligenceConfidence.values.where((c)=>c.name==decision.confidence.name).firstOrNull ?? IntelligenceConfidence.insufficient,
        knowledge: context.knowledge,
        context: context.structured,
      );
    }
    return switch (context.intent) {
      IntelligenceIntent.readiness => _readiness(context),
      IntelligenceIntent.lactate => _lactate(context),
      IntelligenceIntent.threshold => _test(context),
      IntelligenceIntent.testComparison => _comparison(context),
      IntelligenceIntent.zones => _zones(context),
      IntelligenceIntent.ercolina => _ercolina(context),
      IntelligenceIntent.plan => _plan(context),
      IntelligenceIntent.history => _history(context),
      IntelligenceIntent.substitution => _substitution(context),
      IntelligenceIntent.general => _overview(context),
    };
  }

  CoachAnswer _plan(PreparedCoachContext context) {
    final coach = context.coach;
    final plan = coach?.plan;
    if (coach == null || plan == null) {
      return _limitation(
        context,
        'Für diesen Athleten ist kein Trainingsplan gespeichert.',
      );
    }
    final today = plan.todays.firstOrNull?.planned;
    final next = plan.upcoming.firstOrNull;
    if (today == null) {
      return CoachAnswer(
        kind: CoachAnswerKind.explanation,
        title: 'Für heute ist keine Einheit geplant',
        recommendation:
            context.readiness?.headline ??
            'Plane eine Einheit oder frage nach deinem aktuellen Stand.',
        reasoning: [
          if (next != null) 'Nächste geplante Einheit: ${_workoutLine(next)}.',
          ...?context.readiness?.reasons,
        ],
        evidence: _physiologyEvidence(coach),
        uncertainty: [
          if (coach.missing.isNotEmpty)
            'Nicht vorhanden: ${coach.missing.join(', ')}.',
        ],
        confidence: IntelligenceConfidence.moderate,
        knowledge: context.knowledge,
        context: context.structured,
      );
    }
    final physiology = coach.physiologyFor(today.sport);
    final todayActual = plan.todays.first;
    final done = todayActual.actual;
    return CoachAnswer(
      kind: CoachAnswerKind.recommendation,
      title: 'Heute geplant: ${today.goal}',
      recommendation: _workoutLine(today),
      reasoning: [
        if (today.isStarted)
          'Die Einheit wurde begonnen und ist noch nicht abgeschlossen'
              '${done == null ? '' : ' (bisher ${(done.durationSeconds / 60).round()} min)'}.'
        else if (today.status == PlannedWorkoutStatus.skipped)
          'Die Einheit wurde als ausgelassen markiert.'
        else if (done != null)
          'Absolviert: ${(done.durationSeconds / 60).round()} von '
              '${(today.durationSeconds / 60).round()} min'
              '${today.status == PlannedWorkoutStatus.modified ? ', als verändert erfasst' : ''}.',
        ...coach.reasonsFor(today),
        if (next != null) 'Danach: ${_workoutLine(next)}.',
      ],
      evidence: physiology == null
          ? const []
          : _physiologyEvidence(coach, physiology),
      uncertainty: [
        if (physiology == null)
          'Für ${_sportName(today.sport)} liegt keine Schwelle vor.',
        if (coach.missing.isNotEmpty)
          'Nicht vorhanden: ${coach.missing.join(', ')}.',
      ],
      confidence: physiology == null
          ? IntelligenceConfidence.low
          : IntelligenceConfidence.moderate,
      knowledge: context.knowledge,
      context: context.structured,
    );
  }

  CoachAnswer _history(PreparedCoachContext context) {
    final coach = context.coach;
    if (coach == null || !coach.available) {
      return _limitation(context, 'Die Trainingshistorie ist nicht lesbar.');
    }
    final week = coach.sessionsThisWeek();
    if (week.isEmpty) {
      return _limitation(
        context,
        'In dieser Kalenderwoche ist keine aufgezeichnete oder importierte '
        'Einheit gespeichert.',
      );
    }
    final total = week.fold(
      0,
      (sum, item) => sum + item.session.durationSeconds,
    );
    final planned = coach.plan?.week.workouts ?? const <PlannedWorkout>[];
    return CoachAnswer(
      kind: CoachAnswerKind.explanation,
      title:
          'Diese Woche: ${week.length} Einheiten, ${(total / 60).round()} min',
      recommendation: planned.isEmpty
          ? 'Für diese Woche war nichts geplant; es gibt keinen Plan-Ist-Vergleich.'
          : '${planned.where((item) => item.status == PlannedWorkoutStatus.completed || item.status == PlannedWorkoutStatus.modified).length} '
                'von ${planned.length} geplanten Einheiten sind mit einer '
                'Session belegt.',
      reasoning: [for (final item in week) _sessionLine(item, coach)],
      evidence: [
        IntelligenceEvidence(
          label: 'Trainingszeit dieser Woche',
          value: (total / 60).round(),
          unit: 'min',
          source: IntelligenceSource.measurement,
        ),
      ],
      uncertainty: const [
        'Gezählt sind nur aufgezeichnete und importierte Einheiten.',
      ],
      confidence: IntelligenceConfidence.high,
      knowledge: context.knowledge,
      context: context.structured,
    );
  }

  CoachAnswer _substitution(PreparedCoachContext context) {
    final coach = context.coach;
    if (coach == null || !coach.available) {
      return _limitation(context, 'Ohne Athletenkontext keine Aussage.');
    }
    final question = context.structured.question.toLowerCase();
    final target = _sportIn(question.split(' statt ').first);
    if (target == null) {
      return _limitation(
        context,
        'GIULIA erkennt die gewünschte Sportart nicht. Nenne Laufen, Rad, '
        'Skilanglauf oder Ercolina.',
      );
    }
    final today = coach.plan?.todays.firstOrNull?.planned;
    final physiology = coach.physiologyFor(target.storageKey);
    return CoachAnswer(
      kind: CoachAnswerKind.explanation,
      title: '${target.label} statt der geplanten Einheit',
      recommendation:
          'GIULIA ändert den Plan nicht selbst. Tauschst du, wird die '
          'Einheit beim Zuordnen als verändert erfasst.',
      reasoning: [
        if (today == null)
          'Für heute ist keine Einheit geplant.'
        else
          'Geplant: ${_workoutLine(today)}.',
        if (physiology == null)
          'Für ${target.label} liegt kein ausgewerteter Test vor. Zielbereiche '
              'in Watt oder Tempo kann GIULIA dafür nicht angeben; Schwellen '
              'einer anderen Sportart werden nicht übertragen.'
        else
          'Für ${target.label} gibt es Schwellen vom '
              '${_dateOf(physiology.performedAtUtcUs)}: LTP1 '
              '${_value(physiology.powerOrSpeedAtLtp1, physiology.loadUnit)}, '
              'LTP2 ${_value(physiology.powerOrSpeedAtLtp2, physiology.loadUnit)}. '
              'Die geplante Intensität lässt sich darauf beziehen.',
      ],
      evidence: physiology == null
          ? const []
          : _physiologyEvidence(coach, physiology),
      uncertainty: const [
        'Ob zwei Sportarten dieselbe Trainingswirkung haben, belegen die '
            'gespeicherten Daten nicht.',
      ],
      confidence: physiology == null
          ? IntelligenceConfidence.low
          : IntelligenceConfidence.moderate,
      knowledge: context.knowledge,
      context: context.structured,
    );
  }

  String _workoutLine(PlannedWorkout workout) => [
    '${workout.day.day}.${workout.day.month}.',
    _sportName(workout.sport),
    '${(workout.durationSeconds / 60).round()} min',
    if (workout.intensity != null) 'Intensität ${workout.intensity}',
  ].join(' · ');

  String _sessionLine(CoachSession item, CoachContext coach) {
    final session = item.session;
    final planned = item.plannedWorkoutId == null
        ? null
        : coach.plan?.plan.workouts
              .where((workout) => workout.id == item.plannedWorkoutId)
              .firstOrNull;
    return [
      _dateOf(session.startedAtUtcUs),
      _sportName(session.sport),
      '${(session.durationSeconds / 60).round()} min',
      if (session.averagePowerWatt != null)
        'Ø ${session.averagePowerWatt!.round()} W',
      if (session.averageSpeedKmh != null)
        'Ø ${_number(session.averageSpeedKmh!)} km/h',
      if (session.averageHeartRateBpm != null)
        'HF ${session.averageHeartRateBpm}',
      if (planned != null) 'geplant: ${planned.goal}',
    ].join(' · ');
  }

  List<IntelligenceEvidence> _physiologyEvidence(
    CoachContext coach, [
    SportPhysiology? only,
  ]) => [
    for (final entry in only == null ? coach.physiology : [only])
      for (final threshold in [entry.ltp1, entry.ltp2])
        if (threshold?.load != null)
          IntelligenceEvidence(
            label:
                '${threshold!.type.toUpperCase()} ${_sportName(entry.sportKey)}',
            value: threshold.load!,
            unit: threshold.loadUnit,
            source: IntelligenceSource.lalaEngine,
            sourceId: entry.testId,
            observedAtUtcUs: entry.performedAtUtcUs,
          ),
  ];

  DiagnosticSport? _sportIn(String text) {
    if (_hasAny(text, ['ercolina'])) return DiagnosticSport.ercolina;
    if (_hasAny(text, ['langlauf', 'ski', 'roller'])) {
      return DiagnosticSport.xcSki;
    }
    if (_hasAny(text, ['rad', 'bike', 'cycling'])) {
      return DiagnosticSport.cycling;
    }
    if (_hasAny(text, ['lauf', 'run', 'joggen'])) {
      return DiagnosticSport.running;
    }
    return null;
  }

  bool _hasAny(String text, List<String> words) => words.any(text.contains);

  String _sportName(String sport) =>
      DiagnosticSport.classify(sport: sport)?.label ?? sport;

  String _dateOf(int utcUs) {
    final day = CalendarDay.ofUtcUs(utcUs);
    return '${day.day.toString().padLeft(2, '0')}.'
        '${day.month.toString().padLeft(2, '0')}.${day.year}';
  }

  String _value(double? value, String unit) =>
      value == null ? 'unbekannt' : '${_number(value)} $unit';

  CoachAnswer _readiness(PreparedCoachContext context) {
    final value = context.readiness;
    if (value == null) return _limitation(context, 'Readiness fehlt');
    final planned = context.coach?.plan?.todays.firstOrNull?.planned;
    return CoachAnswer(
      kind: CoachAnswerKind.recommendation,
      title: value.headline,
      recommendation: _recommendationText(value.recommendation),
      reasoning: [
        if (planned != null)
          'Heute geplant: ${planned.goal} (${(planned.durationSeconds / 60).round()} min).',
        ...value.reasons,
      ],
      evidence: value.evidence,
      uncertainty: [
        if (value.missing.isNotEmpty)
          'Nicht vorhanden: ${value.missing.join(', ')}.',
        'Die Empfehlung ist Trainingssteuerung, keine medizinische Diagnose.',
      ],
      confidence: value.confidence,
      knowledge: context.knowledge,
      context: context.structured,
    );
  }

  CoachAnswer _lactate(PreparedCoachContext context) {
    final trend = context.comparison?.trends
        .where((item) => item.parameter == 'lactate_at_common_load')
        .firstOrNull;
    final test = context.latestTest;
    if (test == null) {
      return _limitation(
        context,
        'Ohne Laktatstufentest kann GIULIA keinen Laktatverlauf einordnen.',
      );
    }

    final reasoning = <String>[];
    final evidence = <IntelligenceEvidence>[];
    final uncertainty = <String>[
      'Aus einem höheren Laktatwert allein lässt sich keine Ursache beweisen.',
      'Mögliche Einflüsse sind Vorbelastung, Kohlenhydratzufuhr, '
          'Entnahmezeitpunkt, Temperatur, Tagesform und Messstreuung.',
      'GIULIA stellt keine medizinische Diagnose.',
    ];
    if (trend != null) {
      reasoning.add(trend.summary);
      evidence.addAll(trend.evidence);
      if (trend.caveat != null) uncertainty.insert(0, trend.caveat!);
    } else {
      reasoning.add(
        'Zwischen den jüngsten Tests gibt es keine identische, zulässig '
        'vergleichbare Belastungsstufe. GIULIA interpoliert hier bewusst '
        'keinen scheinbar exakten Tagesunterschied.',
      );
    }
    final latestRpe = test.curve.map((point) => point.rpe).whereType<double>();
    final latestHr = test.curve
        .map((point) => point.heartRateBpm)
        .whereType<int>();
    if (latestRpe.isNotEmpty) {
      evidence.add(
        IntelligenceEvidence(
          label: 'RPE der höchsten verwertbaren Stufe',
          value: latestRpe.last,
          source: IntelligenceSource.subjective,
          sourceId: test.id,
          observedAtUtcUs: test.startedAtUtcUs,
        ),
      );
    }
    if (latestHr.isNotEmpty) {
      evidence.add(
        IntelligenceEvidence(
          label: 'Höchste gemessene Herzfrequenz',
          value: latestHr.reduce((a, b) => a > b ? a : b),
          unit: 'bpm',
          source: IntelligenceSource.measurement,
          sourceId: test.id,
          observedAtUtcUs: test.startedAtUtcUs,
        ),
      );
    }
    return CoachAnswer(
      kind: CoachAnswerKind.explanation,
      title: 'Laktat im Kontext des Tests',
      recommendation:
          'Vergleiche den Wert nur unter demselben Protokoll und mit den '
          'Bedingungen vor dem Test.',
      reasoning: reasoning,
      evidence: evidence,
      uncertainty: uncertainty,
      confidence: trend?.confidence ?? IntelligenceConfidence.low,
      knowledge: context.knowledge,
      context: context.structured,
    );
  }

  CoachAnswer _test(PreparedCoachContext context) {
    final test = context.latestTest;
    if (test == null) {
      return _limitation(context, 'Es liegt noch kein auswertbarer Test vor.');
    }
    final lt1 = test.threshold('lt1');
    final lt2 = test.threshold('lt2');
    final evidence = <IntelligenceEvidence>[
      if (lt1?.load != null) _thresholdEvidence(test, lt1!),
      if (lt2?.load != null) _thresholdEvidence(test, lt2!),
      if (test.maximumLoad != null)
        IntelligenceEvidence(
          label: 'Höchste verwertbare Stufe',
          value: test.maximumLoad!,
          unit: test.loadUnit,
          source: IntelligenceSource.measurement,
          sourceId: test.id,
          observedAtUtcUs: test.startedAtUtcUs,
        ),
    ];
    final reasoning = <String>[
      if (lt1 != null)
        'LTP1 wurde mit ${lt1.methodId} bestimmt; der Methodenweg gehört zum Wert.',
      if (lt2 != null)
        'LTP2 wurde mit ${lt2.methodId} bestimmt; es ist keine magische '
            'Festkonzentration.',
      if (lt2?.load != null && test.maximumLoad != null)
        'Zwischen LTP2 und der höchsten Stufe liegen '
            '${_number(test.maximumLoad! - lt2!.load!)} ${test.loadUnit}.',
    ];
    return CoachAnswer(
      kind: CoachAnswerKind.explanation,
      title: 'Was am letzten Stufentest auffällt',
      recommendation: reasoning.isEmpty
          ? 'Der Test enthält noch keine belastbare Schwelle.'
          : 'Nutze die ausgewiesenen Methoden und Zonen dieses Calculation Runs.',
      reasoning: reasoning,
      evidence: evidence,
      uncertainty: [
        ...test.qualityNotes,
        if (test.structure == null)
          'Die Stufenstruktur ist nicht eindeutig; ein Längsschnittvergleich '
              'wird deshalb blockiert.',
        'Die Interpretation beschreibt Leistungsdiagnostik, keine Erkrankung.',
      ],
      confidence: evidence.length >= 2
          ? IntelligenceConfidence.high
          : IntelligenceConfidence.low,
      knowledge: context.knowledge,
      context: context.structured,
    );
  }

  CoachAnswer _comparison(PreparedCoachContext context) {
    final comparison = context.comparison;
    if (comparison == null) {
      return _limitation(
        context,
        'Für einen Vergleich braucht GIULIA mindestens zwei Tests.',
      );
    }
    if (!comparison.comparable) {
      return CoachAnswer(
        kind: CoachAnswerKind.limitation,
        title: 'Diese Tests werden nicht numerisch verglichen',
        recommendation: 'Wiederhole denselben Sport- und Stufenaufbau.',
        reasoning: comparison.caveats,
        evidence: const [],
        uncertainty: const [
          'Eine Zahl wäre hier präzise formatiert, aber fachlich irreführend.',
        ],
        confidence: IntelligenceConfidence.insufficient,
        knowledge: context.knowledge,
        context: context.structured,
      );
    }
    final evidence = <IntelligenceEvidence>[
      for (final trend in comparison.trends) ...trend.evidence,
    ];
    return CoachAnswer(
      kind: CoachAnswerKind.comparison,
      title: 'Entwicklung zwischen den jüngsten Tests',
      recommendation: _comparisonRecommendation(comparison.trends),
      reasoning: [for (final trend in comparison.trends) trend.summary],
      evidence: _uniqueEvidence(evidence),
      uncertainty: [
        ...comparison.caveats,
        'Die Daten zeigen Zusammenhänge und Veränderungen, aber keine '
            'Ursache für diese Veränderungen.',
      ],
      confidence: comparison.confidence,
      knowledge: context.knowledge,
      context: context.structured,
    );
  }

  CoachAnswer _zones(PreparedCoachContext context) {
    final zones = context.zones;
    if (zones.isEmpty) {
      return _limitation(
        context,
        'Für den jüngsten Test sind keine Trainingszonen gespeichert.',
      );
    }
    final model = zones.first.modelName;
    final provisional = zones.where((zone) => zone.provisional).length;
    final evidence = <IntelligenceEvidence>[];
    for (final zone in zones.take(6)) {
      if (zone.lowerLoad != null) {
        evidence.add(
          IntelligenceEvidence(
            label: '${zone.code} Untergrenze',
            value: zone.lowerLoad!,
            unit: zone.loadUnit,
            source: IntelligenceSource.lalaEngine,
            caveat: '${zone.modelId} · ${zone.modelVersion} · ${zone.quality}',
          ),
        );
      }
      if (zone.upperLoad != null) {
        evidence.add(
          IntelligenceEvidence(
            label: '${zone.code} Obergrenze',
            value: zone.upperLoad!,
            unit: zone.loadUnit,
            source: IntelligenceSource.lalaEngine,
            caveat: '${zone.modelId} · ${zone.modelVersion} · ${zone.quality}',
          ),
        );
      }
    }
    return CoachAnswer(
      kind: CoachAnswerKind.explanation,
      title: 'Warum GIULIA diese Trainingszonen verwendet',
      recommendation:
          'Verwende die Grenzen zusammen mit dem Modellnamen, nicht als '
          'universelle Prozentwerte.',
      reasoning: [
        'Die angezeigten Bereiche stammen aus dem versionierten Zonenmodell '
            '$model und aus dem gespeicherten LaLa-Calculation-Run.',
        'Sie wurden nicht vom Coach-Text neu berechnet.',
      ],
      evidence: evidence,
      uncertainty: [
        if (provisional > 0)
          '$provisional Grenzen sind vom Engine-Ergebnis als vorläufig markiert.',
        'Andere wissenschaftlich begründete Zonenmodelle können mit denselben '
            'Schwellen andere Grenzziehungen verwenden.',
      ],
      confidence: provisional == 0
          ? IntelligenceConfidence.high
          : IntelligenceConfidence.moderate,
      knowledge: context.knowledge,
      context: context.structured,
    );
  }

  CoachAnswer _ercolina(PreparedCoachContext context) {
    final value = context.ercolina;
    if (value?.session == null) {
      return _limitation(
        context,
        'Für eine Technikanalyse braucht GIULIA eine Sitzung mit Zugdaten.',
      );
    }
    return CoachAnswer(
      kind: CoachAnswerKind.explanation,
      title: 'Wie die Leistung erzeugt wurde',
      recommendation:
          value!.findings.any(
            (finding) =>
                finding.parameter == 'symmetry' &&
                finding.summary.contains('mehr Leistung'),
          )
          ? 'Beobachte die Seitigkeit in weiteren vergleichbaren Einheiten, '
                'bevor du Technik daraus ableitest.'
          : 'Leistung, Frequenz und Arbeit je Zug gemeinsam beurteilen.',
      reasoning: [for (final finding in value.findings) finding.summary],
      evidence: _uniqueEvidence([
        for (final finding in value.findings) ...finding.evidence,
      ]),
      uncertainty: [
        if (value.missing.isNotEmpty)
          'Nicht auswertbar: ${value.missing.join(', ')}.',
        'Eine Links-rechts-Abweichung ist eine Messbeobachtung, keine '
            'Verletzungsdiagnose.',
      ],
      confidence: value.findings.isEmpty
          ? IntelligenceConfidence.insufficient
          : IntelligenceConfidence.moderate,
      knowledge: context.knowledge,
      context: context.structured,
    );
  }

  CoachAnswer _overview(PreparedCoachContext context) {
    final trend = context.trends.firstOrNull;
    final readiness = context.readiness;
    final athleteState = context.athleteState;
    final year = athleteState?.window(365);
    return CoachAnswer(
      kind: CoachAnswerKind.explanation,
      title: 'GIULIA Intelligence für ${context.athlete!.name}',
      recommendation:
          readiness?.headline ??
          'Stelle eine konkrete Frage zu Training, Test, Laktat oder Technik.',
      reasoning: [
        if (athleteState != null && year != null)
          'Der persistente Athlete State umfasst ${year.activityCount} '
              'Aktivitäten aus bis zu 365 Tagen; '
              '${athleteState.dataQuality.historyDays} Tage Historie sind '
              'tatsächlich belegt.',
        if (athleteState != null)
          for (final dimension in athleteState.dimensions.where(
            (item) => const {
              'aerobic_base',
              'threshold_performance',
              'training_tolerance',
            }.contains(item.key),
          ))
            '${dimension.label}: ${dimension.assessment}.',
        if (trend != null) trend.summary,
        if (context.latestTest == null)
          'Noch kein auswertbarer Stufentest vorhanden.',
        if (readiness != null) ...readiness.reasons,
      ],
      evidence: [
        if (trend != null) ...trend.evidence,
        if (readiness != null) ...readiness.evidence,
      ],
      uncertainty: [
        if (athleteState == null)
          'Noch kein persistenter Athlete State verfügbar.',
        if (athleteState != null && athleteState.dataQuality.missing.isNotEmpty)
          'Athlete-State-Lücken: '
              '${athleteState.dataQuality.missing.join(', ')}.',
        if (readiness != null && readiness.missing.isNotEmpty)
          'Fehlende Daten: ${readiness.missing.join(', ')}.',
      ],
      confidence:
          readiness?.confidence ??
          athleteState?.dataQuality.confidence ??
          IntelligenceConfidence.low,
      knowledge: context.knowledge,
      context: context.structured,
    );
  }

  CoachAnswer _noProfile(PreparedCoachContext context) => CoachAnswer(
    kind: CoachAnswerKind.limitation,
    title: 'Kein freigegebener Athletenkontext',
    recommendation: 'Wähle ein sichtbares Athletenprofil.',
    reasoning: const [
      'GIULIA beantwortet personenbezogene Fragen nicht ohne Profil und '
          'Berechtigung.',
    ],
    evidence: const [],
    uncertainty: const [],
    confidence: IntelligenceConfidence.insufficient,
    knowledge: context.knowledge,
    context: context.structured,
  );

  CoachAnswer _limitation(PreparedCoachContext context, String reason) =>
      CoachAnswer(
        kind: CoachAnswerKind.limitation,
        title: 'Das lässt sich noch nicht zuverlässig ableiten',
        recommendation: reason,
        reasoning: const [],
        evidence: const [],
        uncertainty: const [
          'GIULIA ergänzt fehlende Messwerte nicht durch Schätzungen.',
        ],
        confidence: IntelligenceConfidence.insufficient,
        knowledge: context.knowledge,
        context: context.structured,
      );

  IntelligenceEvidence _thresholdEvidence(
    IntelligenceTest test,
    IntelligenceThreshold threshold,
  ) => IntelligenceEvidence(
    label: threshold.type.toUpperCase(),
    value: threshold.load!,
    unit: threshold.loadUnit,
    source: IntelligenceSource.lalaEngine,
    sourceId: test.id,
    observedAtUtcUs: test.startedAtUtcUs,
    caveat: '${threshold.methodId} · ${threshold.engineVersion}',
  );

  String _recommendationText(ReadinessRecommendation recommendation) =>
      switch (recommendation) {
        ReadinessRecommendation.insufficient =>
          'Keine konkrete Intensität empfehlen, bis mehr Daten vorliegen.',
        ReadinessRecommendation.recovery =>
          'Pause oder eine sehr kurze, regenerative Bewegungseinheit.',
        ReadinessRecommendation.easy =>
          'Lockere Einheit klar unter LTP1; Umfang nach Gefühl begrenzen.',
        ReadinessRecommendation.endurance =>
          'Gleichmässige Grundlageneinheit unter LTP1.',
        ReadinessRecommendation.quality =>
          'Eine geplante Intervall- oder Schwelleneinheit ist vertretbar; '
              'bei ungewöhnlichem Gefühl abbrechen oder reduzieren.',
        ReadinessRecommendation.technique =>
          'Technikfokus ohne harte Leistungsvorgabe.',
      };

  String _comparisonRecommendation(List<IntelligenceTrend> trends) {
    final improved = trends
        .where(
          (trend) =>
              (trend.parameter == 'lt1' || trend.parameter == 'lt2') &&
              trend.direction == TrendDirection.improving,
        )
        .length;
    final declined = trends
        .where(
          (trend) =>
              (trend.parameter == 'lt1' || trend.parameter == 'lt2') &&
              trend.direction == TrendDirection.declining,
        )
        .length;
    if (improved > 0 && declined == 0) {
      return 'Die Schwellenentwicklung ist positiv; Trainingswirkung und '
          'Belastungsverträglichkeit weiter gemeinsam beobachten.';
    }
    if (declined > 0 && improved == 0) {
      return 'Die Veränderung beobachten und mit Belastung, Erholung und '
          'Testbedingungen abgleichen; ein einzelner Vergleich beweist keine '
          'Verschlechterungsursache.';
    }
    return 'Die Entwicklung ist gemischt oder stabil; aus diesem Vergleich '
        'allein folgt keine Trainingsumstellung.';
  }

  List<IntelligenceEvidence> _uniqueEvidence(
    List<IntelligenceEvidence> values,
  ) {
    final seen = <String>{};
    return [
      for (final value in values)
        if (seen.add(
          '${value.label}|${value.value}|${value.unit}|${value.sourceId}',
        ))
          value,
    ];
  }
}

String _number(double value) {
  final rounded = value.roundToDouble();
  return (value - rounded).abs() < .05
      ? rounded.toInt().toString()
      : value.toStringAsFixed(1).replaceAll('.', ',');
}
