# PROJ-11 – Vertrauensschutz bei Blindspots

**Status**: Abgeschlossen

## Ziel

Wenn sensible Stellen nicht erkannt werden, soll die App das Vertrauen nicht stillschweigend untergraben.

## Schwerpunkte

- bessere Erkennung kontextarmer Personennamen
- deutlicher Hinweis auf visuelle Nachprüfung
- Kommunikation von Erkennungsgrenzen ohne Panikmache

## Deliverables

- Detection-Verbesserungen für problematische Personenkontexte
- Prüfhinweis im Workflow
- ggf. Abschluss-Hinweis vor Export

## Relevante Dateien

- `Inkognito/PIIDetector.swift`
- `Inkognito/Views/Main/MainView.swift`

## Umsetzung

- Die Detektion ergänzt jetzt zusätzliche Personen-Heuristiken für knappe Namenskontexte wie `Herrn Max Muster`, `Muster, Max` und einzeilige Namensfelder.
- Im Review-Workflow weist ein eigener Blindspot-Hinweis jetzt sichtbar auf die notwendige visuelle Nachprüfung hin, ohne die Exportfreigabe unnötig zu dramatisieren.
- Vor dem Export wurde die Kommunikation geschärft: offene Prüfungen blockieren weiter den Export, und nach abgeschlossener Freigabe erinnert die UI noch einmal an Anreden, Namensvarianten und freie Textstellen.
