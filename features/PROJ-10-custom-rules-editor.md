# PROJ-10 – Custom-Rules-Editor verständlicher machen

**Status**: Abgeschlossen

## Ziel

Der Editor für eigene Regeln soll wie ein Produktwerkzeug wirken, nicht wie ein internes Konfigurationspanel.

## Schwerpunkte

- `custom_identifier` als technisches Default entfernen
- Dropdown mit bestehenden Kategorien
- optionale `Eigene Kategorie`
- orange Hilfs-Buttons in echte Vorlagen-Chips oder klare Inline-Hinweise umwandeln

## Deliverables

- verständlichere Feldbeschriftungen
- bessere Kategorieauswahl
- klarere Hilfen/Vorlagen am Textfeld

## Relevante Dateien

- Custom-Rules-Editor-Views
- zugehörige Modelle/Enums

## Umsetzung

- Die technische Standardauswahl `custom_identifier` wurde im Editor durch einen produktnäheren Flow ersetzt: `Automatisch`, bestehende Kategorien und die bewusste Zusatzoption `Eigener Begriff`.
- Die Einordnung erklärt sich jetzt direkt im Formular über verständliche Hilfetexte und eine kompakte Zusammenfassung der aktuell verwendeten Kategorie.
- Die generische Beispielaktion am Textfeld wurde durch Vorlagen-Chips für Adressblock, Person und Kennung ersetzt.
- Zusätzliche Inline-Hinweise am Baustein-Editor reagieren auf den aktuellen Inhalt und helfen beim sinnvollen Zeilenaufbau.
