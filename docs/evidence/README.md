# Forschungsbibliothek für den XC Ski Coach

**Stand 26. November 2026.** Die Sammlung umfasst 47 Arbeiten mit überprüfter Bibliografie und gelesenem Abstract. Zu jeder Arbeit gibt es eine konkrete, deutschsprachige Aussage mit Fundstelle, untersuchter Gruppe und Grenze der Übertragbarkeit. Die Doppelstockstudie LA03 wurde vollständig ausgewertet. Für vier weitere Arbeiten wurden ergänzend Methodenabschnitte konsultiert. Keine Arbeit ist bereits vollständig fachlich beurteilt. Keine der neun abgeleiteten Regelideen ist für individuelle Trainingsentscheidungen freigegeben.

| Datei | Inhalt |
| --- | --- |
| [Quellenregister](sources.json) | Bibliografie, Online- und Ausgabejahr, Zugang, Lizenzstatus, verknüpfte Hinweise und Prüfstand |
| [Evidenztabelle](EVIDENCE.md) und [maschinenlesbare Aussagen](claims.json) | 47 getrennte Befunde mit Untersuchungsdesign, Stichprobe, Verfahren, Wirkung und Unsicherheit |
| [Volltextextraktion LA03](LA03.md) | Methoden, Sensitivität für den ausgeschlossenen Einzelwert, Tabellen, Abbildungen und Grenzen des Doppelstocktests |
| [Thematische Synthesen](SYNTHESIS.md) | Befunde im Zusammenhang, Gegenbefunde, Studiendesign und persönliche Übertragungsgrenzen |
| [Suchprotokoll](SEARCH.md) und [einzelne Suchergebnisse](search_log.json) | Abfragen, Trefferzahlen, gesichtete Titel, Deduplizierung, Auswahl und fehlende Zugänge |
| [Regelkandidaten](rules.json) | Herkunft, Ein-/Ausschluss, Parameter, Testfall und Freigabestatus je Version |

In der App lässt sich die Bibliothek offline nach Thema, Technik, Trainingsziel, Autor, Jahr, DOI/PMID und Bearbeitungsstand durchsuchen. Die Detailansicht führt vom konkreten Befund zur Originalquelle. Bei fehlender Stichprobengröße oder Altersangabe im ausgewerteten Material steht im Register `null`. Ein fehlender Wert darf nicht als Nullbeobachtung verwendet werden.

## Vom Suchtreffer zur Trainingsentscheidung

Ein neuer Suchtreffer bleibt zunächst in der Sichtungsliste. Zur Aufnahme wird die bibliografische Identität mit einer Primärquelle abgeglichen. „Abstract gelesen“ bedeutet, dass der vollständige Abstract für diese Fassung gelesen wurde. Ausschließlich auf Abstract-Ebene bearbeitete Claims tragen den Status `abstract_extracted`. Vollständig gelesene Quellen erhalten `full_text_read`, ihre im Volltext geprüfte Aussage `full_text_extracted`. Ein geladener Volltext, die Prüfung eines Methodenabschnitts oder ein Verweis auf eine frühere Sichtung genügt für den Status „Volltext gelesen“ nicht.

Der nächste Schritt je Prioritätsfrage ist die vollständige Auswertung von Methodik, Ergebnissen, Tabellen, Ausfällen und Unsicherheiten, gefolgt von einer fachlichen Beurteilung im Kontext gegensätzlicher Befunde. Die Freigabe eines konkreten Algorithmus braucht darüber hinaus eine bezeichnete Version, Eingangsgrößen, Ausschlüsse, bestandene Implementierungstests und dokumentierte Verantwortung. Die Regeldatei enthält Prüfideen und erwartete Fälle. Sie wird nicht als Regelwerk in den Coach geladen. Aktive Produktlogik benötigt einen eigenen Herkunftsnachweis.

Quellen-IDs bleiben bei Aktualisierungen stabil. Änderungen an einer Aussage erhalten eine neue Claim-Version, danach werden abhängige `claim_ids` und ihre Regelversionen erneut geprüft. Neue Errata, Geräteverfahren oder ein anderer Anwendungskontext können eine erneute Prüfung auslösen. Der lokale Konsistenztest läuft mit `python3 docs/evidence/validate.py`.
