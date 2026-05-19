# PROJ-9 – Terminologie- und Label-System

**Status**: Abgeschlossen

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

## Umsetzung

- vorhandenes Kategorien-Mapping in `FindingVisualSemantics` zu einem zentralen Nutzerlabel-Layer ausgebaut
- Kurz- und Langlabels für Haupt-Workflow, Legende, Diagnose und Regel-Editor vereinheitlicht
- Diagnoseansicht, Suchtreffer und Kopierexport auf Nutzerbegriffe statt Rohkategorien umgestellt
- Regelkategorien und Filterchips im Custom-Rules-Bereich an dieselbe Benennung angebunden

## Relevante Dateien

- `HideMyData/Views/Main/MainView.swift`
- Diagnose-View-Dateien
- Custom-Rules-UI
