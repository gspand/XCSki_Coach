/// The integrated GIULIA Intelligence surface.
///
/// This is intentionally not a detached generic chat page. It is a compact
/// entry beside the athlete's real data and opens a structured answer with
/// recommendation, reasoning, evidence and uncertainty kept visibly apart.
library;

import '../../branding.dart';

import 'package:flutter/material.dart';

import '../../database/coach_storage_repository.dart';
import '../../database/platform_repository.dart';
import '../../intelligence/coach.dart';
import '../../intelligence/models.dart';
import '../academy/academy_link.dart';
import '../design_system.dart';

const List<String> defaultGiuliaQuestions = [
  'Analysiere meinen aktuellen Trainingsstand.',
  'Was soll ich heute trainieren?',
  'Hat sich meine aerobe Basis verbessert?',
  'Vergleiche meine letzten Tests.',
  'Warum empfiehlt GIULIA diese Trainingszone?',
  'Was fällt dir an meiner letzten Ercolina-Einheit auf?',
];

class GiuliaCoachCard extends StatelessWidget {
  const GiuliaCoachCard({
    super.key,
    required this.coach,
    required this.athletes,
    this.initialAthleteId,
    this.prompt = 'GIULIA, wie sieht mein Training heute aus?',
    this.questions = defaultGiuliaQuestions,
    this.storage,
  });

  final GiuliaCoach coach;
  final List<AthleteSummary> athletes;
  final String? initialAthleteId;
  final String prompt;
  final List<String> questions;
  final SqliteCoachStorageRepository? storage;

  @override
  Widget build(BuildContext context) {
    if (athletes.isEmpty) return const SizedBox.shrink();
    return GiuliaPanel(
      key: const Key('giulia-intelligence-card'),
      onTap: () => showGiuliaCoach(
        context: context,
        coach: coach,
        athletes: athletes,
        initialAthleteId: initialAthleteId,
        questions: questions,
        storage: storage,
      ),
      tone: GiuliaTokens.surface2,
      child: Row(
        children: [
          const Icon(
            Icons.auto_awesome_outlined,
            color: GiuliaTokens.accent,
            size: GiuliaTokens.iconM,
          ),
          const SizedBox(width: GiuliaTokens.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GIULIA INTELLIGENCE',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: GiuliaTokens.accent),
                ),
                const SizedBox(height: GiuliaTokens.spacingXs),
                Text(prompt, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: GiuliaTokens.textMuted),
        ],
      ),
    );
  }
}

