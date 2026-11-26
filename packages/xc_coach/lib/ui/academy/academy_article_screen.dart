/// Ein Artikel, in drei Tiefen.
///
/// Der Aufbau ist überall derselbe, und das ist Absicht: Wer den zweiten
/// Artikel liest, weiss schon, wo er was findet — kurze Fassung oben, die
/// Missverständnisse unten, die Quellen ganz am Ende und eingeklappt.
library;

import 'package:flutter/material.dart';

import '../../academy/academy.dart';
import '../../academy/academy_library.dart';
import '../../academy/academy_search.dart';
import '../design_system.dart';

class AcademyArticleScreen extends StatefulWidget {
  const AcademyArticleScreen({
    super.key,
    required this.article,
    this.personalNote,
  });

  final AcademyArticle article;

  /// Ein Satz aus den eigenen Daten — «Dein LT1 liegt bei 198 W».
  ///
  /// Nur gesetzt, wenn der Wert wirklich vorliegt. Ein erfundener Bezug wäre
  /// schlimmer als keiner: Er sieht aus wie Wissen über den Leser.
  final String? personalNote;

  @override
  State<AcademyArticleScreen> createState() => _AcademyArticleScreenState();
}

class _AcademyArticleScreenState extends State<AcademyArticleScreen> {
  ArticleDepth _depth = ArticleDepth.brief;
  bool _showSources = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final density = GiuliaDensity.of(context);
    final article = widget.article;

