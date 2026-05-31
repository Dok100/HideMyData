# Decision Log

## 2026-05-16

- `PROJ-1` wird als abgeschlossen gewertet.
- Die Detection-Haertung gilt fuer native PDFs, OCR/Bilder und den Clipboard-/Platzhalterpfad als funktional stabil.
- Nicht-blockierende Restpunkte aus dem Clipboard-Preview werden nicht mehr in `PROJ-1`, sondern spaeter als Produktfeinschliff behandelt.
- `PROJ-2` startet mit einem technischen Export-Validierungsreport fuer PDF- und Bildexporte.
- Export-Vertrauen wird nicht nur ueber Text, sondern ueber konkrete technische Aussagen zu eingebrannten Schwärzungen, annotationsfreiem Export und Metadaten-Bereinigung kommuniziert.
- `PROJ-2` wird als abgeschlossen gewertet.
- Ein explizites Exportprotokoll oder ein vertiefter Validierungsdialog bleibt optionaler Produktfeinschliff und ist kein Release-Blocker.
- `PROJ-3` wird als abgeschlossen gewertet.
- Der Review-Workflow gilt mit Statuslogik, Ruecknahme, direktem Fokus-Sprung aus sichtbaren Schwärzungen und exportorientiertem Abschlussmoment als funktional stabil.
- Bei aktivem Filter `Nur offene Treffer` bleibt ein ueber die Dokumentflaeche fokussierter bestaetigter oder abgelehnter Treffer sichtbar, damit Korrekturen ohne Filterwechsel moeglich bleiben.
- `PROJ-5` wird als abgeschlossen gewertet.
- Das Farbsystem gilt fuer Kategorien, Statusflächen, Review-Karten und neutrale Hauptflächen als zentralisiert und konsistent genug fuer den aktiven Produktstand.
- `PROJ-6` wird als abgeschlossen gewertet.
- Startfläche, Leerzustände und Clipboard-Einstieg gelten als produktseitig klar genug, um die zwei Hauptworkflows gleichwertig zu kommunizieren.
- `PROJ-7` startet mit einem ersten Mikrocopy-Block fuer Trust-Momente im Intro, im Modell-Download und an den zentralen Einstiegen.

## 2026-05-19

