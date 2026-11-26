# Register der aktiven Tagesentscheidung

Stand 26. November 2026, private Version 0.5.0. Die Entscheidung entsteht in `CanonicalTodayService` und `DailyDecisionEngine`. Ihre Revision bindet die Ausgabe und ihre Begründung an Person und lokalen Tag. Zeitstempel der Berechnung sind von Messzeitpunkten getrennt. Die sichtbare Kurzfassung auf der Watch enthält keine freien Symptomtexte.

| Regel und Herkunft | Eingaben und Wirkung | Geltungsgrenze und Prüfung |
|---|---|---|
| XC-SCHUTZ-1 · Vorsorgliche Produktregel | Gemeldete Krankheitssymptome oder bereits als schwer bzw. kritisch markierte Einschränkung lösen einen Ruhetag aus. Der Zweig läuft vor der Einheitenauswahl. | Die Software verarbeitet eine Selbstauskunft. Eine gute subjektive Erholung kann die Sperre nicht aufheben. Regression in `workout_selection_test.dart`, einschließlich kritischer Stufe bei Erholung 10. Eine medizinische Einzelfallfreigabe erfordert Fachpersonal. |
| XC-SYMPTOM-1 · Vorsorgliche Produktregel | Bei aktiviertem privaten Tracking und aktuell als schwer gemeldeten Beschwerden folgt Erholung. | Eine geschätzte Zyklusphase ist kein Auslöser. Personenbezogene Wirksamkeits- und Datenschutzabnahme auf gemeinsam genutzten Geräten stehen aus. |
| XC-RUHE-1 · Persönliche Entscheidung | Ein aktiver Ruhetagswunsch gilt für die Person und den lokalen Tag. | Abgrenzung bei Mitternacht, Neubewertung und Versionierung werden in `day_release_test.dart` geprüft. |
| XC-ERHOLUNG-1 · Übernommene Trainerheuristik | Ein kritischer Erholungsbedarf oder ausgeprägte subjektive Erschöpfung priorisiert Erholung. Das bestehende Modell prüft verfügbare Zeit und Schmerzen für die Auswahl aktiv/passiv. | Modellschwellen für Selbstauskunft und Dosis sind Produktparameter. Eine Behauptung über beschleunigte physiologische Erholung ist daraus nicht ableitbar. |
| Dosis, Sporttransfer, Reizabstand · Übernommene Trainerheuristiken | Die Einheitenauswahl berücksichtigt sportartspezifische Historie, Tagesverfügbarkeit, Planabsicht und tolerierte Dosis. Reizabstand wird abhängig von Trainingsblock und Belastungsart geprüft. | Die Punktegewichtung und Zeitfenster besitzen noch keine individuelle prospektive Validierung. Ein fehlender Wochenplan wird als Annahme angezeigt. |
| Forschungskandidaten · In Prüfung | Neun getrennte Kandidaten mit Studienbezug, Eingangsgrößen, Ausschlüssen und erwarteten Testfällen. | Keiner wird durch Aufnahme einer Quelle in der App aktiviert. [Forschungsregister](evidence/rules.json) |

Die Detailprüfung der übrigen übernommenen Bewertungsgewichte und ihrer Wechselwirkungen steht aus. Die sportwissenschaftliche Abnahme soll Einzelfälle einschließlich gegensätzlicher Signale beurteilen. Die Klinik-, Geräte- und Softwareprüfungen decken unterschiedliche Fragen ab.
