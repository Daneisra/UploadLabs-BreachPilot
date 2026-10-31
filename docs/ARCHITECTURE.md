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
    ├── breach_simulator.gd       # distribution exacte des salves, calcul pur et borné
    ├── gap_probe.gd              # mesure entre deux attaques, machine à états pure
    ├── gap_stats.gd              # totaux bornés de ces mesures
    └── threat_observer.gd        # adaptateur vers le jeu, en lecture seule
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

## Méthodes natives

L'observateur inspecte les méthodes du nœud à l'exécution (`get_script_method_list()`), sans aucun décodage. Il n'appelle que des accesseurs de lecture à un argument, après en avoir vérifié la forme : `get_max_firewall`, `get_max_breach`, `get_max_time`, `is_elite`. Il signale `level_up` et `level_down` sans jamais les appeler, ce qu'un test vérifie dans le code source.

## Simulateur

`breach_simulator.gd` calcule la distribution exacte des salves à partir des coups entiers aléatoires, et compte une égalité avec le minuteur comme un échec. Le calcul se limite aux salves que le minuteur autorise, 64 au plus, avec 2048 états par salve et un cache par conditions. Il n'est lancé qu'en fin d'attaque complète. Il ne couvre pas encore les dégâts d'infection : une attaque qui en reçoit est marquée non fiable (`sim_trusted=false`).

## Régulation simulée

Le régulateur ne fait que retourner des décisions hypothétiques : **rien dans cette version ne peut les appliquer**. Chaque décision sépare le niveau réel (`real_level`) du niveau supposé (`assumed_level`) et n'est proposée qu'une fois tant que le niveau réel et la puissance ne changent pas.

- **Unités :** délais, blocages, budgets et gels sont en secondes de minuteur du jeu, cumulées depuis `tick_speed`. Les fenêtres sont en attaques complètes et comparables. Le temps réel ne sert qu'au journal.
- **Prévision :** sans infection, probabilité exacte. Avec infection, encadrement : réussite dans le pire cas ou échec dans le cas nominal sont fiables, le reste est incertain. Le modèle d'infection doit d'abord réussir 10 comparaisons à la puissance courante, sinon il est incertain, et il devient invalide au-delà de 5 % de résultats hors plage. Vulnérabilité, furtivité et croissance `INFECTED` restent invalides tant qu'elles ne sont pas mesurées.
- **Montée :** réussites consécutives, prévision fiable et conforme au profil, sous le maximum et le plafond, hors blocage.
- **Baisse :** seuls les `failure_power` complets comptent. Il faut assez d'échecs pour que le hasard ne soit plus une explication acceptable (moins de 0,1 % sur la fenêtre de 20 attaques), et au moins 10 attaques si un risque est attendu. Un échec contre un risque attendu sous 1 % réfute la prévision : le niveau reste bloqué jusqu'au prochain changement de puissance.
- **Plafond manuel :** tout changement manuel fixe le plafond au nouveau niveau, vers le haut comme vers le bas. Il n'est supprimé que par une action explicite. Sans identifiant de sauvegarde fiable, il ne dure que la session et rien n'est écrit.
- **Sécurité :** option native active, classificateur peu fiable ou inversions répétées suspendent les décisions.

## Mesure entre deux attaques

Avec l'option `gap_probe`, désactivée par défaut, l'observateur relève l'état de chaque nœud en lecture seule : au début (`F`) et à la fin (`L`) du `_process` de l'image, à chaque tick (`T`), au signal `breached` (`B`) et dans un appel différé après ce signal (`D`). `call_deferred` n'est qu'un point d'observation.

- **Disponible :** ni attaque (`detected`), ni dégâts, ni pause, avec un minuteur réarmé. Connaître le résultat ne rend pas le nœud disponible.
- **Fenêtre brute :** du premier état disponible à la première trace de l'attaque suivante. **Fenêtre utilisable :** la même, à partir du moment où le résultat est aussi connu. Un échec n'est connu qu'après coup.
- **Incertitude :** chaque bord réel se situe entre deux relevés. L'écart maximal est journalisé (`uncertainty_ms_max`).
- **Journal :** rien par image. Détail des 20 premières fins d'attaque de chaque cas, 300 au total, totaux tous les 100 et à l'arrêt, au plus 64 cas.
- **Ordre :** `gap_order` indique à quel relevé chaque changement a été vu en premier.

Une fenêtre observée n'est pas une preuve de sécurité. Une future régulation devra contrôler l'état immédiatement avant chaque action et renoncer si elle ne peut pas garantir que le nœud est disponible.

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