Future<void> showGiuliaCoach({
  required BuildContext context,
  required GiuliaCoach coach,
  required List<AthleteSummary> athletes,
  String? initialAthleteId,
  List<String> questions = defaultGiuliaQuestions,
  String? initialQuestion,
  SqliteCoachStorageRepository? storage,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: GiuliaTokens.surface0,
  builder: (_) => FractionallySizedBox(
    heightFactor: .92,
    child: GiuliaCoachScreen(
      coach: coach,
      athletes: athletes,
      initialAthleteId: initialAthleteId,
      questions: questions,
      initialQuestion: initialQuestion,
      showCloseButton: true,
      storage: storage,
    ),
  ),
);

/// Full Intelligence screen used both as the main athlete destination and in
/// a contextual bottom sheet from diagnostics or coaching.
class GiuliaCoachScreen extends StatefulWidget {
  const GiuliaCoachScreen({
    super.key,
    required this.coach,
    required this.athletes,
    required this.questions,
    this.initialAthleteId,
    this.initialQuestion,
    this.showCloseButton = false,
    this.storage,
  });

  final GiuliaCoach coach;
  final List<AthleteSummary> athletes;
  final String? initialAthleteId;
  final List<String> questions;
  final String? initialQuestion;
  final bool showCloseButton;
  final SqliteCoachStorageRepository? storage;

  @override
  State<GiuliaCoachScreen> createState() => _GiuliaCoachScreenState();
}

class _GiuliaCoachScreenState extends State<GiuliaCoachScreen> {
  String? _athleteId;
  late final TextEditingController _question = TextEditingController(
    text: widget.initialQuestion,
  );
  final ScrollController _scroll = ScrollController();
  final GlobalKey _latestMessage = GlobalKey();
  List<CoachChatMessage> _messages = const [];
  final Map<String, CoachAnswer> _liveAnswers = {};

  @override
  void initState() {
    super.initState();
    _athleteId = _resolvedAthleteId();
    _loadHistory();
    if (widget.initialQuestion?.trim().isNotEmpty ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
    } else if (_messages.isNotEmpty) {
      _scrollToLatest();
    }
  }

  @override
  void dispose() {
    _question.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String? _resolvedAthleteId() {
    for (final athlete in widget.athletes) {
      if (athlete.id == widget.initialAthleteId) return athlete.id;
    }
    return widget.athletes.firstOrNull?.id;
  }

  void _loadHistory() {
    final athleteId = _athleteId;
    _messages = athleteId == null
        ? const []
        : widget.storage?.loadChatMessages(athleteId) ?? const [];
  }

  void _selectAthlete(String athleteId) {
    setState(() {
      _athleteId = athleteId;
      _liveAnswers.clear();
      _loadHistory();
    });
    if (_messages.isNotEmpty) _scrollToLatest();
  }

  void _ask([String? question]) {
    final value = (question ?? _question.text).trim();
    final athleteId = _athleteId;
    if (value.isEmpty || athleteId == null) return;
    final nowUs = DateTime.now().toUtc().microsecondsSinceEpoch;
    final answer = widget.coach.answer(
      question: value,
      athleteId: athleteId,
      nowUtcUs: nowUs,
    );
    final athleteMessageId = 'msg-$nowUs';
    final coachMessageId = 'msg-${nowUs + 1}';
    final storage = widget.storage;

    if (storage != null) {
      storage.saveChatMessage(
        athleteId: athleteId,
        sender: 'athlete',
        text: value,
        createdAtUtcUs: nowUs,
      );
      storage.saveChatMessage(
        athleteId: athleteId,
        sender: 'coach',
        text: answer.recommendation,
        structured: answer.toJson(),
        createdAtUtcUs: nowUs + 1,
      );
    }

    setState(() {
      _question.clear();
      _liveAnswers[coachMessageId] = answer;
      _messages = storage == null
          ? [
              ..._messages,
              (
                id: athleteMessageId,
                sender: 'athlete',
                text: value,
                structured: null,
                createdAtUtcUs: nowUs,
              ),
              (
                id: coachMessageId,
                sender: 'coach',
                text: answer.recommendation,
                structured: answer.toJson(),
                createdAtUtcUs: nowUs + 1,
              ),
            ]
          : storage.loadChatMessages(athleteId);
    });
    _scrollToLatest();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _latestMessage.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: .06,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final density = GiuliaDensity.of(context);
    final athleteId = _athleteId;
    return Scaffold(
      backgroundColor: GiuliaTokens.surface0,
      appBar: AppBar(
        title: const Text(giuliaWordmark),
        automaticallyImplyLeading: false,
        actions: widget.showCloseButton
            ? [
                IconButton(
                  tooltip: 'Schliessen',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ]
            : null,
      ),
      body: athleteId == null
          ? const Padding(
              padding: EdgeInsets.all(GiuliaTokens.spacingL),
              child: GiuliaEmptyState(
                icon: Icons.person_add_alt_1_outlined,
                title: 'Noch kein Athletenprofil',
                description:
                    'GIULIA braucht ein Profil, damit jede Antwort eindeutig '
                    'zugeordnet bleibt.',
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: ListView(
                        controller: _scroll,
                        padding: density.pageInsets,
                        children: [
                          if (widget.athletes.length > 1) ...[
                            DropdownButtonFormField<String>(
                              key: const Key('giulia-athlete-selector'),
                              initialValue: athleteId,
                              decoration: const InputDecoration(
                                labelText: 'GIULIA spricht mit',
                              ),
                              items: [
                                for (final athlete in widget.athletes)
                                  DropdownMenuItem(
                                    value: athlete.id,
                                    child: Text(athlete.name),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null) _selectAthlete(value);
                              },
                            ),
                            const SizedBox(height: GiuliaTokens.spacingM),
                          ],
                          GiuliaPanel(
                            key: const Key('giulia-athlete-state-entry'),
                            tone: GiuliaTokens.surface2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Was möchtest du wissen?',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: GiuliaTokens.spacingXs),
                                Text(
                                  'GIULIA antwortet aus deinem aktuellen '
                                  'Training, deinen Tests und der vorhandenen '
                                  'Datenqualität.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: GiuliaTokens.spacingM),
                                Wrap(
                                  spacing: GiuliaTokens.spacingS,
                                  runSpacing: GiuliaTokens.spacingS,
                                  children: [
                                    FilledButton.icon(
                                      key: const Key(
                                        'giulia-analyze-athlete-state',
                                      ),
                                      onPressed: () => _ask(
                                        'Analysiere meinen aktuellen Trainingsstand.',
                                      ),
                                      icon: const Icon(
                                        Icons.analytics_outlined,
                                      ),
                                      label: const Text(
                                        'Meinen Stand analysieren',
                                      ),
                                    ),
                                    for (final question in widget.questions)
                                      ActionChip(
                                        label: Text(question),
                                        onPressed: () => _ask(question),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          for (final (index, message) in _messages.indexed) ...[
                            SizedBox(height: density.cardGap),
                            Container(
                              key: index == _messages.length - 1
                                  ? _latestMessage
                                  : null,
                              child: _ConversationMessage(
                                message: message,
                                liveAnswer: _liveAnswers[message.id],
                                isLatest: index == _messages.length - 1,
                              ),
                            ),
                          ],
                          const SizedBox(height: GiuliaTokens.spacingM),
                        ],
                      ),
                    ),
                  ),
                ),
                Material(
                  color: GiuliaTokens.surface1,
                  child: SafeArea(
                    top: false,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                          child: TextField(
                            key: const Key('giulia-question'),
                            controller: _question,
                            textInputAction: TextInputAction.send,
                            onSubmitted: _ask,
                            decoration: InputDecoration(
                              hintText: 'Frag GIULIA ...',
                              suffixIcon: IconButton(
                                key: const Key('giulia-send'),
                                tooltip: 'Senden',
                                onPressed: _ask,
                                icon: const Icon(Icons.arrow_upward),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ConversationMessage extends StatelessWidget {
  const _ConversationMessage({
    required this.message,
    required this.isLatest,
    this.liveAnswer,
  });

  final CoachChatMessage message;
  final CoachAnswer? liveAnswer;
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    if (message.sender == 'athlete') {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: GiuliaTokens.accentSoft,
              borderRadius: BorderRadius.circular(GiuliaTokens.radiusM),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: GiuliaTokens.spacingM,
                vertical: GiuliaTokens.spacingS,
              ),
              child: Text(message.text),
            ),
          ),
        ),
      );
    }

    final answerKey = isLatest
        ? const Key('giulia-answer')
        : ValueKey('giulia-answer-${message.id}');
    final answer = liveAnswer;
    if (answer != null) return _Answer(key: answerKey, answer: answer);
    return _StoredAnswer(key: answerKey, message: message);
  }
}

class _Answer extends StatelessWidget {
  const _Answer({super.key, required this.answer});
  final CoachAnswer answer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(answer.title, style: text.headlineSmall)),
            _Confidence(value: answer.confidence),
          ],
        ),
        const SizedBox(height: GiuliaTokens.spacingM),
        _Section(
          title: 'Empfehlung',
          icon: Icons.route_outlined,
          children: [answer.recommendation],
          tone: GiuliaTokens.surface2,
        ),
        if (answer.reasoning.isNotEmpty) ...[
          const SizedBox(height: GiuliaTokens.spacingM),
          _Section(
            title: 'Begründung',
            icon: Icons.psychology_alt_outlined,
            children: answer.reasoning,
          ),
        ],
        if (answer.evidence.isNotEmpty) ...[
          const SizedBox(height: GiuliaTokens.spacingM),
          GiuliaPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Title(icon: Icons.data_object, label: 'Relevante Daten'),
                const SizedBox(height: GiuliaTokens.spacingS),
                for (final evidence in answer.evidence)
                  _EvidenceRow(evidence: evidence),
              ],
            ),
          ),
        ],
        if (answer.uncertainty.isNotEmpty) ...[
          const SizedBox(height: GiuliaTokens.spacingM),
          _Section(
            title: 'Sicherheit / Unsicherheit',
            icon: Icons.info_outline,
            children: answer.uncertainty,
          ),
        ],
        if (answer.knowledge.isNotEmpty) ...[
          const SizedBox(height: GiuliaTokens.spacingL),
          const GiuliaSectionHeader(title: 'In der Academy vertiefen'),
          const SizedBox(height: GiuliaTokens.spacingS),
          for (final article in answer.knowledge)
            AcademyLink(
              articleId: article.articleId,
              label: '${article.title} · ${article.evidenceLabel}',
            ),
        ],
      ],
    );
  }
}