    return Scaffold(
      backgroundColor: GiuliaTokens.surface0,
      appBar: AppBar(title: Text(article.category.label)),
      body: SafeArea(
        child: ListView(
          padding: density.pageInsets,
          children: [
            Text(article.title, style: text.headlineSmall),
            const SizedBox(height: GiuliaTokens.spacingS),
            Text(
              article.summary,
              style: text.bodyLarge?.copyWith(
                color: GiuliaTokens.textSecondary,
              ),
            ),
            const SizedBox(height: GiuliaTokens.spacingM),
            _EvidenceBadge(level: article.evidence),
            if (widget.personalNote != null) ...[
              SizedBox(height: density.cardGap),
              GiuliaPanel(
                tone: GiuliaTokens.surface2,
                child: Row(
                  children: [
                    const Icon(
                      Icons.person_outline,
                      size: GiuliaTokens.iconM,
                      color: GiuliaTokens.accent,
                    ),
                    const SizedBox(width: GiuliaTokens.spacingS),
                    Expanded(
                      child: Text(widget.personalNote!, style: text.bodyMedium),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: density.sectionGap),
            SegmentedButton<ArticleDepth>(
              segments: [
                for (final depth in ArticleDepth.values)
                  ButtonSegment(value: depth, label: Text(depth.label)),
              ],
              selected: {_depth},
              showSelectedIcon: false,
              // Grün ist reserviert: Es heisst «in Ordnung», nicht
              // «ausgewählt».
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: GiuliaTokens.surface3,
                selectedForegroundColor: GiuliaTokens.accent,
              ),
              onSelectionChanged: (selection) =>
                  setState(() => _depth = selection.first),
            ),
            SizedBox(height: density.cardGap),
            for (final paragraph in article.textFor(_depth)) ...[
              Text(paragraph, style: text.bodyLarge?.copyWith(height: 1.5)),
              const SizedBox(height: GiuliaTokens.spacingM),
            ],
            if (article.practicalExample != null) ...[
              SizedBox(height: density.cardGap),
              const GiuliaSectionHeader(title: 'Wie eine Einheit aussieht'),
              SizedBox(height: density.cardGap),
              GiuliaPanel(child: Text(article.practicalExample!)),
            ],
            if (article.progressMarkers.isNotEmpty) ...[
              SizedBox(height: density.sectionGap),
              const GiuliaSectionHeader(title: 'Woran du Fortschritt erkennst'),
              SizedBox(height: density.cardGap),
              GiuliaPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final marker in article.progressMarkers)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: GiuliaTokens.spacingXs,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.trending_up,
                              size: GiuliaTokens.iconS,
                              color: GiuliaTokens.success,
                            ),
                            const SizedBox(width: GiuliaTokens.spacingS),
                            Expanded(child: Text(marker)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (article.misconceptions.isNotEmpty) ...[
              SizedBox(height: density.sectionGap),
              const GiuliaSectionHeader(title: 'Häufige Missverständnisse'),
              SizedBox(height: density.cardGap),
              for (final item in article.misconceptions) ...[
                GiuliaPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '«${item.claim}»',
                        style: text.titleSmall?.copyWith(
                          color: GiuliaTokens.warning,
                        ),
                      ),
                      const SizedBox(height: GiuliaTokens.spacingXs),
                      Text(item.correction, style: text.bodyMedium),
                    ],
                  ),
                ),
                SizedBox(height: density.cardGap),
              ],
            ],
            if (article.related.isNotEmpty) ...[
              SizedBox(height: density.sectionGap),
              const GiuliaSectionHeader(title: 'Das gehört dazu'),
              SizedBox(height: density.cardGap),
              for (final id in article.related) ...[
                ?_relatedCard(context, id),
                SizedBox(height: density.cardGap),
              ],
            ],
            if (article.sources.isNotEmpty) ...[
              SizedBox(height: density.sectionGap),
              _Sources(
                sources: article.sources,
                expanded: _showSources,
                onToggle: () => setState(() => _showSources = !_showSources),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget? _relatedCard(BuildContext context, String id) {
    final related = articleById(id, library: academyLibrary);
    if (related == null) return null;
    return GiuliaPanel(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AcademyArticleScreen(article: related),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  related.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: GiuliaTokens.spacingXs),
                Text(
                  related.summary,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: GiuliaTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: GiuliaTokens.textMuted),
        ],
      ),
    );
  }
}

/// Wie gut belegt das ist — sichtbar, nicht versteckt.
class _EvidenceBadge extends StatelessWidget {
  const _EvidenceBadge({required this.level});
  final EvidenceLevel level;

  @override
  Widget build(BuildContext context) {
    final colour = switch (level) {
      EvidenceLevel.strong || EvidenceLevel.good => GiuliaTokens.success,
      EvidenceLevel.contextual => GiuliaTokens.accent,
      EvidenceLevel.limited || EvidenceLevel.practice => GiuliaTokens.warning,
    };
    return Tooltip(
      message: level.description,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_outlined,
            size: GiuliaTokens.iconS,
            color: colour,
          ),
          const SizedBox(width: GiuliaTokens.spacingXs),
          Text(
            level.label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: colour),
          ),
        ],
      ),
    );
  }
}

class _Sources extends StatelessWidget {
  const _Sources({
    required this.sources,
    required this.expanded,
    required this.onToggle,
  });

  final List<AcademySource> sources;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final unverified = sources.where((source) => !source.verified).length;

    return GiuliaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const Key('academy-sources-toggle'),
            onTap: onToggle,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${sources.length} wissenschaftliche '
                    '${sources.length == 1 ? 'Quelle' : 'Quellen'}',
                    style: text.titleSmall,
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  color: GiuliaTokens.textMuted,
                ),
              ],
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: GiuliaTokens.spacingM),
            for (final source in sources)
              Padding(
                padding: const EdgeInsets.only(bottom: GiuliaTokens.spacingS),
                child: Text(source.citation, style: text.bodySmall),
              ),
            if (unverified > 0) ...[
              const SizedBox(height: GiuliaTokens.spacingS),
              Text(
                // Ehrlicher Zwischenstand: Lieber sagen, dass die Angaben noch
                // nicht gegen die Originalarbeiten geprüft sind, als eine
                // Kennung zu zeigen, die auf nichts zeigt.
                'Die Angaben sind noch nicht gegen die Originalarbeiten '
                'geprüft; sie tragen deshalb keine Kennung.',
                style: text.bodySmall?.copyWith(color: GiuliaTokens.textMuted),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
