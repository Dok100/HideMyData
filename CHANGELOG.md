# Unreleased

## Branding und Sprache

* Sichtbares Branding in App, Projekt, Update-Dialog und Sparkle-Assets auf `Inkognito` umgestellt.
* Startansicht sprachlich und visuell geschaerft, inklusive klarerer Kernbotschaft, Trust-Zeile und ueberarbeiteter Karten fuer Dokumente und Zwischenablage.
* Sichtbare UI-Texte, Statusmeldungen und Exportoptionen ins Deutsche uebersetzt.

## Erkennung und OCR

* OCR-Fallback fuer PDFs mit defektem oder stark zerfallenem Textlayer ergaenzt.
* Native PDF-Textschichten und OCR-Texte werden jetzt unterschiedlich normalisiert, damit saubere PDFs nicht unnoetig verformt werden.
* Erkennung fuer deutsche Namen, Strassen, Hausnummern und `PLZ + Ort`-Kombinationen erweitert, auch bei OCR-Fragmentierung und Zeilenumbruechen.
* Nachgelagerte Filter gegen Dokumentrauschen, Briefkopf-Orte und false positives verschaerft, insbesondere fuer Steuer- und Behördendokumente.
* Modell- und Regex-Treffer werden robuster zusammengefuehrt, damit Empfaenger- und Adressbloecke natuerlicher im Review erscheinen.
* Zu aggressive modellseitige Kontonummern-Treffer werden staerker unterdrueckt, waehrend plausible strukturierte Identifier erhalten bleiben.
* OCR-Diagnostikansicht fuer gelesenen und normalisierten Text hinzugefuegt.
* Kleiner lokaler Regression-Check fuer die juengsten OCR-, Briefkopf- und Adress-Fixes hinzugefuegt.

## Regeln und Review

* Eigene Erkennungsregeln um komfortable Verwaltung, Import und Export per JSON erweitert.
* Import-Verhalten fuer Regeln um die Modi `Ergaenzen` und `Ersetzen` erweitert.
* Funktionen zum Modernisieren bestehender Regeln und zum Entfernen von Duplikaten hinzugefuegt.
* Unterstuetzung fuer mehrzeilige Adressbloecke und robustere Zerlegung in Teil- und Blockregeln ergaenzt.
* Datumserkennung fuer OCR-Faelle robuster gemacht, z. B. bei `01.10.1938` mit zusaetzlichen Zeichen oder abweichender Zeichenerkennung.
* Review-Inspector ueberarbeitet: Treffer werden verdichtet, ruhiger dargestellt und staerker als Pruef-Workflow aufbereitet.
* Automatisch erkannte Treffer werden vor der Bestaetigung zunaechst nur markiert und erst danach final geschwaerzt oder unscharf exportiert.

## Zwischenablage und UI

* Globalen Zwischenablage-Workflow ergaenzt: kopierten Text lokal anonymisieren, Vorschau pruefen und direkt in KI-Tools uebernehmen.
* Rueckfuehrung fuer KI-Antworten ergaenzt: Platzhalter koennen wieder mit Originalwerten ersetzt werden.
* Platzhalter-Erkennung bei der Rueckfuehrung robuster gemacht, auch bei leicht veraenderten Tokens wie `NAME 1` oder `[name-1]`.
* Hauptarbeitsflaeche und Toolbar visuell beruhigt und staerker an eine sachliche macOS-Utility-App angenaehert.
* Option ergaenzt, um `Zuletzt verwendet` und lokale Vorschaubilder fuer sensible Dokumente zu deaktivieren.

## Modell und Sicherheit

* Modelldownload auf eine feste Hugging-Face-Revision gepinnt, statt `main` zu folgen.
* Validierung von Manifest-Pfaden ergaenzt, um unsichere Pfad-Traversal beim Download zu verhindern.
* Laden des Modells auf einen revisionsgebundenen lokalen Cache-Pfad umgestellt.
* README um einen Hinweis auf das gepinnte Modellverhalten und die neuen Regression-Checks ergaenzt.
* Bestehende Installationen muessen das Modell moeglicherweise einmal neu herunterladen, da der Cache jetzt revisionsgebunden ist.

# 0.2.0

## Inkognito is now notarized!

* Integrate Sparkle for automatic updates. 
* `Check for Updates…` menu item in the app menu.
* Switched to xcodegen.
* Allow removing metadata from files when saving.

### ⚠️ Manual cleanup for users on v0.1.0

Because of the notarization and because I changed the app bundle ID, a one-timemanual reinstall is needed.

* If you use Raycast or AppCleaner - you're good, just uninstall there.

Manually:

* Drag the app to trash
* The old sandbox container at `~/Library/Containers/com.maciejonos.HideMyData/` is left behind. To reclaim the disk space:

```bash
rm -rf ~/Library/Containers/com.maciejonos.HideMyData
```

No further bundle ID changes are planned — future versions update in place via Sparkle.

# 0.1.0

* Initial release.
