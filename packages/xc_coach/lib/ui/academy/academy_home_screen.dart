/// Der Einstieg in die Wissensschicht.
///
/// Oben die Suche, weil die meisten mit einer Frage kommen und nicht mit dem
/// Wunsch zu stöbern. Darunter die Bereiche — und in jedem nur so viele
/// Artikel, wie es wirklich gibt: Eine Kategorie, die leer ist, wird nicht
/// gezeigt. Ein Verzeichnis mit Karteileichen bringt jemandem bei, dass hier
/// nichts steht.
library;

import 'package:flutter/material.dart';
import '../../app/mirco_preview.dart';

import '../../academy/academy.dart';
import '../../academy/academy_library.dart';
import '../../academy/academy_search.dart';
import '../design_system.dart';
import 'academy_article_screen.dart';

class AcademyHomeScreen extends StatefulWidget {
  const AcademyHomeScreen({super.key, this.library = academyLibrary});

  final List<AcademyArticle> library;

  @override
  State<AcademyHomeScreen> createState() => _AcademyHomeScreenState();
}

class _AcademyHomeScreenState extends State<AcademyHomeScreen> {
  final TextEditingController _query = TextEditingController();
  List<AcademyArticle> _results = const [];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search(String value) =>
      setState(() => _results = searchAcademy(value, library: widget.library));

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final density = GiuliaDensity.of(context);
    final searching = _query.text.trim().isNotEmpty;

    return ListView(
      padding: density.pageInsets,
      children: [
        Text(
          (mircoPreview
              ? 'Understand your training. Understand your performance.'
              : 'Verstehe dein Training. Verstehe deine Leistung.'),
          style: text.titleMedium?.copyWith(color: GiuliaTokens.textSecondary),
        ),
        SizedBox(height: density.cardGap),
        TextField(
          key: const Key('academy-search'),
          controller: _query,
          onChanged: _search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: (mircoPreview
                ? 'What are you looking for? For example, “Zone 2”'
                : 'Wonach suchst du? Zum Beispiel «Zone 2»'),
          ),
        ),
        SizedBox(height: density.sectionGap),
        if (searching) ...[
          if (_results.isEmpty)
            const GiuliaEmptyState(
              icon: Icons.search_off_outlined,
              title: (mircoPreview
                  ? 'No matching articles yet'
                  : 'Dazu steht hier noch nichts'),
              description: (mircoPreview
                  ? 'The library is growing. No article is available for this search yet.'
                  : 'Die Wissensschicht wächst. Was fehlt, fehlt — erfunden '
                        'wird nichts.'),
            )
          else
            for (final article in _results) ...[
              _ArticleCard(article: article),
              SizedBox(height: density.cardGap),
            ],
        ] else
          for (final category in AcademyCategory.values) ...[
            ?_categorySection(context, category, density),
          ],
      ],
    );
  }

  Widget? _categorySection(
    BuildContext context,
    AcademyCategory category,
    GiuliaDensity density,
  ) {
    final articles = articlesOf(category, library: widget.library);
    if (articles.isEmpty) return null;
    return Padding(
      padding: EdgeInsets.only(bottom: density.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GiuliaSectionHeader(
            title: category.label,
            subtitle: category.description,
          ),
          SizedBox(height: density.cardGap),
          for (final article in articles) ...[
            _ArticleCard(article: article),
            SizedBox(height: density.cardGap),
          ],
        ],
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.article});
  final AcademyArticle article;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GiuliaPanel(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AcademyArticleScreen(article: article),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(article.title, style: text.titleSmall),
                const SizedBox(height: GiuliaTokens.spacingXs),
                Text(
                  article.summary,
                  style: text.bodySmall?.copyWith(
                    color: GiuliaTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: GiuliaTokens.spacingS),
          const Icon(Icons.chevron_right, color: GiuliaTokens.textMuted),
        ],
      ),
    );
  }
}
