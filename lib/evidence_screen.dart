import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

typedef _Record = Map<String, dynamic>;

enum _ReviewFilter {
  all('Alle Prüfstände'),
  abstractRead('Abstract gelesen'),
  fullTextRead('Volltext ausgewertet'),
  expertReviewed('Fachlich beurteilt'),
  approved('Regel freigegeben');

  const _ReviewFilter(this.label);
  final String label;
}

class _Evidence {
  _Evidence(this.source, this.claim);

  final _Record source;
  final _Record claim;
  String get id => source['id'] as String;
  String get title => source['title'] as String;
  String get year => (source['issue_year'] ?? source['online_year']).toString();
  String get authors => (source['authors'] as List).join(', ');
  bool get fullTextRead => claim['status'] == 'full_text_extracted';
  bool get abstractRead => source['status'] == 'abstract_read' || fullTextRead;
  bool get approved => claim['prescription_approved'] == true;
  bool get expertReviewed => claim['independent_expert_review'] == true;
  String get status => approved
      ? _ReviewFilter.approved.label
      : expertReviewed
      ? _ReviewFilter.expertReviewed.label
      : fullTextRead
      ? _ReviewFilter.fullTextRead.label
      : abstractRead
      ? _ReviewFilter.abstractRead.label
      : 'Bibliografisch geprüft';

  late final String searchable = [
    id,
    title,
    year,
    authors,
    source['research_topic'],
    source['pmid'],
    source['doi'],
    claim['technique'],
    claim['target'],
    claim['scope'],
    claim['finding'],
    claim['study_design'],
    status,
    ...(claim['tags'] as List),
  ].join(' ').toLowerCase();

  bool matches(List<String> terms, _ReviewFilter review) {
    final statusMatches = switch (review) {
      _ReviewFilter.all => true,
      _ReviewFilter.abstractRead => abstractRead,
      _ReviewFilter.fullTextRead => fullTextRead,
      _ReviewFilter.expertReviewed => expertReviewed,
      _ReviewFilter.approved => approved,
    };
    return statusMatches && terms.every(searchable.contains);
  }
}

/// Local research library, available offline without sending search terms off-device.
class EvidenceScreen extends StatefulWidget {
  const EvidenceScreen({super.key});

  @override
  State<EvidenceScreen> createState() => _EvidenceScreenState();
}

class _EvidenceScreenState extends State<EvidenceScreen> {
  final search = TextEditingController();
  _ReviewFilter review = _ReviewFilter.all;
  late final Future<List<_Evidence>> library = load(
    DefaultAssetBundle.of(context),
  );

  Future<List<_Evidence>> load(AssetBundle bundle) async {
    final raw = await Future.wait([
      bundle.loadString('docs/evidence/sources.json'),
      bundle.loadString('docs/evidence/claims.json'),
    ]);
    final sources = (jsonDecode(raw.first)['sources'] as List).cast<_Record>();
    final claims = (jsonDecode(raw.last)['claims'] as List).cast<_Record>();
    final byId = {for (final claim in claims) claim['id']: claim};
    return [
      for (final source in sources)
        _Evidence(source, byId[source['primary_claim_id']]!),
    ];
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forschungsbibliothek')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: FutureBuilder<List<_Evidence>>(
              future: library,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      'Die Forschungsbibliothek konnte nicht geladen werden.',
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final terms = search.text
                    .trim()
                    .toLowerCase()
                    .split(RegExp(r'\s+'))
                    .where((s) => s.isNotEmpty)
                    .toList();
                final matches = snapshot.requireData
                    .where((e) => e.matches(terms, review))
                    .toList();
                return CustomScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      sliver: SliverList.list(
                        children: [
                          TextField(
                            controller: search,
                            onChanged: (_) => setState(() {}),
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              labelText: 'Thema, Technik oder Trainingsziel',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: search.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Suche löschen',
                                      icon: const Icon(Icons.clear),
                                      onPressed: () => setState(search.clear),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 14,
                            children: [
                              DropdownButton<_ReviewFilter>(
                                value: review,
                                items: [
                                  for (final f in _ReviewFilter.values)
                                    DropdownMenuItem(
                                      value: f,
                                      child: Text(f.label),
                                    ),
                                ],
                                onChanged: (f) {
                                  if (f != null) setState(() => review = f);
                                },
                              ),
                              Text(
                                matches.length == 1
                                    ? '1 Quelle'
                                    : '${matches.length} Quellen',
                              ),
                            ],
                          ),
                          if (matches.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                'Für diese Auswahl gibt es keine Quellen.',
                              ),
                            ),
                        ],
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                      sliver: SliverList.builder(
                        itemCount: matches.length,
                        itemBuilder: (context, index) {
                          final e = matches[index];
                          return ListTile(
                            key: ValueKey(e.id),
                            title: Text(e.source['research_topic'] as String),
                            subtitle: Text('${e.id} · ${e.year} · ${e.status}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => _EvidenceDetails(e),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _EvidenceDetails extends StatelessWidget {
  const _EvidenceDetails(this.entry);

  final _Evidence entry;

  @override
  Widget build(BuildContext context) {
    final source = entry.source;
    final claim = entry.claim;
    final theme = Theme.of(context).textTheme;
    final fields = <String, String>{
      'Befund': claim['finding'] as String,
      'Übertragbarkeit und Grenzen': claim['limitations'] as String,
      'Untersuchte Gruppe': [
        claim['scope'],
        if (claim['sample'] != null) 'Stichprobe: ${claim['sample']}',
        if (claim['age'] != null) 'Alter: ${claim['age']}',
      ].join(' · '),
      'Methode': [
        claim['intervention_comparison_measurement'],
        claim['duration_or_design'],
      ].join(' · '),
      'Prüfstand': [
        entry.status,
        claim['locator'],
        if (!entry.approved)
          'Für individuelle Trainingsvorgaben ist dieser Befund noch nicht freigegeben.',
      ].join(' · '),
    };
    return Scaffold(
      appBar: AppBar(title: Text('Quelle ${entry.id}')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(entry.title, style: theme.headlineSmall),
                const SizedBox(height: 8),
                SelectableText(
                  '${entry.authors} · ${source['journal']} · ${entry.year}',
                ),
                for (final field in fields.entries) ...[
                  const SizedBox(height: 20),
                  Text(field.key, style: theme.titleMedium),
                  const SizedBox(height: 3),
                  SelectableText(field.value),
                ],
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Originalquelle öffnen'),
                    onPressed: () async {
                      final uri = Uri.parse(claim['primary_url'] as String);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        if (await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        )) {
                          return;
                        }
                      } on PlatformException {
                        // The source identifier remains visible if the system has no handler.
                      }
                      if (messenger.mounted) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Die Originalquelle konnte nicht geöffnet werden.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
                SelectableText('DOI ${source['doi']}'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
