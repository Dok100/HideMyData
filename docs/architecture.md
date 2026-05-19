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
  Review-Workflow, Sidebar, Export, Diagnose, Clipboard-Anonymisierung, Regel-Assistenz, Seitenstatus, Export-Zusammenfassung, Vertrauensfeedback nach dem Speichern und ruhige Fehlerfuehrung fuer Oeffnen-, Retry-, Export- und Clipboard-Probleme.

## Erkennungspipeline

1. nativer PDF-Text oder OCR-Text erfassen
2. Text normalisieren
3. Modell-Treffer erzeugen
4. Regex-Treffer ergaenzen
5. Dokumentklasse heuristisch einschaetzen
6. Heuristiken fuer Dokumentrauschen, Briefkopf-Kontext, AGB-/Rechtstext und False Positives anwenden
7. Review-faehige Treffer aufbereiten
8. finale Redaktionen exportieren
9. Export technisch validieren und Vertrauenssignale im UI anzeigen

## Aktuelle Schwerpunkte

- abgeschlossene Detection-Haertung fuer native PDFs, OCR/Bilder und Clipboard-Text
- dokumentklassensensitive Erkennung fuer Rechnungen, Formulare, Bankseiten, DIN-5008-Briefe und E-Rechnungen
- abgeschlossener Review-Workflow mit direkter Ruecknahme, Fokus-Sprung aus der Dokumentflaeche, Seitenstatus und Sammelaktionen fuer aehnliche Treffer
- Export-Vertrauen durch technische Validierung und eine zusaetzliche menschliche Export-Zusammenfassung
- Fehlerfuehrung und Resilienz fuer Oeffnen, OCR-Schwachfaelle, Export und Clipboard-Status
- abgeschlossene Vereinheitlichung des Farbsystems zwischen Legende, Sidebar, Dokument-Highlights und Review-Karten
- abgeschlossene Start- und Leerzustaende mit gleichwertigem Einstieg fuer Dokumente und Zwischenablage
- abgeschlossene Produktkommunikation fuer Einstieg, Export, Review, `Eigene Regeln` und `Technische Ansicht`
- Regel-Assistenz mit Vorlagen, Qualitaets-Hinweisen und Dokumentvorschau im Editor
- konsistente Terminologie und nachgezogene Produktdokumentation bis `PROJ-20`
