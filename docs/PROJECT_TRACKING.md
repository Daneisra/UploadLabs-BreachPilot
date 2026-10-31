# Suivi du projet

## État

| Phase | État |
|---|---|
| 1. Analyse | Terminée, revue externe favorable |
| 2. Structure du projet | En cours |
| 3. Prototype d'observation (0.1.0) | En cours, aucun test en jeu |
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
- Fréquence réelle des ticks et validité du seuil de détection.
- Justesse de la prédiction sur les niveaux élite.

## Limites connues

- `failure_power` est une déduction : le jeu n'émet aucun événement d'échec.
- Test 14 (initialisation tardive) : couverture **partielle**. Le mod se charge avant le bureau ; le test passe par une désactivation puis réactivation, ce qui n'équivaut pas à un vrai chargement tardif.
- Test 16 (vitesse de simulation) : à simuler s'il n'existe pas de moyen de l'exercer en jeu sans triche.

## Validation de la 0.1.0

**Critère de sortie :** aucune modification du niveau par le mod et aucune erreur de classification constatée sur les scénarios ci-dessous. Cela ne prouve pas l'absence de faux positifs.

| # | Scénario | Attendu | Résultat |
|---|---|---|---|
| 1 | Lancement avec le mod | Chargé, API validées, aucune nouvelle erreur | À faire |
| 2 | Avec et sans nœud Corps | Détection, ou attente sans erreur | À faire |
| 3 | Attaque réussie | `success`, temps restant cohérent à l'écran | À faire |
| 4 | Niveau trop élevé | `failure_power` | À faire |
| 5 | Raise et Lower en pleine attaque | `level_changed_reset`, jamais d'échec | À faire |
| 6 | Lanceur débranché | `failure_starved` | À faire |
| 7 | Nœud en pause | `failure_paused`, ou correction de l'hypothèse | À faire |
| 8 | Rechargement en pleine attaque | Cycle `partial` | À faire |
| 9 | Suppression et recréation du nœud | `invalidated`, puis nouvelle liaison | À faire |
| 10 | Option native active | Journalisée, changements bien classés | À faire |
| 11 | Passage de 4 à 5, puis de 5 à 6 | Écart de prédiction mesuré | À faire |
| 12 | Tous les mods actifs | Aucun conflit | À faire |
| 13 | Mod retiré | Sauvegarde intacte | À faire |
| 14 | Réactivation avec bureau déjà créé | Fonctionne, sans double connexion (couverture partielle) | À faire |
| 15 | Réussites rapides consécutives | Une observation par attaque | À faire |
| 16 | Vitesse de simulation modifiée | Aucun faux échec | À faire |
| 17 | Désactivation puis réactivation | Signaux reconnectés, sans doublon | À faire |
