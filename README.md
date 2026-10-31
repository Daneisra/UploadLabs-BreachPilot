# Upload Labs – Smart Automation

Mod de confort modulaire pour [Upload Labs](https://store.steampowered.com/app/3606890/Upload_Labs/), basé sur le Godot Mod Loader intégré au jeu.

> **État : en développement (0.1.0).** Aucune fonctionnalité n'a encore été validée en jeu. N'utilisez pas ce mod sur une partie importante sans sauvegarde.

## Objectif

Automatiser des tâches répétitives en respectant les mécaniques normales du jeu : pas de dégâts, de récompenses ou de ressources modifiés.

| Fonctionnalité | Version visée | État |
|---|---|---|
| Observateur des infiltrations (lecture seule) | 0.1.0 | En développement |
| Auto Threat Manager (régulation de la menace) | Après validation de la 0.1.0 | Non commencé |
| Auto Data Lab Supply : observateur | 0.2.0 | Non commencé |
| Auto Data Lab Supply : répartiteur | 0.2.0 | Non commencé |

La version 0.1.0 **ne modifie jamais** le niveau de menace : elle observe et journalise.

## Compatibilité visée

Upload Labs 3.0.12, Godot Mod Loader 7.0.1. Au démarrage, le mod vérifie les API du jeu qu'il utilise et se désactive proprement si l'une d'elles manque.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Suivi du projet](docs/PROJECT_TRACKING.md)

## Contenu du dépôt

Ce dépôt ne contient aucun fichier extrait du jeu, aucune sauvegarde et aucun secret.
