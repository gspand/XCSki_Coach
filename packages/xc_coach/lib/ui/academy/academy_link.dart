/// Die Verbindung von einer Zahl zu ihrer Erklärung.
///
/// Das ist der eigentliche Zweck der Wissensschicht: nicht ein Lexikon, das
/// man aufsucht, sondern eine Antwort dort, wo die Frage entsteht. Neben
/// einem LT2-Wert, neben einer geplanten Einheit, neben einem Testergebnis.
///
/// Der Baustein bleibt bewusst klein und leise — ein Wort, kein Banner. Wer
/// die Erklärung nicht braucht, soll nicht daran vorbeilesen müssen.
library;

import 'package:flutter/material.dart';

import '../../academy/academy.dart';
import '../../academy/academy_library.dart';
import '../../academy/academy_search.dart';
import '../design_system.dart';
import 'academy_article_screen.dart';

class AcademyLink extends StatelessWidget {
  const AcademyLink({
    super.key,
    required this.articleId,
    this.label = 'Warum?',
    this.personalNote,
    this.library = academyLibrary,
  });

  /// Der Artikel, der die Frage beantwortet.
  final String articleId;

  /// Was danebensteht — «Warum?», «Mehr erfahren», «Was trainiere ich damit?».
  final String label;

  /// Ein Satz aus den eigenen Daten. Nur setzen, wenn der Wert vorliegt.
  final String? personalNote;

  final List<AcademyArticle> library;

  @override
  Widget build(BuildContext context) {
    final article = articleById(articleId, library: library);
    // Fehlt der Artikel, erscheint nichts. Ein Verweis ins Leere ist
    // schlimmer als kein Verweis.
    if (article == null) return const SizedBox.shrink();

    return InkWell(
      key: Key('academy-link-$articleId'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AcademyArticleScreen(
            article: article,
            personalNote: personalNote,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: GiuliaTokens.spacingXs),
        child: Row(
          children: [
            const Icon(
              Icons.help_outline,
              size: GiuliaTokens.iconS,
              color: GiuliaTokens.accent,
            ),
            const SizedBox(width: GiuliaTokens.spacingXs),
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: GiuliaTokens.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
