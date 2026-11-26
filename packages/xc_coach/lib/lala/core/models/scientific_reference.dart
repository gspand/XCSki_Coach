class ScientificReference {
  const ScientificReference({
    required this.authors,
    required this.title,
    required this.year,
    required this.journal,
    this.doi,
    this.url,
    required this.relevance,
  });

  final String authors;
  final String title;
  final int year;
  final String journal;
  final String? doi;
  final String? url;
  final String relevance;
}
