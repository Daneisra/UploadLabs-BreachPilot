# Upload Labs – Smart Automation

Mod de confort consacré au hacking pour [Upload Labs](https://store.steampowered.com/app/3606890/Upload_Labs/), basé sur le Godot Mod Loader intégré au jeu.

> **Version actuelle : 0.5.0.** Le mod règle chaque nœud d'infiltration sur le niveau qui rapporte le plus pour l'objectif choisi, niveaux élites compris, et monte au besoin pour débloquer les suivants. Le panneau de conseil commence par la meilleure recommandation et propose des pistes à essayer. Il est **désactivé par défaut** : réglez `regulation_mode` sur `active` dans les options.

## Objectif

Rendre le hacking plus confortable en respectant les mécaniques normales du jeu : pas de dégâts, de récompenses ou de ressources modifiés.

| Fonctionnalité | Version visée | État |
|---|---|---|
| Observateur des infiltrations (lecture seule) | 0.1.0 | **Validé en jeu** |
| Mesures pour la régulation (lecture seule) | 0.2.0-alpha.1 | Validé en jeu |
| Simulation à blanc des décisions, aucune action | 0.2.0-alpha.2 | Validé en jeu |
| Actionneur, pause sur le nœud, essais réels | 0.2.0-beta.1 | Validé en jeu |
| Auto Threat Manager (régulation de la menace) | 0.2.0 | **Validé en jeu** |
| Smart Hacking Advisor : branchements et achats comparés, en lecture seule (`Ctrl+Alt+F8`) | 0.3.0 | **Validé en jeu** |
| Chaîne quelconque mesurée sans liste de nœuds, niveau le plus rentable | 0.4.0 | **Validé en jeu** |
| Recommandation en tête du panneau, pistes « À essayer », calculs repliables | 0.5.0 | **Validé en jeu** |

## Ce que fait le mod

- Règle chaque nœud d'infiltration sur le niveau qui rapporte le plus par minute pour l'objectif choisi dans le panneau (XP, données ou équilibré), niveaux élites compris, en une seule action. Il monte une fois au plus haut niveau débloqué quand il peut être gagné, pour ouvrir le suivant, puis revient.
- Lit la chaîne de hacking telle qu'elle est branchée et mesure ce que font ses nœuds dans les attaques réelles : un nœud inconnu ou venu d'un autre mod n'est pas un obstacle. Tant qu'une mesure manque, le panneau affiche « données insuffisantes » et la régulation vise le plus haut niveau qui tient.
- Trois profils : conservateur, équilibré, agressif. En équilibré et agressif, le mod essaie aussi un niveau qui peut réussir, et redescend si l'essai échoue. Après un essai de déblocage raté, le conservateur et l'équilibré attendent que la chance d'y gagner ait nettement augmenté ; l'agressif réessaie de temps en temps.
- Sous les boutons du nœud : état de l'automatisation, boutons `Pause` et `Reprendre`. Un changement de niveau par le joueur met le type en pause pour la session.
- Se suspend à vitesse × 5 ou si l'option native est active. `Ctrl+Alt+F10` arrête tout. Une anomalie arrête la régulation jusqu'au redémarrage du jeu.
- Les changements de niveau passent par les méthodes du jeu et sont enregistrés normalement dans vos sauvegardes.

`Ctrl+Alt+F8` ou le bouton `Conseil` du nœud ouvre le conseil hacking. Il affiche d'abord le meilleur branchement pour l'objectif choisi, étape par étape, avec le gain estimé, les inconvénients et la fiabilité, puis l'achat conseillé. La section « À essayer » signale, sans chiffre tant que rien n'est mesuré, les nœuds sans puissance ou sans dégâts, les sorties et entrées libres, et les nœuds débloqués pas encore posés. Le détail des calculs est dans une section repliable. Il ne fait qu'afficher : vous gardez la main sur vos branchements et vos achats.

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
