# PROJ-23 – Onboarding- und Regeln-Editor-UX nachschärfen

**Status**: Abgeschlossen

## Ziel

Die ersten Produkttexte und der Regeln-Editor sollen so nachgeschärft werden, dass neue Nutzer Inkognito nicht nur als Schwärzungswerkzeug verstehen und die Arbeit mit eigenen Regeln ohne unnötige Scroll- oder Verständnisbarrieren abschließen können.

## Schwerpunkte

- Begrüßungsbildschirm klar auf Anonymisieren und Dateien ausrichten
- Nutzen von PDFs, Bildern und Zwischenablage im Onboarding deutlicher benennen
- Regeln-Editor so anpassen, dass der Abschluss auch am unteren Seitenende direkt erreichbar bleibt
- Formulierungen zu eigenen Regeln und abgeleiteten Teilregeln verständlicher machen
- eine produktnahe Hilfeseite ergänzen, die typische Nutzerfragen ohne technisches Vorwissen beantwortet

## Wichtige Vorsichtspunkte

- keine Produktaussagen einführen, die technische Fähigkeiten überziehen
- bestehende Regeln-Logik nicht verändern, nur ihre Kommunikation und Bedienbarkeit
- vorhandene Review- und Export-Begriffe konsistent zu den übrigen App-Flächen halten
- Hilfe nicht als langes Handbuch anlegen, sondern als schnelle, vertrauensbildende Produktführung

## Relevante Dateien

- `Inkognito/Views/Intro/IntroView.swift`
- `Inkognito/Views/FirstRun/FirstRunView.swift`
- `Inkognito/Views/Main/MainView.swift`
- `Inkognito/Views/Help/HelpView.swift` (neu)
- `docs/architecture.md`
- `docs/commercial-readiness-audit.md`
- `features/PROJ-21-commercial-readiness-relicensing-cleanup.md`

## Konkreter Help-Center-Vorschlag

Die Hilfeseite sollte nicht wie klassische Dokumentation wirken, sondern wie eine ruhige, produktnahe "So funktioniert Inkognito"-Fläche. Nutzer sollen drei Dinge schnell verstehen:

- was Inkognito anonymisiert
- wie der Review- und Exportablauf funktioniert
- wie eigene Regeln sinnvoll eingesetzt werden

### Empfohlene Struktur

#### 1. Einstieg: Was Inkognito macht

Kurzer Einstiegsblock mit 2 bis 3 Sätzen:

- Inkognito anonymisiert sensible Inhalte in PDFs, Bildern und Texten.
- Erkennung, Review und Export laufen lokal auf dem Mac.
- Vor dem Export können Treffer geprüft und fehlende Stellen ergänzt werden.

Der Ton soll ruhig und klar sein, ohne Marketing-Übertreibung und ohne Modell-Sprache.

#### 2. Schnellstart in 4 Schritten

Kurze Schrittfolge mit klarer Nutzerführung:

1. Datei oder Text öffnen
2. erkannte Stellen prüfen
3. fehlende Stellen ergänzen oder unnötige Treffer abwählen
4. anonymisierte Datei oder Text exportieren

Diese Sektion sollte sich sprachlich an `IntroView` anschließen, aber konkreter im Ablauf sein.

#### 3. Was wird erkannt?

Eine kompakte Karten- oder Listenfläche mit typischen Beispielen:

- Namen und Anreden
- Adressen
- E-Mail-Adressen und Telefonnummern
- Konto- und Kennnummern
- wiederkehrende Inhalte über eigene Regeln

Wichtig:
- nicht versprechen, dass alles immer vollständig erkannt wird
- stattdessen klar sagen, dass Sichtprüfung Teil des Workflows bleibt

#### 4. Eigene Regeln verständlich erklären

Das ist der wichtigste Help-Baustein für `PROJ-23`, weil hier aktuell das größte Missverständnispotenzial liegt.

Klar formulieren:

- Eigene Regeln helfen bei wiederkehrenden Namen, Adressen, Kennungen oder organisationsspezifischen Begriffen.
- Inkognito kann daraus zusätzliche Teiltreffer ableiten, damit typische Varianten leichter wiedergefunden werden.
- Eigene Regeln ersetzen die Sichtprüfung nicht, besonders bei OCR-Fehlern oder stark abweichenden Schreibweisen.

Empfohlene Mikrocopy:

- "Eigene Regeln sind besonders hilfreich, wenn dieselben Personen, Adressen oder Kennungen regelmäßig in Dokumenten auftauchen."
- "Inkognito kann aus einer Regel zusätzliche Teiltreffer ableiten, damit auch naheliegende Varianten leichter erkannt werden."
- "Bitte prüfe Treffer vor dem Export trotzdem kurz, besonders bei Scans oder schwacher OCR."

#### 5. Typische Fälle und Grenzen

Kurzer FAQ-Block statt langer Erklärung:

- Warum fehlt manchmal ein Name?
- Warum ist eine Adresse nur teilweise erkannt?
- Warum helfen eigene Regeln bei OCR-Fehlern nicht immer sofort?
- Warum sollte ich den Export vor dem Teilen prüfen?

Dabei explizit benennen:

- PDFs mit nativem Text sind meist stabiler
- Scans und OCR-nahe Dokumente brauchen eher Review
- bereits geschwärzte oder beschädigte Ursprungsdokumente können Erkennung erschweren

#### 6. Datenschutz und lokale Verarbeitung

Eigene Vertrauenssektion:

- Dokumente und Inhalte bleiben auf dem Gerät
- kein Konto erforderlich
- keine Cloud-Weitergabe der Inhaltsdaten

Diese Sektion ist für Erstvertrauen wichtig und sollte optisch nicht im Kleingedruckten verschwinden.

## UX-Empfehlung für die View

Als Vorbild eignet sich eher eine ruhige Sidebar- oder Themennavigation wie bei `Dictio`, aber für Inkognito deutlich reduziert:

- nicht zu viele Themen
- keine technische Werkzeugliste
- stattdessen 5 bis 6 große, selbsterklärende Hilfethemen

Empfohlene Themen:

- Schnellstart
- Dateien anonymisieren
- Treffer prüfen
- Eigene Regeln
- Typische Fragen
- Datenschutz

Für Inkognito ist eine flache Struktur wahrscheinlich besser als viele Unterkapitel.

## Design- und Inhaltsprinzipien

- kurze Absätze statt langer Fließtexte
- klare Beispiele statt abstrakter Erklärungen
- gleiche Begriffe wie in App und Export verwenden
- Hilfe auf Nutzerfragen ausrichten, nicht auf interne Architektur
- keine Angstkommunikation, aber ehrliche Grenzen

## Sinnvolle Einhängung in die App

- über einen Hilfe-Eintrag im Hauptfenster oder App-Menü
- optional zusätzlich als Link oder Sekundäraktion im Regeln-Editor
- nicht den Begrüßungsbildschirm überladen, sondern dort nur dezent darauf verweisen

## Empfohlene Umsetzungsreihenfolge

1. Help-Center-Inhalt und Themen final texten
2. `HelpView` als ruhige Sidebar-/Detail-Ansicht anlegen
3. Einstiegspunkt im Hauptfenster ergänzen
4. anschließend Onboarding- und Regeln-Editor-Texte auf dieselben Begriffe angleichen
