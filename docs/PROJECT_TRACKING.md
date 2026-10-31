# Suivi du projet

## État

| Phase | État |
|---|---|
| 1. Analyse | Terminée, revue externe favorable |
| 2. Structure du projet | Terminée, dépôt GitHub privé créé |
| 3. Observateur (0.1.0) | **Terminée**, validée le 2026-10-31, tag `v0.1.0` |
| Auto Threat Manager, `0.2.0-alpha.1` (mesures) | En cours sur `dev/0.2.0-alpha.1`, observation uniquement |
| Auto Threat Manager, `0.2.0-alpha.2` (simulation des décisions) | Non autorisée pour l'instant |
| Auto Threat Manager, `0.2.0-beta.1` (premières actions) | Non autorisée pour l'instant |
| 4. Auto Data Lab Supply (version ultérieure) | Non commencée |
| 5. Stabilisation | Non commencée |

**La version 0.1.0 observe uniquement et ne contient aucune régulation automatique.**

## Décisions

| Sujet | Décision |
|---|---|
| Version 0.1.0 | Observation seule, aucune modification de la menace |
| Intégration | Signaux et propriétés, sans extension de script ni hook |
| Option native `auto_level_breach` | Journalisée en 0.1.0 ; la régulation refusera de s'activer tant qu'elle est active |
| Data Lab | Observateur d'abord ; répartiteur seulement après preuve de sauvegarde, rechargement et retrait propres |
| Analyse du jeu | Plus de décodage de scripts ; inspection à l'exécution uniquement |

## Décisions pour la régulation (0.2.0)

Validées par Jérémy après revue. **Aucune n'est implémentée à ce stade.**

| Sujet | Décision |
|---|---|
| Étapes | `0.2.0-alpha.1` mesures, `0.2.0-alpha.2` simulation des décisions, `0.2.0-beta.1` premières actions, `0.2.0` validée. Chaque étape est testée et validée avant la suivante |
| Modes | Conservateur : 100 % de réussite théorique, marge 20 %. Équilibré : 99 %, marge 10 %. Agressif : 95 %, marge 0 %. 90 % éventuellement en paramètre avancé, après validation expérimentale |
| Baisse | Le seuil doit tenir compte de la probabilité d'échec attendue, pas d'une règle fixe |
| Prédiction | Méthodes natives d'abord, modèle probabiliste par salves. Formules de remplacement pour une décision active seulement si leur fiabilité est démontrée. Montée interdite si le modèle n'est pas assez fiable |
| Classificateur incertain | Mise en sécurité de la régulation |
| Baisse manuelle | Définit un **plafond durable**, levé explicitement par le joueur dans les paramètres |
| Interface | ModManager et journaux. Petit indicateur discret seulement quand la régulation sera active |
| Sécurité | Désactivée par défaut, refus si `auto_level_breach` est actif, arrêt d'urgence, méthodes natives uniquement, aucune écriture directe du niveau, vérification après chaque action |

**À démontrer avant `0.2.0-beta.1` :**

1. Un changement automatique peut intervenir entre deux attaques sans en interrompre une. `call_deferred()` ne suffit pas à le garantir.
2. Les échecs par manque de puissance sont distingués des coupures d'alimentation.
3. Aucune baisse sur `failure_starved` ni `reset_unknown`.
4. Les conditions de fiabilité du classificateur sont définies précisément.
5. Les calculs probabilistes sont bornés.
6. Les unités des délais, blocages et budgets d'actions sont définies.
7. La documentation indique que les changements de niveau faits par le mod sont enregistrés normalement dans les sauvegardes du jeu.

## Points ouverts

- Publication : les conditions applicables seront réexaminées à la préparation d'une version publique. Le jeu a un support officiel du modding et un Workshop ; aucun contact avec les développeurs n'est prévu ni bloquant à ce stade.
- Fiabilité de `failure_power`, à réévaluer avant toute régulation.
- Validité du seuil de détection sur de vrais échecs.
- Justesse du modèle par salves, notamment sur les niveaux élite et les attaques furtives.

## Mesures en jeu

Premier essai du 2026-10-31, 3 min 45 d'observation, niveau 2/4 :

- 19,97 ticks par seconde et pas de minuteur de 0,05 s : `tick_speed` est bien en secondes de minuteur par tick.
- 55 réussites sur 55 cycles, attaque de 4 s, 3 s au minuteur, car celui-ci démarre à la première salve.
- Valeurs du journal conformes aux captures : niveau, pare-feu, infiltration, dégâts.
- Le jeu stocke les niveaux en nombres flottants.

