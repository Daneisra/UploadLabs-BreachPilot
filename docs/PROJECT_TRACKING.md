# Suivi du projet

## État

| Phase | État |
|---|---|
| 1. Analyse | Terminée, revue externe favorable |
| 2. Structure du projet | Terminée, dépôt GitHub privé créé |
| 3. Prototype d'observation (0.1.0) | Premier essai en jeu réussi, scénarios d'échec à tester |
| 4. Auto Data Lab Supply (0.2.0) | Non commencée |
| 5. Stabilisation | Non commencée |

## Décisions

| Sujet | Décision |
|---|---|
| Version 0.1.0 | Observation seule, aucune modification de la menace |
| Intégration | Signaux et propriétés, sans extension de script ni hook |
| Option native `auto_level_breach` | Journalisée en 0.1.0 ; la régulation refusera de s'activer tant qu'elle est active |
| Data Lab | Observateur d'abord ; répartiteur seulement après preuve de sauvegarde, rechargement et retrait propres |
| Analyse du jeu | Plus de décodage de scripts ; inspection à l'exécution uniquement |

## Points ouverts

- Réponse d'EnigmaDev Studios sur l'automatisation et l'inspection des API.
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

- `failure_power` est une déduction : le jeu n'émet aucun événement d'échec.
- Test 14 (initialisation tardive) : couverture **partielle**. Le mod se charge avant le bureau ; le test passe par une désactivation puis réactivation, ce qui n'équivaut pas à un vrai chargement tardif.
- Test 16 (vitesse de simulation) : à simuler s'il n'existe pas de moyen de l'exercer en jeu sans triche.

## Commandes de développement

```powershell
# Première fois seulement : enregistre les classes de remplacement du chargeur
Godot_console.exe --headless --path . --import
# Tests simulés
Godot_console.exe --headless --path . --script res://tests/run_tests.gd
# Construction du zip dans build/
python tools/build_zip.py
```

Les tests simulés reposent sur notre compréhension du jeu et sur un faux jeu : ils ne remplacent pas les tests en jeu.

## Validation de la 0.1.0

**Critère de sortie :** aucune modification du niveau par le mod et aucune erreur de classification constatée sur les scénarios ci-dessous. Cela ne prouve pas l'absence de faux positifs.

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
| 13 | Mod retiré | Sauvegarde intacte | À faire |
| 14 | Réactivation avec bureau déjà créé | Fonctionne, sans double connexion (couverture partielle) | Réussi, couverture partielle |
| 15 | Réussites rapides consécutives | Une observation par attaque | Réussi à vitesse × 5 (moins de 1 s par attaque) |
| 16 | Vitesse de simulation modifiée | Aucun faux échec | Réussi : 626 attaques à vitesse × 5 pendant le jeu normal |
| 17 | Désactivation puis réactivation | Signaux reconnectés, sans doublon | Réussi (2026-10-31) |
