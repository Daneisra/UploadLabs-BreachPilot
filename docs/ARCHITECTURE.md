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
    ├── threat_actuator.gd        # seul script pouvant changer un niveau, verrouillé dans le dépôt
    ├── action_policy.gd          # verrou du dépôt et limites de l'essai en cours
    ├── regulation_state.gd       # pauses manuelles par type, en mémoire
    ├── automation_control.gd     # rangée d'état et bouton sous les boutons de niveau
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
- Raise et Lower réinitialisent l'attaque en cours. Sur un nœud disponible, ils n'ont provoqué aucune réinitialisation (10 cas sur 10, changements du joueur).
- Le minuteur démarre aux premiers dégâts.
- La fenêtre entre deux attaques peut ne durer qu'un tick, après une réussite comme après un échec. Voir les mesures dans le [suivi du projet](PROJECT_TRACKING.md).

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
- **Pause manuelle :** remplace les plafonds. Tout changement de niveau du joueur, `Ctrl+Z` compris s'il change vraiment le niveau, suspend le type. Seul un clic sur le nœud la lève. Elle dure toute la session, chargements compris, et rien n'est écrit.
- **Reprise :** le niveau actuel devient le point de départ, la fenêtre d'attaques est vidée et 2 attaques de stabilisation sont exigées. Délais, blocages, prévisions réfutées, budget et arrêts sont conservés. Le mod peut ensuite dépasser le niveau choisi par le joueur. Le bouton n'appelle aucune méthode de niveau.
- **Sécurité :** option native active, classificateur peu fiable ou inversions répétées suspendent les décisions.

## Actionneur

**Le code du dépôt ne peut changer aucun niveau.** `action_policy.gd` garde `ACTIONS_ENABLED` à faux, ce qui ferme les verrous de l'observateur et de l'actionneur. Seule l'archive construite par `tools/build_zip.py --trial` l'ouvre, pour un essai autorisé, et la construction échoue si du code réservé aux tests s'y trouve. En `dry_run`, tous les contrôles s'exécutent et le journal indique ce qui aurait été fait (`action_would_apply`).

**Essai actif :** même dans une archive d'essai, il faut l'option `active_trial` à vrai. Une ancienne configuration ne contient pas cette option, et `regulation_mode` ne peut demander que `off` ou `dry_run`. L'essai fixe lui-même ses limites, dans `action_policy.gd` : type, sens, niveaux, profil conservateur, 1 action, vérification sur 3 attaques. Un fichier propre à chaque essai (`user://smart_automation/trial_used.json`, `trial_2_used.json`, `trial_3_used.json`), écrit avant chaque appel et séparé des sauvegardes, interdit toute action après un redémarrage, même s'il reste du budget.

**Marge et baisse :** la marge du profil ne s'applique qu'aux montées. Pour une baisse, le niveau cible doit être annoncé fiable et réussi à 100 % sans marge.

| Étape | Règle |
|---|---|
| Décision | Le régulateur propose. Une baisse exige une prévision fiable et assez d'échecs observés |
| Occasion | Fin d'attaque uniquement : au tick où l'échec est déduit, ou dans un appel différé après `breached`. Le report n'est qu'un moyen d'arriver après la réinitialisation |
| Refus | Thread, arrêt, limite, nœud absent, option native, vitesse, plusieurs nœuds, classificateur, même attaque, niveau, bornes, plafond, puissance. L'action est abandonnée et le budget rendu si rien n'a bougé |
| Report | Attaque, dégâts, pause ou minuteur non réarmé : `action_deferred_no_safe_window`, nouvelle tentative à la fin d'attaque suivante, `action_starving` après 5 reports |
| Action | Contrôles et appel dans le même appel, sans attente. Un seul niveau, un seul point d'entrée (`_call_native`) |
| Après | Relecture immédiate du niveau et de l'état, puis vérification de l'attaque suivante (`action_verification`). Une attaque perturbée, incomplète ou absente, ou un rechargement, arrête la régulation |

- **Origine d'un changement :** `origin=mod` seulement pour le niveau attendu après une action du mod, et une seule fois. Tout autre changement est celui du joueur (pause du type, action en attente abandonnée), ou de l'option native si elle est active.
- **Arrêt d'urgence :** `Ctrl+Alt+F10`, toujours actif, sans option. Il dure jusqu'au redémarrage du jeu.
- **Limite d'actions :** `action_limit`, 1 par défaut. Elle arrête la régulation juste après l'action, et la vérification continue.
- **Un seul type :** un actionneur armé exige `action_type`, sans valeur par défaut.
- **Vitesse :** toute vitesse autre que 0,05 ou illisible empêche l'action. Un changement de vitesse efface la fenêtre d'attaques et relance la stabilisation.

**Limite :** tout cela n'est testé que sur un faux jeu, qui suit notre compréhension de `level_up` et `level_down`. Leur effet réel et le sens de leur argument ne sont pas vérifiés.

## Contrôle sur le nœud

Une rangée, créée à l'exécution, est ajoutée en dernier enfant de `MainContainer`, juste sous `ActionContainer`, qui contient `Lower Threat` et `Raise Threat`. Aucun script du jeu n'est modifié. Si cette structure manque, le nœud n'a simplement pas de contrôle (`automation_control result=unavailable`). L'état appartient au type et survit à la suppression du nœud. Le contrôle est retiré à l'arrêt de l'observateur, et jamais doublé.

| Affichage | Sens | Bouton |
|---|---|---|
| `Auto : actif` | Régulation armée, maintien du niveau compris | `Pause` |
| `Auto : simulation` | Même état, dans un build qui ne peut pas agir | `Pause` |
| `Pause manuelle` | Geste ou clic du joueur. L'infobulle signale un blocage éventuel | `Reprendre l'automatisation` |
| `Auto : bloqué` | Arrêt d'urgence, anomalie, budget, option native, vitesse, API, classificateur. Cause dans l'infobulle | Aucun |
| `Auto : désactivé` | Régulation coupée, ou type hors de l'essai | Aucun |

La pause et le blocage sont indépendants : reprendre ne lève jamais un blocage. Une prévision insuffisante est un maintien, pas un blocage. Les textes ne sont qu'en français pour l'instant.

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
