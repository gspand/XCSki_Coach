# Abnahme der eigenständigen XC-Plattform

Stand 26.11.2026. **Teillieferung.** Die folgenden Nachweise stammen von einem Mac, dem tatsächlichen GIULIA-v31-Archiv, seinem redigierten Vergleichsstand und separaten synthetischen Regressionen. Eine bestandene Softwareprüfung weist genau den beschriebenen Pfad nach. Neu verbundene reale Uhren, Labortests, bestehende Garmin-Konten und fachliche Freigaben haben eigene Abnahmebedingungen.

## Aktualisierung mit der privaten Mac-Version 0.6.0

Ein Feldtest am 26. November bestätigte die erneute Zustellung einer bestehenden Garmin-Aktivitätsdatei über das offizielle Partnerwerkzeug. Die laufende App übernahm die Datei automatisch in das richtige Trainingsbuch. Der Vergleich der Tagesberechnung mit und ohne genau diese Einheit verwendete eine schreibgeschützte Datenbank. Die Anzahl der Einheiten, Bewegungszeit und Strecke unterschieden sich exakt um den verifizierten Beitrag. Eine neu mit der Uhr aufgezeichnete Einheit und ein mehrjähriger Vollabgleich bleiben eigene Abnahmen. Garmin lehnte den historischen Export mit HTTP 412 ab. Der Status ist im Coach sichtbar. Der klassische GIULIA-Import ist weiterhin ausgeschaltet.

## Durchgeführte Läufe

| Prüfung | Beobachtetes Ergebnis |
|---|---|
| Vollständiger Migrationsvergleich | 66 Tabellen einschließlich Rohframes, Samples und BLOBs. 6.637.391 Zeilen nach dokumentierter Redigierung identisch, keine Fremdschlüsseldifferenz. [Daten und Nachweis](BESTAND.md) |
| Vollständiger Erststart mit echten Daten | Fünf Tests bestanden im Lauf für Archivredigierung, Fremdprofilgrenze und echten v31→v32-Replay. Wiederholte Berechnung für beide lokalen Profile liefert je die zugehörige Empfehlung. |
| Gerenderte Daten | Read-only-Widgetlauf mit beiden realen Profilen. Heute- und Dashboardansicht, Planungsziel, fehlende Werte und 360 × 780 wurden in der Flutter-Testumgebung geprüft. Foto-/Bildschirmprüfung auf mehreren physischen Geräten separat offen. |
| Entscheidung, Monatskalender und Uhr | day_release_test prüft beide Profile und geräteübergreifend gleiche Entscheidung und Revision. month_plan_test prüft Monatswechsel, richtige Person und Planung eines gewählten Tages. test/watch/WatchDeliveryTest.swift prüft verzögerte Zustellung, Widerruf und Neustart im Swift-Hosttest. |
| Modell und Herkunft | 270 Kernprüfungen im Lauf auf dem Mac. Enthalten sind Load-/EWMA-Referenzen, FIT-Nordic-Sport, ungültige CRC, Coach-Fälle und die eingeschränkte Datenherkunft. Zusätzlich lief training_provenance_test gezielt durch. |
| Frontend und Plattformen | Flutter-App, wissenschaftliche Suche, Archiv, Garmin-Adapter und manuelle Proben besitzen eigene Tests. Android-35-Emulator bis ins Dashboard über den regulären Release-Erststart, iPhone mit iOS 27 im Simulator vom leeren Archiv bis zur Übersicht mit zwei Profilen (integration_test/first_start_test.dart). Bei der Android-Prüfung wurde eine unzulässige Übergabe von Flutter-Zustand an den Hintergrundprozess reproduziert, behoben und im Release erneut geprüft. macOS-Release, iOS-Geräte-Bundle (ohne App-Store-Signaturbeleg) und Android-Release-APKs für arm64-v8a, armeabi-v7a und x86_64 gebaut. Die Builddateien stammen vom 26.11. Ein iPhone-Bundle enthält die Watch-App. Windows-Build und physischer Uhrenlauf sind offen. Die separaten Buildläufe haben nicht zwingend denselben Stand wie der spätere Monatskalendertest. |

## Verbindliche Kriterien aus Abschnitt 18

