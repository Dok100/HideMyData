# Architektur

## Ziel

Inkognito ist eine native macOS-App fuer lokale Anonymisierung von PDFs, Bildern und Zwischenablage-Texten. Der Kernanspruch ist: sensible Inhalte erkennen, pruefen lassen und erst danach final schwaerzen, ohne dass Daten den Mac verlassen muessen.

## Hauptbausteine

- `HideMyData/HideMyDataApp.swift`
  App-Einstieg, globale App-Einstellungen und Shortcuts.

- `HideMyData/ContentView.swift`
  Top-Level-Zustandssteuerung zwischen Erststart, Download, Hauptworkflow und Fehlerfaellen.

- `HideMyData/PIIDetector.swift`
  Modellintegration, Regex-Matching, Span-Nachbearbeitung und Textwiederherstellung fuer den Clipboard-Flow.

- `HideMyData/PDFRedactor.swift`
  PDF-Textgewinnung, OCR-Fallback, Finding-Projektion, Review-Kandidaten, finale Exporte, technischer Export-Validierungsreport und Produktzustände fuer schwache oder unbrauchbare PDF-/OCR-Ergebnisse.

- `HideMyData/ImageRedactor.swift`
  Bildbasierte Erkennung, Redaktionslogik, Schwachsignal-Erkennung fuer OCR und technischer Export-Validierungsreport.

- `HideMyData/Views/Main/MainView.swift`
  Review-Workflow, Sidebar, Export, Diagnose, Clipboard-Anonymisierung, Vertrauensfeedback nach dem Speichern und ruhige Fehlerfuehrung fuer Oeffnen-, Retry-, Export- und Clipboard-Probleme.

## Erkennungspipeline

1. nativer PDF-Text oder OCR-Text erfassen
2. Text normalisieren
3. Modell-Treffer erzeugen
4. Regex-Treffer ergaenzen
5. Heuristiken fuer Dokumentrauschen und False Positives anwenden
6. Review-faehige Treffer aufbereiten
7. finale Redaktionen exportieren
8. Export technisch validieren und Vertrauenssignale im UI anzeigen

## Aktuelle Schwerpunkte

- abgeschlossene Detection-Haertung fuer native PDFs, OCR/Bilder und Clipboard-Text
- abgeschlossener Review-Workflow mit direkter Ruecknahme, Fokus-Sprung aus der Dokumentflaeche und exportorientiertem Abschlussmoment
- Export-Vertrauen durch technische Validierung nach dem Speichern
- Fehlerfuehrung und Resilienz fuer Oeffnen, OCR-Schwachfaelle und Clipboard-Status
- abgeschlossene Vereinheitlichung des Farbsystems zwischen Legende, Sidebar, Dokument-Highlights und Review-Karten
- zentrale visuelle Semantik fuer Kategorien, Statusflächen und neutrale Oberflächen
- konsistente Terminologie und Dokumentation
