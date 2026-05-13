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
  PDF-Textgewinnung, OCR-Fallback, Finding-Projektion, Review-Kandidaten und finaler Export.

- `HideMyData/ImageRedactor.swift`
  Bildbasierte Erkennung und Redaktionslogik.

- `HideMyData/Views/Main/MainView.swift`
  Review-Workflow, Sidebar, Export, Diagnose und Clipboard-Anonymisierung.

## Erkennungspipeline

1. nativer PDF-Text oder OCR-Text erfassen
2. Text normalisieren
3. Modell-Treffer erzeugen
4. Regex-Treffer ergaenzen
5. Heuristiken fuer Dokumentrauschen und False Positives anwenden
6. Review-faehige Treffer aufbereiten
7. finale Redaktionen exportieren

## Aktuelle Schwerpunkte

- Detection-Haertung fuer OCR- und Briefkopf-Faelle
- Review-Workflow und Vertrauenssignale
- konsistente Terminologie und Dokumentation
