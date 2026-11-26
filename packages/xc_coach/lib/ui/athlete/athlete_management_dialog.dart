/// Product-side profile and note editing.
///
/// The profile page owns the visible facts; these dialogs only collect a
/// person's explicit changes and send them to PlatformRepository. The
/// repository remains the permission boundary and records consent as an
/// immutable event.
library;

import 'package:flutter/material.dart';

import '../../database/platform_repository.dart';
import '../../domain/platform.dart';
import '../design_system.dart';

Future<bool> editAthleteDialog({
  required BuildContext context,
  required PlatformRepository platform,
  required String athleteId,
  required String actorUserId,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _EditAthleteDialog(
    platform: platform,
    athleteId: athleteId,
    actorUserId: actorUserId,
  ),
).then((changed) => changed ?? false);

class _EditAthleteDialog extends StatefulWidget {
  const _EditAthleteDialog({
    required this.platform,
    required this.athleteId,
    required this.actorUserId,
  });

  final PlatformRepository platform;
  final String athleteId;
  final String actorUserId;

  @override
  State<_EditAthleteDialog> createState() => _EditAthleteDialogState();
}

class _EditAthleteDialogState extends State<_EditAthleteDialog> {
  late final AthleteProfileRecord _profile = widget.platform.athleteProfile(
    widget.athleteId,
  );
  late final TextEditingController _name = TextEditingController(
    text: _profile.name,
  );
  late final TextEditingController _birthYear = TextEditingController(
    text: _profile.birthYear?.toString() ?? '',
  );
  final TextEditingController _consentName = TextEditingController();
  late final Set<String> _teamIds = _profile.teamIds.toSet();
  late String? _sex = _profile.sex;
  bool _confirmConsent = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _birthYear.dispose();
    _consentName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teams = widget.platform.teamsOf(_profile.organizationId);
    final isMinor = _isMinor(_birthYear.text);
    return AlertDialog(
      title: const Text('Athlet bearbeiten'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('edit-athlete-name'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: GiuliaTokens.spacingM),
              TextField(
                key: const Key('edit-athlete-birth-year'),
                controller: _birthYear,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Jahrgang'),
              ),
              const SizedBox(height: GiuliaTokens.spacingM),
              Wrap(
                spacing: GiuliaTokens.spacingS,
                children: [
                  for (final option in const [
                    ('w', 'Weiblich'),
                    ('m', 'Männlich'),
                  ])
                    ChoiceChip(
                      key: Key('edit-athlete-sex-${option.$1}'),
                      label: Text(option.$2),
                      selected: _sex == option.$1,
                      onSelected: (selected) =>
                          setState(() => _sex = selected ? option.$1 : null),
                    ),
                ],
              ),
              const SizedBox(height: GiuliaTokens.spacingL),
              Text('TEAMS', style: Theme.of(context).textTheme.labelMedium),
              if (teams.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: GiuliaTokens.spacingS),
                  child: Text('Noch kein Team angelegt.'),
                )
              else
                for (final team in teams)
                  CheckboxListTile(
                    key: Key('edit-athlete-team-${team.id}'),
                    value: _teamIds.contains(team.id),
                    contentPadding: EdgeInsets.zero,
                    title: Text(team.name),
                    onChanged: (selected) => setState(() {
                      if (selected ?? false) {
                        _teamIds.add(team.id);
                      } else {
                        _teamIds.remove(team.id);
                      }
                    }),
                  ),
              if (isMinor) ...[
                const SizedBox(height: GiuliaTokens.spacingL),
                Text(
                  'EINWILLIGUNG',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: GiuliaTokens.spacingS),
                const Text(
                  'Für Minderjährige wird eine benannte Bestätigung mit Datum '
                  'als unveränderlicher Eintrag gespeichert.',
                ),
                CheckboxListTile(
                  key: const Key('edit-athlete-consent-confirm'),
                  value: _confirmConsent,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Einwilligung liegt vor'),
                  onChanged: (value) =>
                      setState(() => _confirmConsent = value ?? false),
                ),
                if (_confirmConsent)
                  TextField(
                    key: const Key('edit-athlete-consent-name'),
                    controller: _consentName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Bestätigt durch',
                    ),
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: GiuliaTokens.spacingM),
                Text(
                  _error!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: GiuliaTokens.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('edit-athlete-save'),
          onPressed: _save,
          child: const Text('Speichern'),
        ),
      ],
    );
  }

  bool _isMinor(String raw) {
    final year = int.tryParse(raw.trim());
    return year != null && DateTime.now().toUtc().year - year < 18;
  }

  void _save() {
    final yearText = _birthYear.text.trim();
    final birthYear = yearText.isEmpty ? null : int.tryParse(yearText);
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    if (yearText.isNotEmpty &&
        (birthYear == null ||
            birthYear < 1900 ||
            birthYear > DateTime.now().year)) {
      setState(() => _error = 'Der Jahrgang ist keine plausible Jahreszahl.');
      return;
    }
    if (_isMinor(yearText) &&
        (!_confirmConsent || _consentName.text.trim().isEmpty)) {
      setState(
        () => _error =
            'Für Minderjährige Name und Bestätigung der Einwilligung angeben.',
      );
      return;
    }
    try {
      widget.platform.updateAthleteProfile(
        athleteId: widget.athleteId,
        actorUserId: widget.actorUserId,
        name: _name.text,
        birthYear: birthYear,
        sex: _sex,
        teamIds: _teamIds,
        consentConfirmedByName: _confirmConsent ? _consentName.text : null,
        consentConfirmedAtUtcUs: _confirmConsent ? now : null,
        nowUtcUs: now,
      );
      Navigator.of(context).pop(true);
    } on PlatformAccessException catch (error) {
      setState(() => _error = error.message);
    }
  }
}

