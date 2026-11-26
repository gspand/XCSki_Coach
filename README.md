# XC Ski Coach

Privater Langlauf-Coach für Jan und Karina. Flutter für Android, iPhone, iPad, macOS und Windows. Die native watchOS-Begleitapp empfängt den Tagesplan des auf dem gekoppelten iPhone gewählten Uhrenprofils. Sie zeigt Datum, Dauer, Intensität, Ablauf und Begründung an.

## Starten

Mit Flutter 3.44.8 und Dart 3.12.2 im Projektverzeichnis `flutter pub get` und beispielsweise `flutter run -d macos` ausführen. Für Windows auf einem Windows-Rechner mit Flutter und den Visual-Studio-C++-Desktoptools `flutter build windows` verwenden. Für iPhone und Watch das iOS-Workspace mit Xcode öffnen und beide Targets für das eigene Entwicklungsteam signieren.

Beim ersten Start ein vollständiges GIULIA-SQLite-Archiv auswählen oder mit zwei leeren Profilen anfangen. Der Import erstellt einen eigenen Datenbankstand. Eine bestehende Coach-Datenbank wird beim Erstimport geschützt. Daten bleiben lokal auf dem jeweiligen Gerät. Auf der Uhr wird der letzte übertragene Trainingstag mit Datum angezeigt. Die Zuordnung erfolgt im Profilmenü des iPhones.

## Training und Quellen

Heute, Plan und die Coach-Antwort auf die heutige Einheit lesen dieselbe Tagesentscheidung. Training, Wettkampfziele, Verfügbarkeit, Diagnostik und Check-ins fließen in den Langlauf-Coach ein. Über das Profilmenü lassen sich Einheiten planen, Leistungsdiagnostik öffnen und FIT-Dateien importieren. Die Rohdatei bleibt beim FIT-Import erhalten.

Unter **Plan → Monatskalender** stehen Wettkämpfe, geplante und absolvierte Einheiten je Tag. **Leistungsdiagnostik → Einzelproben** erfasst die Anzeige eines Laktatmessgeräts mit Probezeit und Stufe. **Trainingswissen → Quellen suchen** öffnet die Offline-Forschungsbibliothek.

Die Trainingsübersicht zeigt die heutige Coach-Empfehlung, die geplanten und absolvierten Minuten je Wochentag sowie das wichtigste kommende Saisonziel. Garmin-Messwerte sind nach Profil und Messtag abrufbar.

Über das Uhr-Symbol öffnet **Mit Garmin verbinden** die Kontofreigabe. Garmin liefert neue freigegebene Aktivitäten und Gesundheitsdaten über den XC-Eingang. Die App bestätigt eine Lieferung nach dem lokalen Speichern und aktualisiert die Grundlage der Tagesentscheidung. Der Server fordert historische Daten mit derselben Verbindung an. Bei einer Ablehnung durch Garmin zeigt die App den Status an. Unter **Optionaler Direktabruf** bleibt ein separater persönlicher Zugang verfügbar.

Über **Übersicht anpassen** lassen sich Karten je Profil anordnen und einblenden. **Trainingsbuch** filtert nach Quelle. **Zuletzt von Garmin** zeigt, ob die letzte Aktivität im Trainingsumfang der aktuellen Empfehlung enthalten ist. [Abnahmestand](docs/ACCEPTANCE.md) · [Funktionsmatrix](docs/FEATURE_MATRIX.md)

Die Strava-Anbindung ist bis zur fachbezogenen Partnerfreigabe gesperrt. Der FIT-Import fragt nach der direkten Bezugsquelle. Einzelheiten stehen im [Herkunftsnachweis](docs/PROVENANCE.md).

## Herkunft und Prüfung

Der Coach-Kern ist als eigenständiges Flutter-Paket unter `packages/xc_coach` enthalten. Grundlage ist der Arbeitsstand von `Documents/Giulia/giulia_training_app`, einschließlich der dort entwickelten Langlauf-Logik. Das Datenbankschema stammt aus dem GIULIA-Stand `ea0c8d329891` mit Archivversion 31. Version 32 ergänzt im XC Coach die Korrekturhistorie für manuell übernommene Laktatproben. Das Projekt benötigt beim Bauen keinen GIULIA-Checkout.

Die App-Tests laufen mit `flutter test`. Die übernommenen fachlichen Regressionstests laufen im Verzeichnis `packages/xc_coach` ebenfalls mit `flutter test`. Für den optionalen Archivtest setzen `XC_SOURCE_ARCHIVE` und `XC_NEW_ARCHIVE` die Quelldatei und einen neuen, noch unbenutzten Zielpfad. Der Test kopiert das Archiv tatsächlich, vergleicht die Tabellenbestände und berechnet eine Empfehlung für beide Profile.