| Nr. | Stand | Nachweis oder noch erforderlicher Versuch |
|---|---|---|
| 01 | Teil | Beide realen Profile getrennt gerendert, Inkonsistenz bei Fremdprofil und falscher Providerbindung abgelehnt. Mandantenübergreifende Suche, Jobrechte und Mehrgeräte-Synchronisierung vollständig testen. |
| 02 | Bestanden für dieses Archiv | Vollvergleich, Gruppenprüfungen, Datumsgrenzen und Referenzen in migration-receipt.json. Unbeschädigte Quelle zum Wiederholen verfügbar. |
| 03 | Bestandener Decoderfall | garmin_fit_decoder_test prüft Langlauf mit Geschwindigkeit ohne Watt und generischen Nordic-Subsport. Der reale Gerätedateitest je Uhrenmodell bleibt separat. |
| 04 | Teil | Identischer Inhalt hat stabilen Hash/Quellschlüssel. Reale Paarung FIT + Garmin mit abweichenden Fremdkennungen und genau einer Lastbuchung noch nachweisen. |
| 05 | Teil | Ungültige Prüfsumme wird abgewiesen, lückenhafte Gesundheitsserien zeichnen keine geschlossene Linie. Vollständige Invalid-/Timer-/Pausenmatrix für alle Sensoren offen. |
| 06 | Teil | Tagesentscheidung und lokale Datumszuordnung werden über UTC-Grenze geprüft. Reise mit Zeitzonenwechsel, beide DST-Umstellungen und spät gemeldeter Schlaf benötigen eigene Referenzfälle. |
| 07 | Teil | Last- und EWMA-Kerntests, unabhängiges Impulsbeispiel in METRICS.md. Vollständiger Serienvergleich einschließlich aller Rohimporte, RPE-Grenzen und Methodenwechsel offen. |
| 08 | Teil | Zonensätze und Berechnungsläufe gespeichert. Rückwirkungsfreiheit bei Parserupgrade und durchgehend unterscheidbare Plan-/Ist-Szenarien prüfen. |
| 09 | Teil | Unbekannte Tage und fehlende HRV sind modell-/anzeigeseitig gesondert behandelbar. Widersprüchliche Sensorik und Befinden auf echten Fällen fachlich beurteilen. |
| 10 | Teil | Schutzpfade und Coaching-Testfälle im Kern. Der reproduzierte Konflikt aus einem kritischen Schutzsignal und Erholung 10/10 lieferte zunächst Training. Nach Korrektur verlangt die Regression eine Ruheentscheidung. Eine unabhängige sportfachliche Beurteilung steht aus. [Tagesregeln](COACH_RULES.md) |
| 11 | Teil | Planservice unterstützt Auslassen, geschlossener Coach-Loop besitzt Regressionen. Folgewoche auf unerwünschte hochintensive Kompensation prüfen. |
| 12 | Teil | Kalender kann mehrere Einheiten am Tag führen. Übernahme manueller Fixierung bei Neuberechnung und Fortsetzung/Abbruch bereits gelaufener Schritte komplett abnehmen. |
| 13 | Teil | Entscheidung und Revision werden heute an Dashboard, Coach, Kalender und Watch-Nachricht übergeben. Verzögerung und Widerruf im Swift-Hosttest. Echte gepaarte Uhr und Rückkanal offen. |
| 14 | Teil | Lokaler Inbox-Commit geht der Bestätigung voraus. Wiederholung, Konflikte zwischen echten Geräten, Offline-Check-in, Lösch-/Widerrufsereignis und Rückimport-Schleife gemeinsam abnehmen. |
| 15 | Teil / externer Zugang | Jans verbundenes Konto, vier Gesundheitsfelder und der Weg vom echten Aktivitäts-FIT bis zur Coach-Entscheidung sind nachgewiesen. Der Historienabruf erhielt HTTP 412. Tokenablauf, Karinas Kontobindung und Einwilligung sowie das Ausführen eines geplanten Garmin-Workouts bleiben offen. [Felder und Geräte](CONNECTORS.md) |
| 16 | Geprüfte Sperrpfade | Gesperrte Strava-Herkunft wird von den Datensichten und den Regressionen für direkte und abgeleitete Eingänge geprüft. Aktivierung setzt rechtlich tragfähige Produktfreigabe voraus. |
| 17 | Teil | Quellen, Claims, Methoden-/Freigabestatus und Regeln getrennt, Suche bedienbar. Fachprüfung und prospektiver Test vor der Freigabe einer konkreten automatischen Regel nötig. [Register](evidence/README.md) |
| 18 | Teil | Einwilligungsgebundener Zykluspfad, getrennte Gesundheitsserien und Kernfälle. Echte Messung, End-to-End-Widerruf und vertrauliche Mehrnutzeransicht offen. |
| 19 | Teil | Kleiner Dashboard-Viewport, Archiv- und Leerzustände getestet. Größtmögliche Schrift, alle Zielgrößen, Interaktionszeiten langer Mehrjahresserien und visuelle Geräteabnahme offen. |
| 20 | Teil | macOS, iOS-Gerätebundle und Android-APKs gebaut, Watch-Bundle eingebettet. Erststart durchgehend in Android-35-Emulator und iPhone-iOS-27-Simulator geprüft. Windows benötigt einen Windows-Host und Visual Studio C++-Toolchain. Signierung, physische Geräte und App-Auslieferung gesondert prüfen. |
| 21 | Teil | Wiederholung des vollständigen Erstimports, unbekannte Schemata und sichere Nichtveröffentlichung geprüft. Backup/Restore des eigenständigen Betriebsarchivs und Löschung sämtlicher Derivate aus allen Repliken offen. |
| 22 | Offen | Modelltests ersetzen keine unabhängige sportwissenschaftliche Fallabnahme mit realen Langläufern, Subgruppen und beobachtetem Verlauf. |
| 23 | Teil | Manuelle Scout-Einzelprobe mit Athlet, Zeit, Einheit, Dezimalkomma, Bereichsgrenze, Rohangabe und Korrekturrevision. Vollständige standardisierte Stufentestführung und reale Messgeräteprüfung offen. |
| 24 | Teil | Profile und ihr Export getrennt. Aufeinanderfolgende manuelle und digitale Übernahme derselben Probe und gemeinsames reales Gerät noch prüfen. |
| 25 | Teil | Manuelle Eingabe und Unsicherheiten verfügbar. Tatsächliche Uhr-/Gerätezeit, Stufenende und zeitnahes HF-Fenster mit gemeinsamer Referenzaufzeichnung prüfen. |
| 26 | Teil | Diagnostikmethoden und Qualitätsangaben im Kern, Einzelproben liefern eine dokumentierte Beobachtung. Blinde Qualitätsprüfung mehrerer Protokolle und Schwellenmethoden offen. |
| 27 | Teil | Korrekturhistorie, zonierte Altbestände und Methodenläufe gespeichert. Zonenvorschlag inklusive wirksamer Zustimmung und rückwirkungsfreier Historie als kompletter UI-Ablauf offen. |
| 28 | Teil | Domain-Typen und Vergleichbarkeitsregeln. Fremdmodalität, Technikwechsel und tatsächlich gemessene MLSS als Negativ-/Positivkontrollen fachlich abnehmen. |
| 29 | Direkte Übertragung offen | Manuelle Erfassung und Desktop-JSON-Export verfügbar. Hersteller/Modell, Umgebungslimits, unterstütztes Protokoll, echte Übertragung und sichere Deduplizierung physisch prüfen. |