Future<bool> addCoachNoteDialog({
  required BuildContext context,
  required PlatformRepository platform,
  required String athleteId,
  required String actorUserId,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _CoachNoteDialog(
    platform: platform,
    athleteId: athleteId,
    actorUserId: actorUserId,
  ),
).then((created) => created ?? false);

class _CoachNoteDialog extends StatefulWidget {
  const _CoachNoteDialog({
    required this.platform,
    required this.athleteId,
    required this.actorUserId,
  });
  final PlatformRepository platform;
  final String athleteId;
  final String actorUserId;

  @override
  State<_CoachNoteDialog> createState() => _CoachNoteDialogState();
}

class _CoachNoteDialogState extends State<_CoachNoteDialog> {
  final _body = TextEditingController();
  bool _visibleToAthlete = false;
  bool _trainerPrivate = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Notiz hinzufügen'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('athlete-note-body'),
            controller: _body,
            minLines: 4,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Beobachtung'),
          ),
          CheckboxListTile(
            key: const Key('athlete-note-visible'),
            contentPadding: EdgeInsets.zero,
            value: _visibleToAthlete,
            onChanged: (value) => setState(() {
              _visibleToAthlete = value ?? false;
              if (_visibleToAthlete) _trainerPrivate = false;
            }),
            title: const Text('Auch für Athlet sichtbar'),
          ),
          CheckboxListTile(
            key: const Key('athlete-note-trainer-private'),
            contentPadding: EdgeInsets.zero,
            value: _trainerPrivate,
            onChanged: (value) => setState(() {
              _trainerPrivate = value ?? false;
              if (_trainerPrivate) _visibleToAthlete = false;
            }),
            title: const Text('Nur für mich als Trainer sichtbar'),
            subtitle: const Text(
              'Auch die sportliche Leitung sieht diese Notiz nicht.',
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: GiuliaTokens.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        key: const Key('athlete-note-save'),
        onPressed: _save,
        child: const Text('Speichern'),
      ),
    ],
  );

  void _save() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    try {
      widget.platform.writeCoachNote(
        id: 'note-${widget.athleteId}-$now',
        athleteId: widget.athleteId,
        authorUserId: widget.actorUserId,
        body: _body.text,
        visibility: _trainerPrivate
            ? 'trainer_private'
            : (_visibleToAthlete ? 'athlete' : 'coaching_staff'),
        writtenAtUtcUs: now,
      );
      Navigator.of(context).pop(true);
    } on PlatformAccessException catch (error) {
      setState(() => _error = error.message);
    }
  }
}