class _StoredAnswer extends StatelessWidget {
  const _StoredAnswer({super.key, required this.message});

  final CoachChatMessage message;

  @override
  Widget build(BuildContext context) {
    final data = message.structured;
    final title = data?['title'] as String? ?? giuliaWordmark;
    final reasoning = _strings(data?['reasoning']);
    final uncertainty = _strings(data?['uncertainty']);
    final evidence = _maps(data?['evidence']);
    final knowledge = _maps(data?['knowledge']);
    final confidence = data?['confidence'] as String?;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(title, style: text.headlineSmall)),
            if (confidence != null) _StoredConfidence(value: confidence),
          ],
        ),
        const SizedBox(height: GiuliaTokens.spacingM),
        _Section(
          title: 'Empfehlung',
          icon: Icons.route_outlined,
          children: [message.text],
          tone: GiuliaTokens.surface2,
        ),
        if (reasoning.isNotEmpty) ...[
          const SizedBox(height: GiuliaTokens.spacingM),
          _Section(
            title: 'Begründung',
            icon: Icons.psychology_alt_outlined,
            children: reasoning,
          ),
        ],
        if (evidence.isNotEmpty) ...[
          const SizedBox(height: GiuliaTokens.spacingM),
          GiuliaPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Title(icon: Icons.data_object, label: 'Relevante Daten'),
                const SizedBox(height: GiuliaTokens.spacingS),
                for (final item in evidence) _StoredEvidenceRow(data: item),
              ],
            ),
          ),
        ],
        if (uncertainty.isNotEmpty) ...[
          const SizedBox(height: GiuliaTokens.spacingM),
          _Section(
            title: 'Sicherheit / Unsicherheit',
            icon: Icons.info_outline,
            children: uncertainty,
          ),
        ],
        if (knowledge.isNotEmpty) ...[
          const SizedBox(height: GiuliaTokens.spacingL),
          const GiuliaSectionHeader(title: 'In der Academy vertiefen'),
          const SizedBox(height: GiuliaTokens.spacingS),
          for (final article in knowledge)
            if (article['articleId'] case final String articleId)
              AcademyLink(
                articleId: articleId,
                label:
                    '${article['title'] ?? 'Mehr erfahren'} · '
                    '${article['evidenceLabel'] ?? 'Wissen'}',
              ),
        ],
      ],
    );
  }
}

