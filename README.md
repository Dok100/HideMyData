<div align="center">

<img width="180" height="180" alt="Inkognito" src="HideMyData/Assets.xcassets/AppLogo.imageset/logo.png" />

### Inkognito

**Anonymisieren. Direkt auf deinem Mac.**

Lokale KI-gestuetzte Schwaerzung sensibler Inhalte fuer macOS. Inkognito kombiniert OpenMed, Apple Vision OCR und manuelle Review-Schritte, damit vertrauliche PDFs, Bilder und Zwischenablage-Texte den Mac nicht verlassen muessen.

![Swift](https://img.shields.io/badge/Swift-FA7343?style=for-the-badge&logo=swift&logoColor=white)
![Xcode](https://img.shields.io/badge/Xcode-007ACC?style=for-the-badge&logo=Xcode&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white)

</div>

## Ueberblick

Inkognito ist eine native macOS-App fuer das lokale Anonymisieren von:

- PDFs
- Bildern
- kopierten Texten aus der Zwischenablage

Die App erkennt personenbezogene und sensible Inhalte, markiert sie zuerst nur zur Pruefung und erzeugt erst nach deiner Freigabe die finalen Schwaerzungen. Fuer OCR-lastige Dokumente gibt es einen Fallback ueber Apple Vision. Fuer problematische PDF-Textlayer kombiniert Inkognito eingebetteten Text, OCR, Regexe und nachgelagerte Heuristiken.

## Kernfunktionen

- **Alles lokal**: Modell, OCR, Erkennung und Nachbearbeitung laufen auf deinem Mac.
- **PDF- und Bild-Workflow**: beide Formate teilen sich dieselbe Review-Logik.
- **OCR-Fallback**: gescannte Dokumente und kaputte PDF-Textlayer werden ueber Apple Vision abgefangen.
- **KI-Erkennung**: OpenMed `privacy-filter` auf MLX erkennt Namen, Adressen, Telefonnummern, Daten und weitere PII im Kontext.
- **Regex-Ergaenzungen**: zusaetzliche Muster fuer IBANs, Karten, Wallets, typische Identifier und sprachspezifische Adressformen.
- **Review vor Finalisierung**: automatische Treffer werden erst bestaetigt oder verworfen, bevor sie dauerhaft geschwaerzt werden.
- **Manuelle Bearbeitung**: Redaktionsrechtecke koennen jederzeit hinzugefuegt oder entfernt werden.
- **Zwischenablage-Anonymisierung**: sensible Inhalte lokal durch Platzhalter ersetzen, sicher in KI-Tools einfuegen und Antworten spaeter lokal rueckfuehren.
- **Persistente Schwaerzung beim Export**: finale PDFs werden aus gerenderten Seiten neu aufgebaut.

## Typische Workflows

### Dokumente anonymisieren

1. PDF oder Bild oeffnen oder per Drag-and-drop auf die Startseite legen.
2. Automatische Treffer pruefen.
3. Treffer bestaetigen oder ablehnen.
4. Bei Bedarf manuelle Schwaerzungen ergaenzen.
5. Finale Datei exportieren.

### Zwischenablage anonymisieren

1. Text in die Zwischenablage kopieren.
2. Vorschau ueber die App oder den globalen Shortcut `Cmd+Shift+A` oeffnen.
3. Anonymisierte Version pruefen und in ChatGPT, Claude, Gemini oder ein anderes Tool einfuegen.
4. KI-Antwort wieder in Inkognito holen.
5. Originalwerte lokal aus den Platzhaltern wiederherstellen.

Die Platzhalter-Zuordnung bleibt lokal auf dem Geraet.

## Erkennungspipeline

Inkognito nutzt mehrere Ebenen, damit schwierige Dokumente trotzdem brauchbare Treffer liefern:

1. **Nativer PDF-Text**, wenn die Textschicht sauber genug ist.
2. **OCR ueber Apple Vision**, wenn die Seite gescannt ist oder der eingebettete Textlayer zerfaellt.
3. **Normalisierung**, um OCR-Artefakte wie auseinandergezogene Buchstaben oder zerhackte Ziffernfolgen zu glätten.
4. **OpenMed-Modell**, um kontextbezogene PII zu finden.
5. **Regex-Matching**, um strukturierte Muster zu ergaenzen.
6. **Post-Processing**, um Dokumentrauschen, Briefkopf-Orte, false positives und OCR-Muell wieder zu entfernen.
7. **Review-Compaction**, um einzelne Treffer in lesbare Bloecke zusammenzufassen.

Diese letzte Stufe ist gerade fuer deutsche Steuerbescheide, Briefkoepfe und OCR-lastige PDFs wichtig.

## Sicherheitsnotizen

- Der staerkste Exportmodus fuer vertrauliche Dokumente ist **`Schwarz`**.
- In diesem Modus wird die finale PDF aus gerenderten Seiten neu aufgebaut, statt nur mit entfernbaren Balken ueberdeckt zu werden.
- **`Unschaerfe`** ist visuell nuetzlich, aber schwaecher als eine vollstaendige schwarze Schwaerzung.
- Zwischenstaende sollten nicht weitergegeben werden. Relevant ist nur der finale Export.

## Voraussetzungen

- macOS 26 oder neuer
- Apple Silicon
- Xcode 16 oder neuer empfohlen

## Installation

Die einfachste Nutzung erfolgt ueber die aktuelle `.dmg` aus den GitHub Releases.

- Releases: [Releases](../../releases)

Alternativ kann die App lokal aus dem Repository gebaut werden.

## Build

```bash
open Inkognito.xcodeproj
```

Dann in Xcode:

1. Scheme `Inkognito` auswaehlen
2. `Cmd+R` zum Starten

Beim ersten Start laedt Inkognito das Modell nach:

```text
~/Library/Application Support/Inkognito/ModelCache/
```

Die App pinnt das Modell auf eine feste Hugging-Face-Revision, statt `main` zu verfolgen.

## Regressions-Checks

Fuer die juengsten OCR-/Briefkopf-/Adress-Fixes gibt es einen kleinen lokalen Regression-Check:

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/swift-module-cache swift scripts/run_detection_regressions.swift
```

Der Check verifiziert aktuell unter anderem:

- Briefkopf-Orte wie `74076 Heilbronn` und `74064 Heilbronn` werden unterdrueckt
- echte Empfaenger-Orte wie `74229 Oodheim` bleiben erhalten
- kurze modellseitige Kontonummern werden verworfen
- OCR- und Native-Normalisierung regressieren nicht wieder in den frueheren Fehlerzustand

Die zugehoerige Fixture liegt hier:

- [fixtures/detection/steuerbescheid_page1_ocr.txt](fixtures/detection/steuerbescheid_page1_ocr.txt)

## Projektstruktur

Wichtige Dateien und Bereiche:

- [HideMyData/HideMyDataApp.swift](HideMyData/HideMyDataApp.swift): App-Einstieg, globaler Shortcut, Einstellungen
- [HideMyData/PDFRedactor.swift](HideMyData/PDFRedactor.swift): PDF-Erkennung, OCR-Fallback, Review-Kandidaten, Export
- [HideMyData/ImageRedactor.swift](HideMyData/ImageRedactor.swift): Bilderkennung und Redaktionslogik
- [HideMyData/PIIDetector.swift](HideMyData/PIIDetector.swift): Modellintegration, Regex-Postprocessing, Filter-Heuristiken
- [HideMyData/OCRNormalizer.swift](HideMyData/OCRNormalizer.swift): OCR- und Native-Textnormalisierung
- [HideMyData/patterns.json](HideMyData/patterns.json): eingebaute Regex-Muster
- [HideMyData/Views/Main/MainView.swift](HideMyData/Views/Main/MainView.swift): Hauptworkflow fuer Review, Export und Zwischenablage
- [scripts/run_detection_regressions.swift](scripts/run_detection_regressions.swift): schlanker Regression-Check

## Projekt-Dokumentation

Fuer das generelle Projekt-Framing gibt es zusaetzlich:

- [features/INDEX.md](features/INDEX.md): Feature-Backlog als einzelne Projektbausteine
- [docs/architecture.md](docs/architecture.md): technische und fachliche Struktur
- [docs/decision-log.md](docs/decision-log.md): wichtige Richtungsentscheidungen
- [docs/release-checklist.md](docs/release-checklist.md): Release-Vorbereitung
- [docs/runbook.md](docs/runbook.md): operative Wartungs- und Debug-Abläufe

## Aktueller Stand

Inkognito ist funktional nutzbar, aber weiter in aktiver Qualitaetsarbeit.

Besonders in letzter Zeit geschaerft wurden:

- OCR-Fallback fuer defekte PDF-Textlayer
- deutsche Adress- und Namensmuster
- Briefkopf-Unterdrueckung bei Steuer- und Behördendokumenten
- Filter gegen Dokumentrauschen und false positives

Weitere Verbesserungen werden weiterhin an echten Problembeispielen iterativ abgesichert.

## Tech Stack

- Swift 6
- SwiftUI
- PDFKit
- Apple Vision
- OpenMedKit
- MLX-Swift

## Lizenz

GPL-3.0
