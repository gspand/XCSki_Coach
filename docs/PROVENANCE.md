# Herkunft der Trainingsdaten im XC Ski Coach

Stand 26. November 2026. Abschnitt 7.3 der Produktspezifikation sperrt die Strava-Integration bis zur dokumentierten Freigabe des konkreten Einsatzes. Ein bestehendes Konto, eine lokale Kopie oder eine Umbenennung erteilen keine Freigabe. [Strava API Agreement](https://www.strava.com/legal/api) · [Strava API Policy](https://www.strava.com/legal/api_policy)

| Herkunft | Behandlung im eigenständigen Coach |
|---|---|
| Eigene Garmin-Verbindung | Freigegebene Aktivitäten laufen über den Garmin-Einstieg. Ein als Strava gekennzeichneter Datensatz wird abgewiesen. Verfügbare Gesundheitsdaten hängen von den tatsächlich erteilten Garmin-Rechten ab. |
| FIT direkt vom Gerät oder direkt aus Garmin Connect | Die Dateiauswahl erfragt die unmittelbare Bezugsquelle für Training und Leistungsdiagnostik. Die Trainingsdatei erhält eine profilgebundene Herkunftsbestätigung für ihre aus den Bytes abgeleitete Kennung. Bei der Testdiagnostik wird die Quelle im Testnachweis geführt. Eine FIT-Datei mit Strava als Hersteller im Dateikopf wird abgewiesen. |
| Alte FIT-Datei ohne belegte Bezugsquelle | Der Rohdatensatz bleibt erhalten. Der erneute Import derselben direkt bezogenen Trainingsdatei bestätigt die Herkunft anhand derselben Inhaltskennung. Eine Dateiendung allein genügt nicht. |
| Manuell erfasste Einheiten, unabhängig aufgezeichnete Ercolina-Einheiten | Zulässige Daten bleiben verfügbar. Ercolina-Projektionen übernehmen die Sperre ihrer verknüpften Quellsitzung. |
| Strava-API, bekannte Strava-Exporte, daraus abgeleitete Daten | Die App bietet keine Verbindung und keinen Abruf an. Auch der Bibliotheksclient stellt keine Netzverbindung her. Strava-Aktivitäten werden vor dem Schreiben neuer Aktivitäten oder Analyseprojektionen abgewiesen. |

Die SQLite-Lesemodelle filtern die Quellen vor Zeitfenster, Pagination, Deduplizierung und Lastrechnung. Bei überlappenden Aufzeichnungen bleibt eine unabhängig bezogene Kopie verwendbar. Welche zulässige Quelle eine Aktivitätsgruppe für den Coach vertritt, wird nur unter ihren zulässigen Sitzungen ermittelt. Historische Strava-Synchronisation gilt nicht als Beleg für ein trainingsfreies Datum.

Für Diagnostik, Beobachtungen, Schwellen, Zonen, Rekorde, Coachingnotizen und Planentscheidungen werden bestehende Sitzungs- und Testverknüpfungen ausgewertet. Ältere automatisierte Entscheidungen, Chatverläufe und Zustands-Snapshots ohne die neue Herkunftsgrenze werden von den aktuellen Leseroutinen ausgeschlossen. Der Coach baut benötigte Zustände neu auf. Die Rohdaten bleiben im privaten Trainingsarchiv. Der technische Roharchivzugriff ist keine Schnittstelle für Analysen, Prompts oder zukünftige Suchindizes.

## Nachweis und Grenzen

Die Regressionen in `test/training_provenance_test.dart` prüfen einen historischen Rohdatensatz beim Wiederöffnen, dessen unveränderte Originaldaten, eine unabhängige Garmin-Kopie, einen blockierten Ableitungsversuch, die Sicht eines anderen Profils, den direkten FIT-Import und den SQL-Leseweg für den Coach. Die Netztests prüfen die gesperrten Einstiege vor dem ersten HTTP-Aufruf. Das gilt für die hier integrierten Pfade. Ein künftiger Datenexport, Suchindex oder externer KI-Anbieter braucht einen eigenen Nachweis der Herkunftsgrenze.

Eine Originaldatei kann bytegleich aus verschiedenen Diensten bezogen werden. Der Coach kann ihre tatsächliche Transportgeschichte ohne zusätzliche Angaben nicht aus den Bytes rekonstruieren. Bei unbekannter Herkunft lässt die Dateiauswahl den Import abbrechen. Die gespeicherte Auskunft zur Bezugsquelle ist eine Nutzerangabe.