Deuxième essai du 2026-10-31, environ 3 min 50 d'observation, manipulations manuelles :

- Niveau 3 à 25,8 dégâts par salve : échec confirmé à l'écran, 9 `failure_power` sur 9. Le modèle par salves annonçait 6 s pour 5 s disponibles ; le coefficient annonçait une réussite et **est donc réfuté**.
- Raise et Lower en pleine attaque : 2 `level_changed_reset`, aucun faux échec.
- Lanceur coupé : 1 `failure_starved`, sans dégâts ensuite (`damage_rate=0`), aucun événement pendant l'attente.
- Dégâts passés de 25,8 à 30,96 en cours de session, cause non confirmée : le modèle annonce alors 5 salves et 4 s au niveau 3, **pas encore vérifié**.
- Arrêt et reprise de l'observateur : une seule observation par attaque ensuite. Les `cycle_id` repartent de 1 après une reprise.
- Le nœud n'a pas de bouton de pause. `failure_paused` n'a pu être observé qu'en simulation.

Troisième essai du 2026-10-31, deux sessions, 30,96 dégâts par salve :

- Niveau 3 : 24 réussites, 1 s restante à l'écran comme au journal. `prediction_check observed=0.8000 volleys=0.8000 coefficient=0.9000` : le modèle par salves est exact.
- Niveau 4 : échec confirmé à l'écran, comme annoncé par le modèle (8 salves, 7 s pour 5 s). 23 `failure_power`.
- Après `Ctrl+Z` en pleine attaque : le premier échec, sur un cycle incomplet, reste `reset_unknown` (`partial_cycle`), comme prévu.
- Suppression du nœud : `invalidated`, 15 s sans nœud sans erreur, puis nouvelle liaison.
- Option native : ses deux changements sont journalisés. Aucune montée native n'a pu se produire, faute de réussite au niveau maximal.
- Le redémarrage en pleine attaque n'a laissé aucune attaque en cours au rechargement : le chemin `partial` par rechargement n'a été vu qu'au premier essai, sur une réussite.

Session de jeu normale du 2026-10-31, 1 h 07 avec tous les mods : 1 281 réussites, 11 `failure_power`, aucune erreur venant du mod, niveau changé uniquement par le joueur.

- Niveau 4 à 61,9 dégâts : 2 s restantes, comme prévu. Le doublement en coupant Gouvernement est confirmé.
- Niveau 5, élite, à 61,9 dégâts : 303 et 1212 de points et 10 s, comme prévu, et 8 échecs. L'échec au niveau 5 est annoncé par le modèle, mais la durée de 24 s n'a pas pu être vérifiée.
- Niveau 4 après une amélioration (40,865 dégâts, 6 s) : le modèle annonçait 0,667 et a observé 0,6667 ; le coefficient annonçait 0,75.
- Vitesse de minuteur multipliée par 5 pendant 626 attaques (pas de 0,25 s), cause non confirmée : aucun faux échec, seuil adapté à 0,5 s.
- **Écart trouvé :** à 40,865 dégâts, 296 attaques ont pris 5 salves, 47 en ont pris 6 et 1 en a pris 7, d'où l'hypothèse des coups entiers aléatoires.
- **Défaut trouvé et corrigé :** une attaque pendant laquelle les dégâts changent était notée complète. Elle est maintenant incomplète, et un échec dans ce cas devient `reset_unknown` (`damage_changed`).
- Une attaque a réussi avec exactement 6 s utilisées sur 6 s : à égalité, la réussite semble passer avant l'échec. Un seul cas observé.

Mesure directe des coups du 2026-10-31, 7 min 30, niveau 4 à 40,865 dégâts : 86 réussites, coups de 40 ou 41 uniquement, 73 attaques à 5 salves et 13 à 6, aucune hors de la plage du modèle (5 à 7). L'hypothèse des coups entiers aléatoires est confirmée à cette valeur de dégâts.

Limite pour la régulation : une entrée de dégâts d'infection est apparue sur les nœuds. Ces dégâts sont continus et le modèle par salves ne les couvre pas.

## Limites connues

- `failure_power` est une déduction : le jeu n'émet aucun événement d'échec. Il a été juste en jeu aux niveaux 3, 4 et 5, sans attaque furtive ni dégâts d'infection.
- Seul `breach_corps` est observé.
- Les prédictions sont expérimentales. Le modèle par salves ne couvre ni les dégâts d'infection ni les attaques furtives. Les coups entiers aléatoires ne sont mesurés qu'à 40,865 dégâts par seconde.
- La vitesse de minuteur × 5 observée n'est pas expliquée. Elle n'a pas gêné le mod.
- Une attaque a réussi à égalité (6 s sur 6 s) : un seul cas, à ne pas considérer comme une règle.
- Les `cycle_id` repartent de 1 après une reprise de l'observateur.
- Tous les essais viennent d'une seule partie et d'une seule installation.

