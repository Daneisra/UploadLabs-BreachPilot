# Upload Labs – Smart Automation

Mod de confort consacré au hacking pour [Upload Labs](https://store.steampowered.com/app/3606890/Upload_Labs/), basé sur le Godot Mod Loader intégré au jeu.

> **Version actuelle : 0.2.0.** Le mod maintient Infiltrer Entreprises et Infiltrer Gouvernement au plus haut niveau que votre puissance permet. Il est **désactivé par défaut** : réglez `regulation_mode` sur `active` dans les options.

## Objectif

Rendre le hacking plus confortable en respectant les mécaniques normales du jeu : pas de dégâts, de récompenses ou de ressources modifiés.

| Fonctionnalité | Version visée | État |
|---|---|---|
| Observateur des infiltrations (lecture seule) | 0.1.0 | **Validé en jeu** |
| Mesures pour la régulation (lecture seule) | 0.2.0-alpha.1 | Validé en jeu |
| Simulation à blanc des décisions, aucune action | 0.2.0-alpha.2 | Validé en jeu |
| Actionneur, pause sur le nœud, essais réels | 0.2.0-beta.1 | Validé en jeu |
| Auto Threat Manager (régulation de la menace) | 0.2.0 | **Validé en jeu** |
| Smart Hacking Advisor : conseils en lecture seule | À venir | En étude |

## Ce que fait la version 0.2.0

- Maintient Infiltrer Entreprises et Infiltrer Gouvernement au plus haut niveau réussissable, en une seule action, vers le haut comme vers le bas.
- Trois profils : conservateur, équilibré, agressif. En équilibré et agressif, le mod essaie aussi un niveau qui peut réussir, et redescend si l'essai échoue.
- Sous les boutons du nœud : état de l'automatisation, boutons `Pause` et `Reprendre`. Un changement de niveau par le joueur met le type en pause pour la session.
- Se suspend à vitesse × 5 ou si l'option native est active. `Ctrl+Alt+F10` arrête tout. Une anomalie arrête la régulation jusqu'au redémarrage du jeu.
- Les changements de niveau passent par les méthodes du jeu et sont enregistrés normalement dans vos sauvegardes.

Limites et scénarios partiellement validés : voir le [suivi du projet](docs/PROJECT_TRACKING.md).

## Compatibilité

Testé sur Upload Labs 3.0.12 et Godot Mod Loader 7.0.1, avec Smart GPU Manager, Smart Thread Manager, Better Splitters, Where Should I Connect?, Easy Tokens et ModManager.

Au démarrage, le mod vérifie les API du jeu qu'il utilise et se désactive proprement si l'une d'elles manque. Il n'étend aucun script du jeu et n'écrit rien dans les sauvegardes.

## Installation locale

Le mod n'est pas publié. Pour le construire :

```powershell
python tools/build_zip.py
```

Copiez ensuite le zip de `build/` dans le dossier `mods` du jeu, à créer à côté de l'exécutable. Pour retirer le mod, supprimez ce zip.

## Journaux

Les observations sont dans `%APPDATA%\Upload Labs\logs\modloader.log`, sur les lignes `Daneisra-SmartAutomation`.

## Documentation

- [Changelog](CHANGELOG.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Suivi du projet et tests](docs/PROJECT_TRACKING.md)

## Contenu du dépôt

Ce dépôt ne contient aucun fichier extrait du jeu, aucune sauvegarde et aucun secret.
