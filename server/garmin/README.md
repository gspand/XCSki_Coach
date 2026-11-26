# Garmin-Empfang

Die XC-Module laufen im bestehenden GIULIA-Gateway. Die App verwendet eine eigene Installation je Profil. Die Datenbank speichert zugestellte Garmin-Ereignisse verschlüsselt bis zur Bestätigung des Clients. Der Historienauftrag speichert jeden von Garmin angenommenen Zeitabschnitt und unterscheidet ausstehende Lieferungen von abgelehnten oder noch ungeprüften Anforderungen.

In diesem Verzeichnis prüft `npm test` die Historienverarbeitung mit Node ab 22.13. Zum Nachbauen des eingesetzten Gateways im GIULIA-Servercheckout von Basis `8808f4a` die drei Dateien aus `src/` nach `server/giulia/src/` und den Historientest nach `server/giulia/test/` übernehmen. Anschließend `git apply /pfad/zu/gateway.patch` aus dem Stammverzeichnis des Servercheckouts ausführen. Die vollständigen Serverprüfungen laufen in `server/giulia` mit `npm ci` und `npm test`.
