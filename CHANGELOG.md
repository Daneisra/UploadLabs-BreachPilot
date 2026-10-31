# Changelog

## 0.2.0-beta.1-gap.1 – en cours : mesure de la fenêtre entre deux attaques

**Aucun changement automatique du niveau de menace, aucun actionneur, aucun mode `active`.** Ce n'est pas encore la `0.2.0-beta.1`.

### Ajouté

- Option `gap_probe`, désactivée par défaut : mesure en lecture seule du temps entre deux attaques.
- `gap_probe.gd` : horodatage en microsecondes, images et ticks, résultat connu distingué du nœud réellement disponible, effet des changements de niveau.
- `gap_stats.gd` : totaux bornés par cas, minimum, maximum, moyenne et distributions.
- Relevés au début et à la fin du `_process` de chaque image, pour établir l'ordre des traitements, et coût de la mesure dans le journal.

## 0.2.0-alpha.2 – 2026-10-31 : simulation à blanc

**Aucun changement automatique du niveau de menace.** Le mod peut seulement journaliser les décisions qu'il aurait prises. `regulation_mode` n'accepte que `off` (par défaut) et `dry_run`. Pré-version validée, tag `v0.2.0-alpha.2`.

### Ajouté

- `power_profile.gd` : signature de puissance, seules les attaques de même signature sont comparables.
- `breach_forecast.gd` : prévision `reliable`, `uncertain` ou `invalid`, avec un encadrement déterministe pour l'infection.
- `threat_regulator.gd` : décisions hypothétiques, profils, seuil statistique de baisse, anti-oscillation, stabilisation après un changement de puissance.
- `regulation_state.gd` : plafonds manuels par type, conservés pendant la session tant qu'aucun identifiant de sauvegarde fiable n'est connu.
- Comparaison des prévisions aux attaques réelles et signalement des résultats hors plage (`forecast_check`).
- Recherche à l'exécution d'un identifiant de sauvegarde (`save_candidates`).

### Modifié

- Une attaque où l'infection ou la vulnérabilité change n'est plus une mesure complète.
- Le lanceur de tests échoue au lieu de rester bloqué si une erreur d'exécution l'interrompt.

### Corrigé

- Une baisse est maintenant proposée quand la prévision annonce l'échec du niveau courant. Ces échecs étaient jugés attendus.

## 0.2.0-alpha.1 – 2026-10-31 : mesures

Observation uniquement. **Aucun changement automatique du niveau de menace.** Pré-version validée, sur la branche `dev/0.2.0-alpha.1`.

### Limites

- Infection : mesurée en jeu sur une seule configuration. Le simulateur intégré ne la couvre pas et marque ces attaques non fiables. Le modèle à pile n'existe qu'en prototype hors du jeu, et une attaque à 4,90 s sort de sa plage (2,90 à 3,70 s).
- Attaques furtives et vulnérabilité : **non mesurées**, faute de déblocage dans la partie.
- Niveaux élite : 5 observé, le passage de 5 à 6 reste à voir.

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
