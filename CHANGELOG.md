# Unreleased

* Modelldownload auf eine feste Hugging-Face-Revision gepinnt, statt `main` zu folgen.
* Validierung von Manifest-Pfaden ergänzt, um unsichere Pfad-Traversal beim Download zu verhindern.
* Laden des Modells auf einen revisionsgebundenen lokalen Cache-Pfad umgestellt.
* Sichtbare UI-Texte, Statusmeldungen und Exportoptionen ins Deutsche übersetzt.
* Option ergänzt, um „Zuletzt verwendet“ und lokale Vorschaubilder für sensible Dokumente zu deaktivieren.
* README um einen Hinweis auf das gepinnte Modellverhalten ergänzt.
* Bestehende Installationen müssen das Modell möglicherweise einmal neu herunterladen, da der Cache jetzt revisionsgebunden ist.
* Eigene Erkennungsregeln um komfortable Verwaltung, Import und Export per JSON erweitert.
* Import-Verhalten für Regeln um die Modi `Ergänzen` und `Ersetzen` ergänzt.
* Funktionen zum Modernisieren bestehender Regeln und zum Entfernen von Duplikaten hinzugefügt.
* Regelverwaltung optisch überarbeitet und stärker an den macOS-/Apple-Stil angepasst.
* Layout der Regelverwaltung für vergrößerte Fenster verbessert.
* Unterstützung für mehrzeilige Adressblöcke und robustere Zerlegung in Teil- und Blockregeln ergänzt.
* Erkennung für deutsche `PLZ + Ort`-Kombinationen verbessert, auch bei Zeilenumbrüchen.
* Datumserkennung für OCR-Fälle robuster gemacht, z. B. bei `01.10.1938` mit zusätzlichen Zeichen oder abweichender Zeichenerkennung.
* Globalen Zwischenablage-Workflow ergänzt: kopierten Text lokal anonymisieren, Vorschau prüfen und direkt in die KI übernehmen.
* Rückführung für KI-Antworten ergänzt: Platzhalter können wieder mit Originalwerten ersetzt werden.
* Platzhalter-Erkennung bei der Rückführung robuster gemacht, auch bei leicht veränderten Tokens wie `NAME 1` oder `[name-1]`.
* Review-Inspector überarbeitet: Treffer werden verdichtet, ruhiger dargestellt und stärker als Prüf-Workflow aufbereitet.
* Automatisch erkannte Treffer werden vor der Bestätigung zunächst nur markiert und erst danach final geschwärzt oder unscharf exportiert.
* Hauptarbeitsfläche und Toolbar visuell beruhigt und stärker an eine sachliche macOS-Utility-App angenähert.
* Bekannter Punkt: Die Erkennungsqualität einzelner OCR-/Adress-/Kontofälle wird im nächsten Schritt gezielt nachstabilisiert.

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
