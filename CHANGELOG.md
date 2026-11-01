# Changelog

## 0.2.0-beta.1-dev.8 – en cours : actionneur, essais actifs et pause sur le nœud

**Le code du dépôt ne peut changer aucun niveau.** Seule une archive construite pour l'essai autorisé le peut, avec son option activée. Montée, baisse et 4 actions successives validées sur Gouvernement. Ce n'est pas encore la `0.2.0-beta.1`.

### Modifié

- Voie rapide : quand le niveau suivant est certain, une seule réussite suffit pour monter, sans délai de profil. Vérification sur 1 attaque pour un niveau normal, 3 avec infection, sur un niveau élite ou après un changement de puissance. Testée en simulation seulement.
- Une prévision certaine démentie suspend les montées sans baisser sur ce seul échec.
- Un changement de puissance ou de vitesse pendant une vérification n'arrête plus la régulation.
- Un chargement de partie repart d'observations neuves, sans être traité comme une anomalie. Pauses, blocages et budget restent.
- Rien n'est proposé pendant la vérification d'une action.
- Session finale : Gouvernement et Entreprises, profil équilibré, 40 actions au plus.

### Ajouté

- Rangée d'état et bouton sous `Lower Threat` et `Raise Threat`, sans dépendance à ModManager.
- Pause manuelle par type et reprise depuis le nœud.

### Retiré

- Les plafonds manuels, remplacés par la pause.

### Corrigé

- Une réussite certaine dont la probabilité s'arrondit juste sous 1 ne bloque plus une décision.

### Modifié

- La prévision du niveau visé par une baisse se calcule sans la marge, réservée aux montées.
- Le journal d'une action donne le moment exact (tick, image, microsecondes) et l'état du nœud avant et après.

### Ajouté

- `action_policy.gd` : verrou unique du dépôt et limites de l'essai.
- Option `active_trial`, désactivée par défaut, sans effet hors d'une archive d'essai.
- Marqueur d'essai écrit avant l'appel, qui empêche toute seconde action.
- `tools/build_zip.py --trial` : archive d'essai, avec refus du code réservé aux tests.
- Vérification de l'action sur 3 attaques, et niveaux de tous les nœuds journalisés autour de l'action.

- `threat_actuator.gd` : point d'entrée unique, contrôles immédiats, report sans action forcée (`action_deferred_no_safe_window`), vérification de l'attaque suivante, limite d'actions. Fermé par deux verrous dans le code, et testé sur un faux jeu seulement.
- Arrêt d'urgence `Ctrl+Alt+F10`.
- En `dry_run`, le journal indique ce que l'actionneur aurait fait.
- Journal en lecture seule des arguments des méthodes de niveau, des liens des boutons et des noms liés à l'annulation.

### Modifié

- Plus aucune baisse sans prévision fiable.
- Un changement de vitesse efface la fenêtre d'attaques du régulateur.

## 0.2.0-beta.1-gap.1 – mesure de la fenêtre entre deux attaques

**Aucun changement automatique du niveau de menace, aucun actionneur, aucun mode `active`.**

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