### Scénarios partiellement validés

| # | Scénario | Ce qui manque |
|---|---|---|
| 2 | Sans nœud | Nœud supprimé en cours de partie ; pas de partie lancée sans nœud |
| 7 | Pause | Le nœud n'a pas de bouton de pause : simulé seulement |
| 8 | Attaque interrompue | Vérifié après chargement et après `Ctrl+Z` ; le redémarrage ciblé n'a laissé aucune attaque en cours |
| 10 | Option native | Journalisée ; montée native vue seulement en simulation |
| 11 | Niveaux élite | 4 vers 5 vérifié ; 5 vers 6 impossible tant que le niveau 5 n'est pas franchi |
| 14 | Chargement tardif | Vérifié par désactivation puis réactivation, ce qui n'équivaut pas à un vrai chargement tardif |

## Commandes de développement

```powershell
# Première fois seulement : enregistre les classes de remplacement du chargeur
Godot_console.exe --headless --path . --import
# Tests simulés
Godot_console.exe --headless --path . --script res://tests/run_tests.gd
# Construction du zip dans build/
python tools/build_zip.py
```

Résultat à la clôture de la 0.1.0 : **106 vérifications, 0 échec**, sur Godot 4.7.2. Les tests simulés reposent sur notre compréhension du jeu et sur un faux jeu : ils ne remplacent pas les tests en jeu.

## Validation de la 0.1.0

**Critère de sortie :** aucune modification du niveau par le mod et aucune erreur de classification constatée sur les scénarios ci-dessous. Cela ne prouve pas l'absence de faux positifs.

**Validée le 2026-10-31.** Total en jeu : 1 485 réussites, 43 `failure_power`, 8 `level_changed_reset`, 1 `failure_starved`, 1 `reset_unknown`, 1 `invalidated`. Les événements de l'heure de jeu libre n'ont pas été comparés un à un à l'écran.

| # | Scénario | Attendu | Résultat |
|---|---|---|---|
| 1 | Lancement avec le mod | Chargé, API validées, aucune nouvelle erreur | Réussi (2026-10-31) |
| 2 | Avec et sans nœud Corps | Détection, ou attente sans erreur | Réussi : nœud supprimé en cours de partie, pas de partie sans nœud au lancement |
| 3 | Attaque réussie | `success`, temps restant cohérent à l'écran | Réussi (2026-10-31) |
| 4 | Niveau trop élevé | `failure_power` | Réussi (2026-10-31) |
| 5 | Raise et Lower en pleine attaque | `level_changed_reset`, jamais d'échec | Réussi (2026-10-31) |
| 6 | Lanceur débranché | `failure_starved` | Réussi (2026-10-31) |
| 7 | Nœud en pause | `failure_paused`, ou correction de l'hypothèse | Non applicable en jeu : pas de bouton de pause. Simulation seulement |
| 8 | Rechargement en pleine attaque | Cycle `partial` | Réussi par deux chemins : réussite après chargement, échec après `Ctrl+Z` |
| 9 | Suppression et recréation du nœud | `invalidated`, puis nouvelle liaison | Réussi (2026-10-31) |
| 10 | Option native active | Journalisée, changements bien classés | Partiel : journalisée, montée native non observée |
| 11 | Passage de 4 à 5, puis de 5 à 6 | Écart de prédiction mesuré | Partiel : 4 vers 5 vérifié, 5 vers 6 impossible (niveau 5 non franchi) |
| 12 | Tous les mods actifs | Aucun conflit | Réussi : 1 h 07 de jeu normal |
| 13 | Mod retiré | Sauvegarde intacte | Réussi : partie et niveaux normaux selon le joueur, aucune erreur nouvelle au journal |
| 14 | Réactivation avec bureau déjà créé | Fonctionne, sans double connexion (couverture partielle) | Réussi, couverture partielle |
| 15 | Réussites rapides consécutives | Une observation par attaque | Réussi à vitesse × 5 (moins de 1 s par attaque) |
| 16 | Vitesse de simulation modifiée | Aucun faux échec | Réussi : 626 attaques à vitesse × 5 pendant le jeu normal |
| 17 | Désactivation puis réactivation | Signaux reconnectés, sans doublon | Réussi (2026-10-31) |
