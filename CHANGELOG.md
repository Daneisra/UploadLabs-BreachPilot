# Changelog

## 0.2.0-alpha.1 – en cours : mesures

Observation uniquement. **Aucun changement automatique du niveau de menace.**

### Ajouté

- Observation d'Infiltrer Gouvernement.
- Inventaire à l'exécution : méthodes natives, variantes de dégâts, recherches et nœuds de hacking disponibles.
- Mesures de l'infection, des variantes de dégâts et de la vulnérabilité.
- Simulateur probabiliste borné, comparé aux salves observées (`distribution_check`).
- Valeurs exactes du niveau suivant par les accesseurs natifs (`next_source`), et résumé de fiabilité du classificateur (`reliability_check`).

### Modifié

- Le zip porte la version complète. Le manifeste garde `0.2.0`, le format major.minor.patch documenté par le chargeur.

## 0.1.0 – 2026-10-31 : Observateur

Version d'observation uniquement, **sans régulation automatique**. Le mod ne modifie ni le niveau de menace ni aucune autre valeur du jeu.

### Ajouté

- Observation d'Infiltrer Entreprises à partir des signaux et propriétés du jeu, sans extension de script ni hook.
- Machine à états par fenêtre et identifiant de cycle : `success`, `failure_power`, `failure_starved`, `failure_paused`, `level_changed_reset`, `level_changed`, `reset_unknown`, `invalidated`.
- Mesures par attaque : temps utilisé, salves, valeur minimale et maximale des coups, pas du minuteur, dégâts et points de vie.
- Prédictions expérimentales journalisées : coefficient et modèle par salves, avec cas favorable et pire cas.
- Vérification des API au démarrage, avec désactivation propre si l'une manque.
- Configuration par le chargeur de mods : activation, niveau de journal, seuil de source coupée, inventaire des API, raccourci de débogage.
- Tests simulés (106 vérifications) et construction du zip.

### Découvert en jeu

- Les dégâts arrivent par salves, et une salve qui finit le pare-feu perd son excédent. Le coefficient × 1,5 est réfuté.
- Les coups sont des entiers aléatoires : 40 ou 41 pour 40,865 dégâts par seconde.
- Le niveau est partagé par type de nœud.

### Limites

Voir [le suivi du projet](docs/PROJECT_TRACKING.md#limites-connues).
