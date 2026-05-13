# PROJ-9 – Terminologie- und Label-System

**Status**: Geplant

## Ziel

Interne Modellbegriffe wie `private_person` oder `custom_identifier` dürfen nirgends ungefiltert in Nutzeroberflächen auftauchen.

## Schwerpunkte

- zentrales Mapping von Kategorie → Nutzerlabel
- Diagnose und Haupt-Workflow auf dieselbe Benennung bringen
- keine Snake-Case-Labels in user-facing Views

## Deliverables

- zentraler Label-Layer, z. B. `CategoryLabel`
- einheitliche Benennung in Diagnose, Sidebar und Editor
- klare deutsche Nutzerbegriffe

## Relevante Dateien

- `HideMyData/Views/Main/MainView.swift`
- Diagnose-View-Dateien
- Custom-Rules-UI

