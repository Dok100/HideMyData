<div align="center">

<img width="180" height="180" alt="Inkognito" src="Inkognito/Assets.xcassets/AppLogo.imageset/logo.png" />

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

Die App erkennt personenbezogene und sensible Inhalte, markiert sie zuerst nur zur Pruefung und erzeugt erst nach deiner Entscheidung die finalen Schwaerzungen. Fuer OCR-lastige Dokumente gibt es einen Fallback ueber Apple Vision. Fuer problematische PDF-Textlayer kombiniert Inkognito eingebetteten Text, OCR, Regexe, Dokumentklassen-Heuristiken und nachgelagerte Filter.

## Kernfunktionen

- **Alles lokal**: Modell, OCR, Erkennung und Nachbearbeitung laufen auf deinem Mac.
- **PDF- und Bild-Workflow**: beide Formate teilen sich dieselbe Review-Logik.
- **OCR-Fallback**: gescannte Dokumente und kaputte PDF-Textlayer werden ueber Apple Vision abgefangen.
- **KI-Erkennung**: OpenMed `privacy-filter` auf MLX erkennt Namen, Adressen, Telefonnummern, Daten und weitere PII im Kontext.
- **Regex-Ergaenzungen**: zusaetzliche Muster fuer IBANs, Karten, Wallets, typische Identifier und sprachspezifische Adressformen.
- **Dokumentklassen-Heuristiken**: Rechnungen, Briefe, Formulare, Bankseiten, DIN-5008-Geschaeftsbriefe und E-Rechnungen werden gezielter nachkontextualisiert.
- **Review vor Finalisierung**: automatische Treffer werden erst bestaetigt oder verworfen, bevor sie dauerhaft geschwaerzt werden.
- **Seitenstatus und Unsicherheiten**: Review zeigt offene, gepruefte oder besonders pruefenswerte Seiten und markiert unsichere Treffer direkt an der Stelle der Entscheidung.
- **Schnellere Nacharbeit**: aehnliche offene Treffer lassen sich gesammelt bestaetigen oder ablehnen.
- **Manuelle Bearbeitung**: Redaktionsrechtecke koennen jederzeit hinzugefuegt oder entfernt werden.
- **Zwischenablage-Anonymisierung**: sensible Inhalte lokal durch Platzhalter ersetzen, sicher in KI-Tools einfuegen und Antworten spaeter lokal rueckfuehren.
- **Gefuehrter Clipboard-Flow**: Anonymisieren, mit KI arbeiten und Rueckfuehren sind als dreistufiger Ablauf aufgebaut.
- **Regel-Assistenz**: eigene Regeln geben vor dem Speichern Rueckmeldung zu Regelqualitaet und moeglichen Treffern im aktuellen Dokument.
- **Export-Zusammenfassung**: vor und nach dem Speichern erklaert Inkognito menschlich, was geschuetzt wurde und wo Sichtpruefung sinnvoll bleibt.
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
- echte Empfaenger-Orte wie `74229 Oedheim` bleiben erhalten
- kurze modellseitige Kontonummern werden verworfen
- OCR- und Native-Normalisierung regressieren nicht wieder in den frueheren Fehlerzustand
- DIN-5008-Briefvorlagen ziehen keine falschen Empfaenger aus Layout- oder Absenderkontext
- ZUGFeRD-, XRechnung- und Leitweg-ID-Marker staerken E-Rechnungs-Kontext statt generischer Brief-Erkennung
- AGB- und Rechtstext-Ueberschriften wie `GELTUNGSBEREICH` oder `SCHLUSSBESTIMMUNGEN` werden nicht als PII fehlmarkiert

Beispielhafte Fixtures liegen hier:

- [fixtures/detection/steuerbescheid_page1_ocr.txt](fixtures/detection/steuerbescheid_page1_ocr.txt)
- [fixtures/detection/din5008_geschaeftsbrief_form_b_pdf_text.txt](fixtures/detection/din5008_geschaeftsbrief_form_b_pdf_text.txt)
- [fixtures/detection/zugferd_erechnung_pdf_text.txt](fixtures/detection/zugferd_erechnung_pdf_text.txt)
- [fixtures/detection/muster_e_rechnung_ba_field_reference.txt](fixtures/detection/muster_e_rechnung_ba_field_reference.txt)

## Projektstruktur

Wichtige Dateien und Bereiche:

- [Inkognito/InkognitoApp.swift](Inkognito/InkognitoApp.swift): App-Einstieg, globaler Shortcut, Einstellungen
- [Inkognito/PDFRedactor.swift](Inkognito/PDFRedactor.swift): PDF-Erkennung, OCR-Fallback, Review-Kandidaten, Export
- [Inkognito/ImageRedactor.swift](Inkognito/ImageRedactor.swift): Bilderkennung und Redaktionslogik
- [Inkognito/PIIDetector.swift](Inkognito/PIIDetector.swift): Modellintegration, Regex-Postprocessing, Filter-Heuristiken
- [Inkognito/OCRNormalizer.swift](Inkognito/OCRNormalizer.swift): OCR- und Native-Textnormalisierung
- [Inkognito/patterns.json](Inkognito/patterns.json): eingebaute Regex-Muster
- [Inkognito/Views/Main/MainView.swift](Inkognito/Views/Main/MainView.swift): Hauptworkflow fuer Review, Export und Zwischenablage
- [scripts/run_detection_regressions.swift](scripts/run_detection_regressions.swift): schlanker Regression-Check

## Projekt-Dokumentation

Fuer das generelle Projekt-Framing gibt es zusaetzlich:

- [features/INDEX.md](features/INDEX.md): Feature-Backlog als einzelne Projektbausteine
- [docs/architecture.md](docs/architecture.md): technische und fachliche Struktur
- [docs/commercial-readiness-audit.md](docs/commercial-readiness-audit.md): offener Re-Licensing- und Commercial-Readiness-Status
- [docs/decision-log.md](docs/decision-log.md): wichtige Richtungsentscheidungen
- [docs/release-checklist.md](docs/release-checklist.md): Release-Vorbereitung
- [docs/runbook.md](docs/runbook.md): operative Wartungs- und Debug-Abläufe

## Aktueller Stand

Die erste grosse Produktstufe ist abgeschlossen: `PROJ-1` bis `PROJ-20` sind umgesetzt und in `features/` dokumentiert.

`PROJ-21` bereitet das Projekt zusaetzlich auf spaetere Monetarisierung und moegliche Store-Distribution vor. Der Schwerpunkt liegt dort auf Relicensing-Readiness, sichtbarem Herkunfts-Cleanup und dem gezielten Ersetzen aelterer Altbloecke.

Der aktuelle Schwerpunkt liegt jetzt weniger auf fehlenden Grundfunktionen als auf:

- weiterer Detection-Haertung an echten Problembeispielen
- Produktfeinschliff in Review, Export und Regeln
- Release-Vorbereitung fuer breitere Nutzung

Die naechsten Schritte werden weiterhin ueber echte Dokumentfaelle, Regressionen und kleine produktnahe Iterationen abgesichert.

## Tech Stack

- Swift 6
- SwiftUI
- PDFKit
- Apple Vision
- OpenMedKit
- MLX-Swift

## Lizenz

Der aktuelle Repository-Stand wird weiterhin unter der in [LICENSE](LICENSE) enthaltenen Lizenz verteilt.

Eine spaetere Umstellung auf ein kommerzielles oder proprietaeres Modell setzt zuerst eine saubere Rechteklaerung, die Bewertung der verbleibenden Fachkern-Dateien und den Abschluss von `PROJ-21` voraus.

Der aktuelle Commercial-Readiness-Stand wird in [docs/commercial-readiness-audit.md](docs/commercial-readiness-audit.md) separat nachgehalten.