## Laufzeitziele und weiterführende Abnahme

Für diesen Mac gelten als vorläufige technische Ziele je Lauf mit rund 2,8 GB Quelldaten maximal 120 s für verifizierten Archivimport, 500 ms für Öffnen der migrierten Datenbank und 500 ms für die erste Tagesberechnung eines Profils. Ein Lauf mit 26,071 s / 6 ms / 78 bzw. 5 ms unterschritt diese Grenzen. Datenbanköffnen im Prozess misst keinen vollständigen App-Kaltstart. Für Interaktion gilt als Ziel das 95. Perzentil unter 150 ms vom Tippen bis zur sichtbaren aktualisierten Monats-/Tagesansicht bei 30 Wiederholungen je Plattform und Datensatz. Dieses Perzentil ist noch ungemessen. Mobile Kaltstarts, Speicherverbrauch und Scrollzeiten bei mehrjährigen Serien benötigen repräsentative Geräte.

Für die nächste durchgehende Geräteabnahme sind ein eigenes Garmin-Ereignis je Profil, dokumentiertes Modell/Datum, Einwilligung und eine gekoppelte Apple Watch relevant. Danach lassen sich dauerhafter Widerruf, Kalenderexport, Offline-Rückmeldung und Reconciliation an denselben Fällen prüfen. Die lokale manuelle Trainings- und Diagnostikarbeit kann unabhängig davon weiterlaufen.
