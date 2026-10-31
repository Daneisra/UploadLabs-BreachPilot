# Architecture

## Principes

- **Signaux plutôt que modification de scripts.** Le mod lit les signaux et les propriétés du jeu et, à terme, appelle ses méthodes publiques. Il n'étend aucun script du jeu en 0.1.0.
- **Pas de hooks du chargeur en 0.1.0.** Par défaut, ils écrivent `mod-hooks.zip` dans le dossier du jeu, et leur effet sur des scripts compilés n'est pas testé. L'option reste à réévaluer si les signaux ne suffisent plus.
- **Logique séparée du jeu.** Les décisions vivent dans des classes pures, testables hors jeu avec des scénarios simulés.
- **Accès défensif.** Les autoloads du jeu sont cherchés à l'exécution et vérifiés au démarrage. Si une API manque, la fonctionnalité se désactive sans planter le jeu.
- **Aucune donnée dans la sauvegarde.** L'état du mod reste en mémoire et ses réglages dans la configuration du chargeur.

## Structure

```
mods-unpacked/Daneisra-SmartAutomation/
├── manifest.json                 # métadonnées et schéma de configuration
├── mod_main.gd                   # point d'entrée du chargeur
├── core/
│   ├── api_guard.gd              # vérifie les API du jeu
│   └── sa_log.gd                 # journal à niveaux, format clé=valeur
└── features/threat_manager/
    ├── breach_classifier.gd      # machine à états pure
    ├── breach_prediction.gd      # calculs purs
    └── threat_observer.gd        # adaptateur vers le jeu
tests/                            # tests simulés (Godot sans interface)
tools/build_zip.py                # construit le zip du mod
```

## Démarrage

1. `_init()` ne fait que journaliser : les autoloads du jeu (`Signals`, `Globals`…) sont chargés après le chargeur et n'existent pas encore.
2. `_ready()` attend une image, vérifie les API et démarre l'observateur.
3. L'observateur se connecte aux signaux, puis balaie le bureau s'il existe déjà. `desktop_ready` relance un balayage. La liaison est idempotente et dédoublonnée par instance.

## Mécaniques observées

- Le niveau est partagé **par type** de nœud et le minuteur est propre à **chaque instance**. La régulation future sera donc organisée par type.
- Une réussite émet `Signals.breached` avant la réinitialisation du nœud : le temps restant est lisible à ce moment.
- Un échec n'émet **aucun signal**. `failure_power` est donc une **déduction**, à réévaluer avant toute régulation.
- Raise et Lower réinitialisent l'attaque en cours.
- Le minuteur démarre aux premiers dégâts.

## Machine à états

États : `UNBOUND`, `IDLE`, `ATTACKING`, `SUSPENDED`.

Une réinitialisation est reconnue quand `detected` repasse à faux **ou** quand `time` remonte pendant une attaque, car des dégâts peuvent relancer une attaque dans le tick qui suit l'échec.

Chaque attaque reçoit un `cycle_id`. Une réussite ferme son cycle dès le signal : un cycle fermé ne peut plus être classé.

| Événement | Condition | Pourra motiver une baisse |
|---|---|---|
| `success` | Signal `breached` reçu | Non |
| `level_changed_reset` | Réinitialisation avec un niveau différent | Non |
| `failure_power` | Tous les indices concordent (voir ci-dessous) | **Oui, le seul cas** |
| `failure_starved` | Temps écoulé sans progression récente | Non |
| `failure_paused` | Temps écoulé avec le nœud en pause | Non |
| `reset_unknown` | Toute autre réinitialisation | Non |
| `invalidated` | Instance disparue ou remplacée | Non |

`failure_power` exige : cycle complet, même nœud, même niveau, ni pause ni réussite, progression récente, et `time` passé d'une valeur proche de 0 à une valeur proche de `max_time`.

### Unités du seuil

`Attributes.tick_speed` vaut un nombre de **secondes de minuteur par tick** : c'est la valeur retirée de `time` à chaque tick. `time`, `max_time`, `tick_speed` et les pas mesurés sont donc tous en secondes de minuteur.

Le seuil « proche de 0 » est `max(2 × tick_speed, 1,5 × plus grand pas observé)`. C'est une hypothèse de départ : le journal enregistre les pas réels pour la vérifier.

## Prédiction (expérimentale)

Avec `r = temps utilisé / temps maximal`, le rapport prévu au niveau suivant vaut :

| Transition | Facteur |
|---|---|
| Normal vers normal | × 1,5 |
| Normal vers élite | × 3,75 |
| Élite vers normal | × 0,6 |

**Ces coefficients ne suffisent pas.** Les dégâts arrivent par salves et une salve qui finit le pare-feu perd son excédent. Sur la première mesure en jeu (niveau 2, pare-feu 18, infiltration 72, 25,8 dégâts par salve), le coefficient annonce 0,9 au niveau 3, alors que le modèle par salves annonce 7 salves, soit 6 s pour 5 s disponibles :

`salves = ⌈pare-feu / dégâts⌉ + ⌈infiltration / dégâts⌉` et `temps utilisé = (salves − 1) × intervalle`

Le journal enregistre les deux prédictions. Le modèle ignore pour l'instant les attaques furtives, qui ne touchent pas le pare-feu.

**Les coups sont des entiers aléatoires.** À 40,865 dégâts par seconde, `min_hit` et `max_hit` n'ont mesuré que des coups de 40 ou 41, et 40 ne suffit plus pour un pare-feu de 40,4 : environ 15 % des attaques prennent une salve de plus. Cela n'a été mesuré qu'à cette valeur de dégâts. Le modèle donne donc un cas favorable et un pire cas (`_worst`) : `model_volleys` et `model_volleys_worst` rejouent le niveau courant, et des salves observées hors de cette plage invalident le modèle. Une future régulation devra raisonner sur le pire cas.

La comparaison n'utilise que deux cycles complets, de niveaux consécutifs, dont les dégâts par seconde restent à ±5 % et dont les points de vie suivent la formule. Rien n'est calibré automatiquement.