class _StoredEvidenceRow extends StatelessWidget {
  const _StoredEvidenceRow({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final value = data['value'];
    final unit = data['unit'] as String?;
    final caveat = data['caveat'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GiuliaTokens.spacingXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(data['label'] as String? ?? 'Messwert')),
          const SizedBox(width: GiuliaTokens.spacingM),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${value is num ? _number(value) : value ?? '-'}${unit == null ? '' : ' $unit'}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (caveat != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    caveat,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: GiuliaTokens.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StoredConfidence extends StatelessWidget {
  const _StoredConfidence({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: GiuliaTokens.spacingS,
      vertical: GiuliaTokens.spacingXs,
    ),
    decoration: BoxDecoration(
      color: GiuliaTokens.surface3,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      'Sicherheit ${_confidenceLabel(value)}',
      style: Theme.of(context).textTheme.labelSmall,
    ),
  );
}

List<String> _strings(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false)
    : const [];

String _confidenceLabel(String value) => switch (value) {
  'high' => 'hoch',
  'moderate' => 'mittel',
  'low' => 'niedrig',
  'insufficient' => 'nicht ausreichend',
  _ => value,
};

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
    this.tone,
  });

  final String title;
  final IconData icon;
  final List<String> children;
  final Color? tone;

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    tone: tone ?? GiuliaTokens.surface1,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Title(icon: icon, label: title),
        const SizedBox(height: GiuliaTokens.spacingS),
        for (final (index, value) in children.indexed) ...[
          if (index > 0) const SizedBox(height: GiuliaTokens.spacingS),
          Text(value),
        ],
      ],
    ),
  );
}

class _Title extends StatelessWidget {
  const _Title({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: GiuliaTokens.iconS, color: GiuliaTokens.accent),
      const SizedBox(width: GiuliaTokens.spacingS),
      Expanded(
        child: Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    ],
  );
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.evidence});
  final IntelligenceEvidence evidence;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: GiuliaTokens.spacingXs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(evidence.label)),
        const SizedBox(width: GiuliaTokens.spacingM),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${_number(evidence.value)}${evidence.unit == null ? '' : ' ${evidence.unit}'}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (evidence.caveat != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  evidence.caveat!,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: GiuliaTokens.textMuted,
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class _Confidence extends StatelessWidget {
  const _Confidence({required this.value});
  final IntelligenceConfidence value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: GiuliaTokens.spacingS,
      vertical: GiuliaTokens.spacingXs,
    ),
    decoration: BoxDecoration(
      color: GiuliaTokens.surface3,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      'Sicherheit ${value.label}',
      style: Theme.of(context).textTheme.labelSmall,
    ),
  );
}

String _number(num value) {
  if (value is int || value == value.roundToDouble()) return '${value.round()}';
  return value.toStringAsFixed(1).replaceAll('.', ',');
}
