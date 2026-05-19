# PROJ-8 – Dokumentklassen und Spezialisierung

**Status**: Abgeschlossen

## Ziel

Die App soll typische Dokumentarten intern unterscheiden und dadurch präziser erkennen.

## Schwerpunkte

- Rechnungen
- Steuerbescheide
- Kontakt-/Bankseiten
- Formulare und standardisierte Schreiben

## Deliverables

- einfache interne Dokumentklassifikation
- dokumenttypspezifische Heuristiken und Prioritäten
- bessere Regeln pro Layoutkontext

## Umsetzung

- interner Dokumentklassen-Layer für Rechnungen/Vertragsschreiben, Steuer-/Behördenpost, Kontakt-/Bankseiten und standardisierte Formulare
- dokumenttypspezifische Aktivierung von Feld- und Adressblock-Heuristiken im Text-Detektor
- zusätzliche Formular-Erkennung für gestapelte Feldlabel wie `Vorname`, `Name`, `PLZ` und `Ort`
- Regressionen für Klassifikation und formularartige Texte ergänzt
- DIN-5008-Geschäftsbrief und ZUGFeRD-/E-Rechnungsbeispiel als Referenz-Fixtures aufgenommen
- Feldreferenz einer öffentlichen E-Rechnungs-Vorlage der Bundesagentur für Arbeit als zusätzlicher EN16931-/Leitweg-ID-Referenzfall aufgenommen

## Relevante Dateien

- `HideMyData/PIIDetector.swift`
- `HideMyData/PDFRedactor.swift`
- `HideMyData/patterns.json`
