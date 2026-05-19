# PROJ-7 – Produktkommunikation

**Status**: Abgeschlossen

## Ziel

Der Privacy-Vorteil und die lokale Verarbeitung sollen im Produkt selbst noch klarer spürbar werden.

## Schwerpunkte

- In-App-Erklärungen zu lokalem Processing
- klarere Trennung zwischen Vorschau und finaler Schwärzung
- abgestimmte Hilfetexte, About-Texte und Trust-Hinweise
- Konsistenz zwischen README, Releases und In-App-Sprache

## Deliverables

- überarbeitete UI-Texte für Trust-Momente
- ggf. About-/Help-Bereich
- abgestimmte Produktbotschaften

## Umgesetzt im ersten Block

- Start- und Trust-Texte rund um Dokument-Start und Zwischenablage sprachlich geglättet
- Intro und Modell-Download kommunizieren den lokalen Privacy-Vorteil ruhiger und klarer
- zentrale Einstiege und Werkzeuge sprechen stärker in Nutzersprache statt in internen Technikbegriffen

## Umgesetzt im zweiten Block

- Export-Vertrauen klingt stärker nach Schutzwirkung und weniger nach interner Technik
- Diagnose-Ansicht und Toolbar benennen Hilfs- und Technikflächen verständlicher
- Eigene Regeln sprechen mehr aus Nutzersicht und weniger aus interner Erkennungslogik

## Umgesetzt im dritten Block

- Toolbar, Review-Sidebar und Workflow-Schritte sprechen stärker in Schutz- und Freigabe-Logik statt in Listen- und Technikbegriffen
- Export-Aktionen klingen konsistenter nach geschütztem Ergebnis statt nach generischem Speichern
- Review-Texte beschreiben offene Stellen, Freigabe und Export klarer als zusammenhängenden Nutzerfluss

## Umgesetzt im vierten Block

- Der Bereich `Eigene Regeln` wurde von einem unklaren Freitextblock auf einen zeilenbasierten Eingabe-Editor umgestellt
- Die Oberfläche erklärt jetzt sichtbar, wie Inkognito aus Eingaben Original-, Teil- und Blockregeln ableitet und dass keine automatische Umstellung wie `Mustermann Max` erfolgt
- Kategorie-Snake-Case wurde in der Eingabe durch nutzernahe Einordnungen ersetzt
- Die technische Ansicht ist wieder direkt über die Toolbar erreichbar
- Der Speicherdialog wurde zusätzlich auf deutsche Projekt- und Panel-Beschriftungen vorbereitet

## Umgesetzt im fünften Block

- Eigene Regeln zeigen jetzt wieder die Nutzerlogik statt flachen Maschinen-Output: pro angelegter Regel gibt es eine aufklappbare Gruppe mit Ableitungen
- Bearbeiten und Löschen greifen auf Gruppenebene, damit eine Nutzerregel mitsamt Teil- und Blockregeln konsistent geändert oder entfernt wird
- Die Bewertungslogik liegt nicht mehr als große Dauerbox im Formular, sondern hinter einem gezielten Info-Zugang
- Die automatische Einordnung spricht ehrlicher: neutrale Fälle bleiben sichtbar neutral, statt eine starke Automatik nur zu behaupten

## Umgesetzt im sechsten Block

- Der Bereich `Eigene Regeln` wurde weiter auf Nutzersicht statt Maschinen-Output ausgerichtet
- Wartungsaktionen sprechen jetzt ruhiger und verständlicher (`Regeln ergänzen`, `Unklare Regeln entfernen`, `Doppelte Regeln löschen`)
- Rückmeldungen zu diesen Aktionen erscheinen direkt im Bereich `Deine Regeln`, also dort, wo sie ausgelöst wurden
- Variantenhinweise und Entscheidungshilfen für eigene Regeln wurden präziser formuliert
- Die Klickflächen für Aufklappen und Auswählen der Regelgruppen wurden deutlich vergrößert

## Umgesetzt im siebten Block

- Die `Technische Ansicht` spricht produktnäher und weniger debug-lastig
- Abschnittstitel wie `Erkannte Stellen`, `Eigene Regeln im Kontext` und `Aufbereiteter Text` erklären klarer, was zu sehen ist
- Kleine Info-Buttons erläutern pro Abschnitt den Zweck und die Herkunft der angezeigten Informationen
- Kontraste in `Eigene Regeln` und in der `Technischen Ansicht` wurden für den Dunkelmodus sichtbar verbessert

## Relevante Dateien

- `README.md`
- `CHANGELOG.md`
- `HideMyData/Views/Main/EmptyState.swift`
- `HideMyData/Views/Main/MainView.swift`
- `HideMyData/Views/Toolbar/FloatingToolbar.swift`
- `HideMyData/Views/Intro/IntroView.swift`
- `HideMyData/Views/FirstRun/FirstRunView.swift`
- `HideMyData/Views/FirstRun/ModelSourceCard.swift`
- `HideMyData/ExportOptions.swift`
- `HideMyData/PDFRedactor.swift`
- `HideMyData/ImageRedactor.swift`
- `HideMyData/PatternMatcher.swift`
