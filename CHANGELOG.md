# 0.3.0

## Produkt und Sprache

* Sichtbares Branding in App, Projekt, Update-Dialog und Sparkle-Assets auf `Inkognito` umgestellt.
* Startansicht, Leerzustaende und Hauptnavigation sprachlich und visuell geschaerft.
* Sichtbare UI-Texte, Statusmeldungen, Export-Hinweise und Einstellungen konsistent ins Deutsche ueberfuehrt.
* Diagnoseansicht, Review und `Eigene Regeln` sprechen produktnaeher und zeigen weniger interne Begriffe.

## Erkennung und Dokumentklassen

* OCR-Fallback fuer PDFs mit defektem oder stark zerfallenem Textlayer ergaenzt.
* Native PDF-Textschichten und OCR-Texte werden unterschiedlich normalisiert, damit saubere PDFs nicht unnoetig verformt werden.
* Erkennung fuer deutsche Namen, Strassen, Hausnummern und `PLZ + Ort`-Kombinationen erweitert, auch bei OCR-Fragmentierung und Zeilenumbruechen.
* Dokumentklassen fuer Rechnungen, Vertraege, Formulare, Bankseiten, DIN-5008-Geschaeftsbriefe und E-Rechnungen verstaerkt.
* Marker wie `ZUGFeRD`, `XRechnung`, `Leitweg-ID`, `Lieferanten-Nr.` und `Fälliger Rechnungsbetrag` in der Erkennung beruecksichtigt.
* Nachgelagerte Filter gegen Dokumentrauschen, Briefkopf-Orte, false positives und AGB-/Rechtstext-Fehlmarkierungen verschaerft.
* Modell- und Regex-Treffer werden robuster zusammengefuehrt, damit Empfaenger- und Adressbloecke natuerlicher im Review erscheinen.
* Zu aggressive modellseitige Kontonummern-Treffer werden staerker unterdrueckt, waehrend plausible strukturierte Identifier erhalten bleiben.
* Detection-Regressionen mit neuen Fixtures fuer DIN-5008, ZUGFeRD und E-Rechnungs-Feldreferenzen erweitert.

## Review und Export

* Review-Inspector grundlegend ueberarbeitet: Treffer werden verdichtet, ruhiger dargestellt und staerker als Pruef-Workflow aufbereitet.
* Automatisch erkannte Treffer werden vor der Bestaetigung zunaechst nur markiert und erst danach final geschwaerzt oder unscharf exportiert.
* Seitenstatus fuer `offen`, `geprueft`, `besonders pruefen`, `wenig lesbarer Text` und `keine Treffer` in die Review-Sidebar integriert.
* Unsichere Treffer werden direkt an den betroffenen Review-Karten markiert, statt nur in separaten Metabloecken zu erscheinen.
* Aehnliche offene Treffer lassen sich gesammelt bestaetigen oder ablehnen.
* Vor dem Export gibt es eine kompakte menschliche Zusammenfassung; nach dem Export einen verstaendlicheren Vertrauensbericht.
* PDF- und Bildexport melden zusaetzlich manuelle Schwaerzungen und bereits erkannte Textqualitaetsrisiken.

## Regeln, Diagnose und Zwischenablage

* Eigene Erkennungsregeln um Verwaltung, Import und Export per JSON erweitert.
* Import-Verhalten fuer Regeln um die Modi `Ergaenzen` und `Ersetzen` erweitert.
* Funktionen zum Modernisieren bestehender Regeln und zum Entfernen von Duplikaten hinzugefuegt.
* Unterstuetzung fuer mehrzeilige Adressbloecke, Namensvarianten und robustere Zerlegung in Teil- und Blockregeln ergaenzt.
* Regeln-Editor um Vorlagen, Regelqualitaets-Hinweise und Dokumentvorschau fuer moegliche Treffer erweitert.
* Diagnoseansicht produktreifer gemacht, inklusive Developer-Umschalter und funktionierendem JSON-Export.
* Globalen Zwischenablage-Workflow ergaenzt: kopierten Text lokal anonymisieren, in KI-Tools nutzen und Antworten lokal rueckfuehren.
* Clipboard-Flow in drei Schritte gegliedert, damit der Ablauf fuer Erstnutzer uebersichtlicher bleibt.
* Platzhalter-Erkennung bei der Rueckfuehrung robuster gemacht, auch bei leicht veraenderten Tokens wie `NAME 1` oder `[name-1]`.

## Modell, Sicherheit und Build

* Modelldownload auf eine feste Hugging-Face-Revision gepinnt, statt `main` zu folgen.
* Validierung von Manifest-Pfaden ergaenzt, um unsichere Pfad-Traversal beim Download zu verhindern.
* Laden des Modells auf einen revisionsgebundenen lokalen Cache-Pfad umgestellt.
* Aktive Legacy-Migrationspfade fuer Cache, Recents, Clipboard-Session und Bestandsdateien bewusst erhalten, obwohl der laufende App-Pfad bereits `Inkognito` spricht.
* Build-Warnungen fuer die ab macOS 26 veraltete `Text + Text`-Komposition entfernt.

# 0.2.0

## Inkognito is now notarized!

* Integrate Sparkle for automatic updates. 
* `Check for Updates…` menu item in the app menu.
* Switched to xcodegen.
* Allow removing metadata from files when saving.

### ⚠️ Manual cleanup for users on v0.1.0

Because of notarization and early distribution changes, some users moving from `v0.1.0` may have needed a one-time reinstall.

* If you use Raycast or AppCleaner, uninstalling there was usually sufficient.

Manually:

* Drag the app to trash
* Older prerelease data containers may remain on disk and can be removed if no longer needed.

Future versions are intended to update in place via Sparkle.

# 0.1.0

* Initial release.
