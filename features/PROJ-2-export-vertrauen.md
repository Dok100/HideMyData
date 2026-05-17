# PROJ-2 – Export-Vertrauen

**Status**: Abgeschlossen

## Ziel

Nutzer sollen sicher sein, dass finale Schwärzungen technisch sauber sind und keine sensiblen Inhalte im Export verbleiben.

## Schwerpunkte

- PDF-Export auf Resttext, Selektion und Annotationen prüfen
- Vorschau und finale Schwärzung klar trennen
- Metadaten und Overlay-Verhalten validieren
- klareres Erfolgsfeedback nach Export

## Deliverables

- Export-Checkliste
- Testfälle für finale Redaktionen
- ggf. technischer Validierungsmodus nach Export
- präzisere In-App-Kommunikation nach dem Speichern

## Stand 2026-05-16

- technischer `ExportValidationReport` für PDF- und Bildexporte eingeführt
- Exportpfad meldet jetzt, ob Schwärzungen eingebrannt, Annotationen entfernt und Metadaten bereinigt wurden
- Success-/Status-Kommunikation nach dem Speichern an den Validierungsreport angebunden
- Review-Sidebar zeigt jetzt ein explizites Vertrauensmodul für den letzten Export

## Manueller Testplan

1. natives PDF mit sichtbaren Schwärzungen exportieren
2. prüfen, ob Status-Pill und Sidebar konsistent melden, dass der Export gespeichert und technisch geprüft wurde
3. prüfen, ob der Vertrauensblock nur Aussagen zeigt, die zum Exportmodus passen
4. bildbasiertes Dokument exportieren und dieselben Vertrauenssignale gegenprüfen
5. Exportdatei stichprobenartig erneut laden und prüfen, dass keine editierbaren Overlay-Reste sichtbar bleiben

## Ergebnis

- technischer Export-Report für PDF und Bild ist integriert
- Vertrauenssignale nach dem Speichern sind im UI sichtbar
- Release- und Runbook-Dokumentation wurden nachgezogen
- der nächste sinnvolle Schritt ist kein Pflichtpunkt mehr aus `PROJ-2`, sondern optionaler Produktfeinschliff wie ein explizites Exportprotokoll oder ein tieferer Validierungsdialog

## Relevante Dateien

- `HideMyData/PDFRedactor.swift`
- `HideMyData/ImageRedactor.swift`
- `HideMyData/ExportOptions.swift`