- `PROJ-7` wird als abgeschlossen gewertet.
- Produktkommunikation gilt jetzt fuer Einstieg, Export, Review, `Eigene Regeln` und `Technische Ansicht` als ausreichend harmonisiert.
- Eigene Regeln zeigen gruppierte Nutzerregeln statt flachen Maschinen-Output, und Wartungsaktionen erklaeren sich an der Stelle, an der sie ausgefuehrt werden.
- Die `Technische Ansicht` bleibt technisch nutzbar, spricht aber mit klareren Abschnittstiteln und kontextbezogenen Info-Hinweisen produktnäher.
- `PROJ-8` wird als abgeschlossen gewertet.
- Die Erkennung nutzt jetzt leichte Dokumentklassen-Heuristiken fuer Rechnungen, Formulare, Bankseiten, DIN-5008-Briefe und E-Rechnungen, statt alle Seiten moeglichst generisch zu behandeln.
- Reale Referenzfaelle fuer DIN-5008, ZUGFeRD und E-Rechnungs-Feldsets werden als Regressionen mitgefuehrt.
- `PROJ-9` wird als abgeschlossen gewertet.
- Nutzer sollen in Review, Diagnose und Regeln keine rohen internen Kategorien wie `private_person` oder `custom_identifier` sehen.
- `PROJ-10` wird als abgeschlossen gewertet.
- Eigene Regeln bleiben flexibel, werden aber im Editor bewusst produktnah ueber Vorlagen, Kategorien und Beispiele erklaert statt ueber interne Musterbegriffe.
- `PROJ-11` wird als abgeschlossen gewertet.
- Blindspot-Schutz wird nicht nur ueber staerkere Heuristiken, sondern auch ueber sichtbare Produkttexte zur Sichtpruefung aufgebaut.
- `PROJ-12` wird als abgeschlossen gewertet.
- Vorschau, Legende und Trefferkarten teilen sich jetzt eine zentrale Farblogik, statt lokale Sonderfaelle nebeneinander zu pflegen.
- `PROJ-13` wird als abgeschlossen gewertet.
- Die Diagnoseansicht bleibt verfuegbar, wird aber klarer zwischen produktnaher Standardansicht und technischem Developer-Modus getrennt.
- `PROJ-15` wird als abgeschlossen gewertet.
- Mikrocopy priorisiert jetzt Nutzen, Pruefkontext und Folgeaktion statt UI-Meta-Sprache oder technisch klingende Statuswoerter.
- `PROJ-14` wird als defensiver Cleanup abgeschlossen, ohne Target-, Source-Ordner- oder Sparkle-Renames zu erzwingen.
- Aktive Legacy-Migrationspfade fuer Cache, Recents, Clipboard-Session und Bestandsdateien bleiben bewusst erhalten.
- Der laufende App-Pfad verwendet intern jetzt `InkognitoApp` und `Inkognito.showClipboardAnonymizer`, akzeptiert den alten Notification-Namen aber weiter als Fallback.
- `PROJ-16` wird als abgeschlossen gewertet.
- Der Review zeigt jetzt zusaetzlich einen kompakten Seitenstatus, damit Pruefvertrauen nicht nur an einzelnen Treffern haengt.
- Die erste Version nutzt bewusst einfache Produktregeln: `offen` bei unbeantworteten Treffern, `besonders prüfen` bei Namens-/dichten Seiten, `geprüft` bei entschiedenen Seiten und `wenig lesbarer Text` bei bereits gemeldeten OCR-/Textqualitaetsproblemen.
- `PROJ-17` wird als abgeschlossen gewertet.
- Unsicherheiten bleiben im Review sichtbar, werden nach dem UI-Feinschliff aber bevorzugt direkt an betroffenen Review-Karten und kompakten Seitenhinweisen gezeigt, statt eine zweite Meta-Ebene vor der Trefferliste aufzubauen.
- Die erste Version hebt schwachen Text, offene Treffer mit niedrigerer Sicherheit, Personenseiten und besonders pruefenswerte Seiten als produktnahe Hinweise hervor.
- `PROJ-18` wird als abgeschlossen gewertet.
- Die manuelle Nacharbeit wird zuerst ueber konservative Sammelaktionen beschleunigt: identische offene Treffer koennen direkt gemeinsam bestaetigt oder abgelehnt werden.
- Fuer die erste Version zaehlen gleiche Kategorie und normalisiert gleicher Textausschnitt als ausreichend sichere Aehnlichkeit.
- `PROJ-19` wird als abgeschlossen gewertet.
- Der Exportabschluss bekommt jetzt eine menschliche Zusammenfassung vor und nach dem Speichern, statt nur technischer Validierungsbausteine.
- Manuelle Ergaenzungen und bereits erkannte Textqualitaetsrisiken werden als Teil des Exportvertrauens sichtbar gemacht.
- `PROJ-20` wird als abgeschlossen gewertet.
- Eigene Regeln sind jetzt nicht nur editierbar, sondern geben schon vor dem Speichern Rueckmeldung zu Regelqualitaet und moeglichen Treffern im aktuell geoeffneten Dokument.
- Die erste Dokumentvorschau bleibt bewusst textbasiert und leichtgewichtig, damit der Editor schnell und ohne Eingriff in die eigentliche Erkennungslogik unterstuetzend bleibt.

## 2026-05-21

- `PROJ-21` wird als abgeschlossen gewertet.
- Das bisherige Fork-Repository bleibt als Nachschlagewerk und historische Referenz bestehen.
- Das neue Repository `Dok100/Inkognito` ist die kuenftige Produktbasis.
- Die verbleibenden Kernpfade aus dem Commercial-Readiness-Audit werden im aktuellen Stand bewusst akzeptiert; innerhalb von `PROJ-21` ist keine weitere Reduzierung mehr geplant.
- Die Lizenz im neuen Repository bleibt vorerst bewusst offen (`No license`), solange die geplante Kommerzialisierung vorbereitet wird.
- Der Sparkle-/Distributionsreset bleibt als separater Folgeblock in `PROJ-22` ausgelagert.

## 2026-05-13

- `Inkognito.xcodeproj` ist das aktive Projekt.
- Das alte `HideMyData.xcodeproj` wird nur noch archiviert und nicht mehr aktiv gepflegt.
- Die GitHub-CI baut direkt `Inkognito.xcodeproj`, statt ueber `xcodegen` ein Legacy-Projekt zu verifizieren.
- Feature-Planung lebt in `features/` nach einem projektweisen Format, angelehnt an Dicto.
- Historische Generator- und Icon-Arbeitsordner werden archiviert, nicht im aktiven Projektpfad weitergefuehrt.

## Offene Architekturentscheidungen

- Soll Seitenvertrauen spaeter von einfachen Produktregeln auf echte seitenbezogene Unsicherheitswerte umgestellt werden?
- Soll die Regel-Vorschau kuenftig echte Bounding-Boxen oder nur textbasierte Trefferlisten zeigen?
- Soll die Export-Validierung spaeter automatisiert pruefbar und als maschinenlesbarer Report exportierbar werden?
