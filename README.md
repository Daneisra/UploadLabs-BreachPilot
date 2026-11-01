# Upload Labs – Smart Automation

Mod de confort modulaire pour [Upload Labs](https://store.steampowered.com/app/3606890/Upload_Labs/), basé sur le Godot Mod Loader intégré au jeu.

> **Version actuelle : 0.2.0-beta.1.** L'archive standard observe et simule sans changer aucun niveau. Les changements automatiques n'existent que dans des archives d'essai construites à la demande. La régulation normale arrive avec la 0.2.0.

## Objectif

Automatiser des tâches répétitives en respectant les mécaniques normales du jeu : pas de dégâts, de récompenses ou de ressources modifiés.

| Fonctionnalité | Version visée | État |
|---|---|---|
| Observateur des infiltrations (lecture seule) | 0.1.0 | **Validé en jeu** |
| Mesures pour la régulation (lecture seule) | 0.2.0-alpha.1 | Validé en jeu |
| Simulation à blanc des décisions, aucune action | 0.2.0-alpha.2 | Validé en jeu |
| Actionneur, pause sur le nœud, essais réels | 0.2.0-beta.1 | Validé en jeu |
| Auto Threat Manager (régulation de la menace) | 0.2.0 | Non commencé |
| Auto Data Lab Supply : observateur, puis répartiteur | Ultérieure | Non commencé |

## Ce que fait la version 0.1.0

- Reconnaît le nœud Infiltrer Entreprises.
- Classe chaque attaque : réussite, échec par manque de puissance, source coupée, changement de niveau, réinitialisation inexpliquée.
- Mesure le temps restant, le nombre de salves et la valeur des coups.
- Écrit dans le journal une prédiction expérimentale pour le niveau suivant, sans agir dessus.

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
