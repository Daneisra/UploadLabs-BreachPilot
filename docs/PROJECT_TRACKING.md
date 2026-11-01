# Suivi du projet

## État

| Phase | État |
|---|---|
| 1. Analyse | Terminée, revue externe favorable |
| 2. Structure du projet | Terminée, dépôt GitHub privé créé |
| 3. Observateur (0.1.0) | **Terminée**, validée le 2026-10-31, tag `v0.1.0` |
| Auto Threat Manager, `0.2.0-alpha.1` (mesures) | **Terminée**, tag `v0.2.0-alpha.1` |
| Auto Threat Manager, `0.2.0-alpha.2` (simulation à blanc) | **Terminée**, validée le 2026-10-31, tag `v0.2.0-alpha.2`. Cette validation ne couvre pas la régulation automatique |
| Auto Threat Manager, `0.2.0-beta.1` (premières actions) | **Terminée**, tag `v0.2.0-beta.1`, sur accord de principe de Jérémy du 2026-11-01. Régulation permanente non encore disponible |
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

Validées par Jérémy après revue. **Les changements automatiques de niveau ne sont pas implémentés à ce stade** : seule la simulation à blanc existe.

| Sujet | Décision |
|---|---|
| Étapes | `0.2.0-alpha.1` mesures, `0.2.0-alpha.2` simulation des décisions, `0.2.0-beta.1` premières actions, `0.2.0` validée. Chaque étape est testée et validée avant la suivante |
| Modes | Conservateur : 100 % de réussite théorique, marge 20 %. Équilibré : 99 %, marge 10 %. Agressif : 95 %, marge 0 %. 90 % éventuellement en paramètre avancé, après validation expérimentale |
| Baisse | Le seuil doit tenir compte de la probabilité d'échec attendue, pas d'une règle fixe |
| Prédiction | Méthodes natives d'abord, modèle probabiliste par salves. Formules de remplacement pour une décision active seulement si leur fiabilité est démontrée. Montée interdite si le modèle n'est pas assez fiable |
| Classificateur incertain | Mise en sécurité de la régulation |
| Intervention du joueur (2026-11-01, remplace les plafonds) | Tout changement manuel met le type en **pause**. Reprise par un bouton sur le nœud, jamais suivie d'un changement immédiat. Après une reprise, le mod peut dépasser le niveau choisi par le joueur |
| Portée de la pause | Toute la session, chargements compris. Rien n'est écrit |
| Langue de l'interface | Français uniquement, traductions à la préparation d'une version publique |
| Prévision avec infection | Encadrement déterministe. Non fiable tant que le modèle ne couvre pas les observations : aucune montée fondée sur lui |
| Partage de puissance | Surveillance seulement : détecter, invalider les mesures, attendre la stabilisation. Ne jamais modifier les branchements |
| Simulation à blanc | Séparer le niveau réel, la décision hypothétique et ses conséquences supposées. Ne pas répéter une même proposition |
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

**Si aucune fenêtre fiable n'est démontrée entre deux attaques, l'architecture sera revue avant de poursuivre.** Le rapport sur cette mesure décidera si le développement de l'actionneur peut commencer.

**Protocole de mesure validé le 2026-10-31 :** instrumentation `gap_probe` en lecture seule, cas A à H, dont l'option native (à remettre à sa valeur initiale après l'essai) et deux nœuds du même type si le jeu le permet, sans contourner ses limites. Zéro fenêtre nulle sur 300 observations serait encourageant, mais ne démontrerait pas l'absence de risque.

**Exigences pour la revue de l'actionneur, décidées par Jérémy le 2026-10-31.** Ce n'est pas une autorisation de le développer.

1. **Baisse :** jamais sur une prévision seule. Il faut une prévision fiable, des échecs réellement observés, une puissance stable et un seuil statistique suffisant. Les interruptions et les échecs de classement incertain sont exclus.
2. **Anti-oscillation :** documenter les résultats du seuil de 0,1 % : inversions après correction, baisses injustifiées, temps passé au niveau optimal.
3. **Interventions manuelles :** distinguer les vrais changements du joueur des réinitialisations liées au chargement ou au système. Un `Ctrl+Z` qui modifie réellement le niveau est pris en compte.
4. **Sécurité :** arrêt d'urgence, nombre limité d'actions, vérification du niveau après chaque action, arrêt immédiat en cas d'incohérence.
5. **Traçabilité :** chaque action journalise le niveau avant et après, sa justification, la fiabilité de la prévision, la marge de sécurité et les observations qui l'ont motivée.
6. **Essais :** d'abord avec le profil conservateur, sur une sauvegarde de test, avant d'envisager le profil équilibré.

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

## Mesures de `0.2.0-alpha.1`

Premier essai du 2026-10-31, 8 min, Entreprises et Gouvernement au niveau 4/5, tous les mods actifs : 225 réussites, aucun échec ni réinitialisation inexpliquée, aucune erreur venant du mod.

- **Méthodes confirmées à l'exécution, sur les deux nœuds :** `get_max_firewall/1`, `get_max_breach/1`, `get_max_time/1`, `is_elite/1`, `level_up/1`, `level_down/1`, `get_level/0`, `get_max_level/0`, `get_reward/1`, `get_experience_reward/1`. `level_up` et `level_down` n'ont pas été appelées.
- **Valeurs natives :** accord avec le niveau courant sur 225 attaques sur 225.
- **Variantes de dégâts :** `STEALTH=1`, `INFECTED=2`.
- **Simulateur, sur de nouvelles attaques :** Entreprises à 40,87 dégâts, 104 attaques à 5 salves et 16 à 6 (86,7 % et 13,3 %), pour 85,8 % et 14,1 % annoncés. Gouvernement : 6 salves sur 103 attaques, comme annoncé.
- **Défaut trouvé :** 3 attaques ont subi un passage à la vitesse × 5 en cours d'attaque, ce qui décale le temps mesuré de 0,15 s. Le garde-fou les a signalées. Elles ne comptent plus comme mesures complètes, et un échec dans ce cas devient `reset_unknown` (`speed_changed`).
- **Mesurable dans la partie actuelle :** l'infection (`build_infection`). **Pas encore mesurable :** la vulnérabilité (`research.injection`) et les attaques furtives (`ghost_attack` non débloqué), sous réserve que ce nœud soit bien celui de la furtivité.

Deuxième essai du 2026-10-31, 8 min, avec manipulations manuelles :

- **Niveau élite 5 :** sans infection, 6 échecs observés. Les valeurs natives (303, 1212, 12 s) sont exactes, y compris sur les échecs. Avec l'infection, 9 réussites : le maximum d'Entreprises est passé à 6.
- **L'infection est une pile :** elle gagne un entier proche de 22,29 par impulsion, à raison d'une par seconde. Chaque tick inflige `pile × tick_speed`, sur le pare-feu tant qu'il tient. La pile n'a pas grossi d'elle-même entre deux impulsions dans cette configuration, sans variante `INFECTED`. Elle atteint 243 en fin d'attaque au niveau 5.
- **Partage de la puissance :** relier l'Interface à deux entrées divise la puissance par 2 : 89 devient 45 sur chaque nœud, et Gouvernement, privé d'infection, échoue au niveau 4 (50 `failure_power` à 24,52 dégâts).
- **Modèle à pile, prototype hors du jeu, phases tirées au hasard :** niveau 5, 10,60 s annoncées pour 10,55 s observées. Niveau 4, 2,90 à 3,70 s annoncées pour 2,93 s en moyenne, avec 1 attaque à 4,90 s sur 84, qui sort de la plage. Observé, le décalage entre les deux sources reste quasi constant d'une attaque à l'autre : il n'est pas aléatoire.
- **Classement :** les 2 `reset_unknown` portent `damage_changed` et correspondent à de vrais changements de puissance.

Vitesse × 5 : très probablement le **Temps de repos** (× 5, payé en temps hors ligne), selon le joueur. Le journal `tick_speed` n'a pas encore vu d'activation pour le confirmer.

## Travaux de `0.2.0-alpha.2`

**Attaque atypique à 4,90 s :** sa première pile n'apparaît que 2,55 s après le début de l'attaque, contre moins de 0,1 s d'habitude. Avec ce décalage, le modèle donne 4,90 s à 0,25 s près (test simulé), et les autres attaques mesurées restent couvertes. L'explication la plus probable est le branchement de l'infection en pleine attaque. Une telle attaque n'est plus une mesure complète, à confirmer en jeu.

**Seuil statistique renforcé :** un seuil de 1 % provoquait 18 inversions en 22 h sur du pur hasard, car le test se répète à chaque attaque. Le seuil passe à 0,1 %, avec au moins 10 attaques si un risque est attendu. Échecs nécessaires sur 20 attaques : 2 sans risque attendu, 4 à 1 %, 5 à 3 %, 6 à 5 %.

**Première session à blanc, 2026-10-31, 25 min en `dry_run`, profil équilibré** (en dessous de l'heure demandée) : 195 réussites, 223 `failure_power`, aucune erreur venant du mod, aucun niveau changé par le mod.

- **Défaut trouvé et corrigé :** Gouvernement a échoué 223 fois sans proposition de baisse. La prévision annonçant un échec certain, le test statistique jugeait ces échecs attendus. Le hasard n'excuse plus que le risque accepté par le profil.
- **Prévision avec infection :** aucune comparaison hors plage. Entreprises niveau 5 : 10,00 à 10,70 s selon le décalage, et 9,06 s à plus forte puissance.
- **Explication des 4,90 s confirmée :** l'infection branchée en pleine attaque donne une première pile tardive (1,95 s et 4,65 s observées). Ces attaques sont bien marquées incomplètes.
- **Temps de repos confirmé :** `tick_speed` passe de 0,05 à 0,25 puis revient, sur le geste du joueur. 14 attaques complètes à vitesse × 5, aucun faux échec. Les 2 attaques à cheval sur un changement sont marquées incomplètes.
- **Lanceur coupé :** Entreprises continue par la seule infection (44,58, soit le double, 7,7 s). Gouvernement n'a plus de dégâts, sans faux échec.
- **Plafond :** 5 vers 4 puis 4 vers 5 donnent les plafonds 4 et 5. Une montée vers 6 reste retenue par le plafond (`at_manual_ceiling`).
- **Identifiant de sauvegarde :** seul `Data.files` ressort, sans valeur exploitable. La recherche est élargie.
- **Limite trouvée :** à vitesse × 5 avec infection, les salves sont sous-comptées (8 à 9 au lieu de 11), car une salve se confond avec la pile. Le modèle d'infection n'utilise pas ce comptage.

**Deuxième session à blanc, 2026-10-31, 1 h 40 en `dry_run`, profil équilibré, version corrigée :** 1 796 réussites, 422 `failure_power`, 1 `reset_unknown` expliqué au chargement, aucune erreur venant du mod. Niveau changé uniquement par le joueur, 2 fois.

- **Baisse proposée :** Gouvernement 4 vers 3, 32 s après le début, avec une réussite annoncée au niveau 3. Le joueur a fait ce changement 49 min plus tard : 422 échecs sur 422 au niveau 4 avant, 734 réussites complètes sur 734 au niveau 3 après.
- **Montée proposée :** Entreprises 5 vers 6, avec 4,3 s annoncées et 5,3 s au maximum sur 6 s. Faite par le joueur 22 min plus tard : 377 attaques de 4,25 à 4,35 s, moyenne 4,29 s, et 2 s restantes à l'écran.
- **Passage de 5 à 6 :** le niveau 6 n'est pas élite (91 et 364 de points, 6 s), et le maximum d'Entreprises passe à 7.
- **Distribution sans infection :** 6 salves annoncées et 64 observées sur 64 à 29,42 dégâts, 4 salves annoncées et 670 observées sur 670 à 35,31 dégâts.
- **Prévision avec infection :** aucune comparaison hors plage sur 1 060 attaques complètes, 145 au niveau 5 et 915 au niveau 6, à deux puissances. Modèle `verified`. À 35,31 dégâts, 8 attaques durent 3,95 s en 4 salves : l'infection finit probablement l'attaque juste avant la cinquième salve.
- **Plafonds :** 6 pour Entreprises et 3 pour Gouvernement, session uniquement. Après l'amélioration de l'Interface, le niveau 4 de Gouvernement est annoncé réussi et reste retenu (`at_manual_ceiling`). **Non vérifié en jeu.**
- **Changement de puissance :** l'amélioration de l'Interface (107 à 128) est détectée sur les deux nœuds, les 2 attaques suivantes sont écartées, et l'attaque à cheval est marquée incomplète.
- **Intervalle entre deux attaques, estimé par le rythme du journal :** environ 0,7 s à 1 s, à mesurer directement avant toute action.
- **Identifiant de sauvegarde :** `Account.save_slots`, `Data.get_slot_path` et `Data.get_local_slot` existent, mais aucune valeur ne désigne l'emplacement en cours. Pas de changement d'emplacement essayé. Plafonds en session uniquement.
- **Non couvert en jeu :** blocages, budget d'actions, gel et prévision réfutée. Une seule proposition par niveau et par puissance est apparue, car une simulation ne fait pas changer le niveau réel.
- **Points mineurs :** `forecast_uncertain` a une raison vide quand le modèle n'est pas encore vérifié, `prediction_check` et les champs `next_*` des événements ignorent l'infection (la décision ne les utilise pas), et le journal grossit d'environ 1 Mo par heure.

## Mesure des fenêtres entre attaques

Session du 2026-10-31, 48 min, build `0.2.0-beta.1-gap.1`, 1 013 fins d'attaque mesurées, aucun niveau changé par le mod, aucune erreur venant de lui. Écarts au protocole : échecs raccourcis à 10 min, vitesse × 5 limitée à 18 s puis 15 s, rechargement absent du journal.

| Cas | n | Fenêtre brute, en ticks | Fenêtre après connaissance du résultat |
|---|---|---|---|
| Réussite, × 1 | 794 | 20 : 717, 15 : 16, 8 : 1, 7 : 1, 3 : 1, 2 : 11, 1 : 47 | Minimum 21 ms, 5 images |
| Réussite, × 5 | 30 | 4 : 13, 2 : 17 | Minimum 94 ms, 14 images |
| `failure_power`, × 1 | 154 | 20 : 100, 1 : 54 | 19 ticks, ou 2,4 à 13 ms sans image restante |
| `failure_power`, × 5 | 20 | 1 : 20 | 2,2 à 3,6 ms, sans image restante |

- **Aucune fenêtre absente sur 1 013, aucun résultat connu après le début de l'attaque suivante.** Ce volume ne prouve pas l'absence de risque, surtout à × 5 (50 fins d'attaque seulement, sans changement de vitesse).
- **Réussite :** `breached`, puis réinitialisation complète, visible au point différé dans la même image pour 824 sur 824. Cela ne vient pas de `call_deferred` lui-même.
- **Échec :** réinitialisation vue au début de l'image suivante, résultat déduit au tick suivant, environ 50 ms après.
- **Ordre mesuré :** le tick arrive après le dernier `_process` de l'image dans 56 888 cas sur 56 888. Le mod reçoit `tick` avant les nœuds du jeu dans cette session, car le minuteur n'a bougé qu'au relevé suivant dans la quasi-totalité des cas. Cet ordre n'est pas garanti : il pourrait s'inverser après une reprise de l'observateur.
- **Durée :** la fenêtre dépend de la phase entre la fin de l'attaque et la prochaine salve. Réussites Entreprises : 3,95 s donnent 1 tick (47 fois), 3,90 s en donnent 2 (11 fois), 4,00 s en donnent 20. Échecs à × 1 : 1 tick avec le minuteur de 12 s, 20 ticks avec celui de 6 s. La cause exacte de cet écart n'est pas établie.
- **Changements manuels :** 10 sur un nœud disponible, aucune réinitialisation, attaque suivante complète et de durée normale. 9 en pleine attaque : réinitialisation dans la même image. Aucun dans la fenêtre d'un seul tick.
- **Option native :** activée 15 s, aucun changement de niveau, sous le maximum des deux types. Son comportement reste inconnu.
- **Deux nœuds du même type :** impossible dans cette partie, l'ajout de nœud affiche `Actif 1/1`.
- **Hors écran :** mêmes durées qu'à l'écran.
- **Coût :** 173 µs par image en moyenne, 2,5 % d'une image à 144 images par seconde, pointe de 21,9 ms. Il n'existe pas de mesure de référence sans l'instrumentation.
- **Non démontré :** l'effet d'un appel fait par le mod. Seuls des changements du joueur ont été observés.

## Anti-oscillation, en simulation

Décisions appliquées à un jeu simulé, 5 tirages de 20 000 attaques (environ 22 h chacun). Ce sont des résultats de simulation, sans passage par l'actionneur ni le jeu.

| Scénario | Profil | Inversions | Baisses injustifiées | Échecs | Au meilleur niveau |
|---|---|---|---|---|---|
| Stable | Les 3 | 0 | 0 | 0 | 100 % |
| Niveau à 97 % | Conservateur, équilibré | 0 | 0 | 0 | 100 % |
| Niveau à 97 % | Agressif | 12 | 6 | 2 977 | 99,7 % |
| Prévision fausse | Les 3 | 25 | 0 | 30 | 99,9 % |
| Puissance changeante | Conservateur, équilibré | 5 | 0 | 40 | 99,9 % |
| Puissance changeante | Agressif | 5 | 0 | 115 | 99,8 % |

Ces chiffres incluent la voie rapide des montées certaines.

Avec une prévision fausse, le niveau réfuté est retenté une fois à chaque changement de puissance, soit 3 essais par tirage dans ce scénario.

## Premier essai actif, autorisé le 2026-10-31

Conditions fixées par Jérémy : sauvegarde de test avec copie de sécurité, emplacement secondaire de préférence, `breach_government` de 2 à 3, une seule montée, profil conservateur, vitesse normale, option native désactivée, arrêt de la régulation juste après.

Réussite : un seul appel natif, niveau final de 3, aucune attaque interrompue, aucune réinitialisation inattendue, aucun autre nœud modifié, changement identifié comme venant du mod, aucun plafond créé, attaques suivantes normales, arrêt automatique, aucune erreur du mod. En cas d'anomalie, aucune nouvelle action.

**Contrôle préalable du 2026-10-31, build `dev.2` sans action possible :**

- `level_up(times:int)` et `level_down(times:int)`, sans valeur par défaut. `AddButton` mène à `_on_add_button_pressed()` et `ReduceButton` à `_on_reduce_button_pressed()`, sans argument. Ce que ces deux méthodes font d'autre reste inconnu.
- `action_would_apply` de 2 à 3 sur `breach_government`, 32 s après la liaison, prévision fiable, 3,0 s au maximum sur 6 s, ce qui implique le fil principal.
- Aucune méthode nommée `undo`, `redo` ou `history` dans les autoloads. Le mécanisme de `Ctrl+Z` reste inconnu.
- `Ctrl+Alt+F10` : arrêt confirmé. Le journal montre 2 lignes dans la même seconde, sans effet puisque l'arrêt est idempotent. La cause n'est pas établie (deux appuis ou événement reçu deux fois).
- La partie lancée vient de la sauvegarde automatique : le niveau 2 s'y trouve, alors que les emplacements locaux 1 et 9 datent d'avant ce changement.

**Premier essai réel, 2026-10-31, build `0.2.0-beta.1-trial.1` : réussi.** Gouvernement passe de 2 à 3 à 23:15:58, après une réussite complète, en profil conservateur, à 35,31 dégâts.

| Critère | Résultat |
|---|---|
| Un seul appel natif | `actions=1`, une seule hausse d'un niveau, marqueur écrit une fois |
| Niveau final de 3 | Relu à 3 juste après l'appel, 3/5 à l'écran, 3 au redémarrage suivant |
| Aucune attaque interrompue | L'attaque en cours était terminée, `detected_after=false`, minuteur à 6,0 sur 6,0 |
| Aucune réinitialisation inattendue | 0 `level_changed_reset`, 0 `reset_unknown`, `level_changed` simple |
| Aucun autre nœud modifié | `breach_corps:6` avant et après, 6/7 à l'écran |
| Origine du mod | `level_origin ... origin=mod` |
| Aucun plafond | 0 `manual_ceiling` |
| Attaques suivantes normales | `action_verification outcome=verified`. 58 attaques complètes au niveau 3, toutes en 3,0 s et 4 salves, comme prévu, 3 s restantes à l'écran |
| Arrêt automatique | `regulation_stopped reason=action_limit_reached actions=1` dans la même seconde |
| Aucune erreur du mod | Aucune au journal |

Le changement a survécu au redémarrage, ce qui montre qu'il est enregistré normalement. Il n'y a eu aucun report (`deferred_no_safe_window=0`), car la fenêtre après cette réussite était d'environ 1 s. L'essai ne dit donc rien de la fenêtre d'un tick.

**Non couvert :** baisse, fenêtre d'un tick, plusieurs actions, `Ctrl+Z` après une action du mod, Entreprises avec infection. Le marqueur `trial_used.json` reste en place. L'archive d'essai a été retirée du jeu.

**Deuxième essai, autorisé le 2026-10-31 :** baisse de Gouvernement de 5 à 4, une seule action, profil conservateur, même protection qu'au premier essai, nouveau marqueur `trial_2_used.json`. Le niveau 4 n'est annoncé fiable que sans marge (5,0 s sur 6 s, pour une limite de 4,8 s avec 20 %), ce qui a été présenté à Jérémy avec les mesures.

**Deuxième essai réel, 2026-10-31, build `0.2.0-beta.1-trial.2` : réussi.** Gouvernement passe de 5 à 4 à 23:51:48, 52 s après la liaison du nœud, à 35,31 dégâts.

| Critère | Résultat |
|---|---|
| Un seul appel à `level_down()` | `actions=1`, une seule baisse d'un niveau |
| De 5 à 4 exactement | Relu à 4 juste après l'appel, 4/5 à l'écran, 4 au redémarrage suivant |
| Entreprises inchangé | `breach_corps:6` avant et après, 6/7 à l'écran |
| Aucune attaque interrompue | État avant l'appel : `detected:false`, minuteur 12,0 sur 12,0, aucun dégât |
| Aucune réinitialisation due à l'action | 0 `level_changed_reset`. Le seul `reset_unknown` date du chargement, 48 s plus tôt |
| Origine du mod, aucun plafond | `origin=mod`, 0 `manual_ceiling` dans cette session |
| Attaques suivantes conformes | `outcome=verified`. 19 attaques complètes au niveau 4, toutes en 5,0 s et 6 salves, 1 s restante à l'écran |
| Arrêt automatique | `regulation_stopped reason=action_limit_reached actions=1` dans la même seconde |
| Aucune erreur du mod | Aucune au journal |

- **Avant la décision :** 4 échecs complets (2 de stabilisation, 2 comptés), après une attaque partielle au chargement écartée.
- **Fenêtres manquées :** 0 (`deferred_no_safe_window=0`), une seule tentative.
- **Moment :** tick 1022, image 7682, au tick où l'échec est déduit. L'attaque suivante apparaît au même numéro de tick et d'image. L'action a donc eu lieu dans une fenêtre d'un tick, sans image libre entre les deux. Le niveau 4 s'applique dès la première salve : 6 salves et 5,0 s.
- **État juste après l'appel :** pare-feu 101 sur 101, minuteur 6,0 sur 6,0. Le changement est immédiat, dans le même appel.
- **Limite :** une seule action dans une fenêtre d'un tick. Cela montre que c'est possible, pas que c'est toujours sûr. Le chemin de report n'a pas été exercé en jeu.

**Contrôle de la pause sur le nœud, 2026-11-01, build `dev.5` sans action possible, 3 sessions :** conforme.

- **Pause :** par le bouton, ou par un changement de niveau du joueur, en moins d'une seconde, sans effet sur l'autre type.
- **Reprise :** niveau inchangé. La première décision simulée arrive 61 s plus tard.
- **Blocages :** option native et vitesse × 5 affichent `Auto : bloqué`, sans bouton, et se lèvent avec leur cause. La décision suivante repart de zéro.
- **Cycle de vie :** pause conservée après le rechargement de la sauvegarde automatique, rangée unique après un redémarrage de l'observateur, après la suppression et la restauration du nœud, et après une relance du jeu.
- **`Ctrl+Z` :** selon Jérémy, il ne fait pas remonter le niveau. Le journal montre toutefois une hausse `origin=player` de 2 à 3, 6 s après la baisse, dont l'origine exacte (clic ou `Ctrl+Z`) reste à confirmer à l'essai. La pause est restée dans tous les cas.
- **Aspect :** taille du texte et de la rangée validée par Jérémy.

**Sauvegardes :** Jérémy a enregistré par erreur dans le Slot 1 local et le Slot 2 cloud pendant ce contrôle. Rien n'a été restauré. Il reste l'ancien Slot 1 dans `2026-10-31_23-48-53_avant-essai-actif-2`, le Slot 9 intact, et l'état proche du Slot 2 cloud d'origine (21:51:13) dans `savegame.dat` de `2026-10-31_22-39-50_avant-controle-essai-actif` (21:51:16).

**Troisième essai, 2026-11-01, build `0.2.0-beta.1-trial.3` : réussi.** Gouvernement seul, de 0 à 4, 4 actions au plus, profil conservateur, 60 s au moins entre deux actions, vérification sur 3 attaques, marqueur `trial_3_used.json`, à 35,31 dégâts.

| Heure | Événement | Détail |
|---|---|---|
| 00:57:54 | Montée 0→1 | 15 s après la liaison, 5 réussites, 8 attaques au niveau 0, vérifiée à 00:58:00 |
| 00:58:56 | Montée 1→2 | 62 s après, 31 attaques au niveau 1, vérifiée à 00:59:08 |
| 01:00:00 | Montée 2→3 | 64 s après, vérifiée à 01:00:12 |
| 01:00:20 | Maintien à 3 | `forecast_too_risky` : niveau 4 à 5,0 s, marge de 20 % non respectée. `Auto : actif`, plus de 3 min sans action |
| 01:04:05 | Baisse à 2 par le joueur | `origin=player`, `automation_pause`, aucune remontée pendant 2 min 20 |
| Entre les deux | `Ctrl+Z` | Selon Jérémy, niveau inchangé et pause conservée. Aucun événement de niveau au journal, ce qui concorde |
| 01:06:25 | Reprise | Niveau inchangé, 2 attaques de stabilisation, puis 5 réussites |
| 01:06:52 | Montée 2→3 | 27 s après la reprise, 4e et dernière action, vérifiée à 01:07:04 |
| 01:06:52 | Arrêt | `regulation_stopped reason=action_limit_reached actions=4`, `Auto : bloqué` sur la capture |

Toutes les actions : `moment=deferred`, `problem=none`, `origin=mod`, Entreprises à 5 avant et après. 0 réinitialisation due à une action, 0 fenêtre manquée, 0 erreur du mod. Attaques suivantes conformes : niveau 1 à 1,0 s et 2 salves (31), niveaux 2 et 3 à 3,0 s et 4 salves (58 et 109).

**Remarque de Jérémy :** les temps sont respectés, mais c'est trop lent quand le niveau suivant est certain. Le journal le confirme : 31 attaques au niveau 1 pour une prévision certaine dès la première.

**Puissance :** l'Interface est montée à 42,37 dégâts par nœud à 01:13:39, pendant une pause. Le changement est bien détecté, sans action.

**Quatrième essai, 2026-11-01, build `0.2.0-beta.1-trial.4`, 24 min 49 : réussi.** Gouvernement et Entreprises avec infection, profil équilibré, voie rapide, budget de 12 actions : 8 utilisées. 339 attaques au niveau 4 sur Gouvernement et 329 au niveau 7 sur Entreprises, 0 échec, 0 réinitialisation due à une action, 0 fenêtre manquée, 0 prévision hors plage, 0 erreur du mod.

| Heure | Action | Attaques avant | Prévu au maximum | Observé |
|---|---|---|---|---|
| 01:38:33 | Gouvernement 0→1 | 7 s après la liaison | 0,95 s | 1,0 s |
| 01:38:35 | Gouvernement 1→2 | 1 | 2,85 s | 3,0 s |
| 01:38:39 | Gouvernement 2→3 | 1 | 3,0 s | 3,0 s |
| 01:38:43 | Gouvernement 3→4 | 1 | 5,0 s | 5,0 s |
| 01:39:40 | Entreprises 3→4 | 5 s après la reprise | 2,45 s | 2,0 à 2,2 s |
| 01:39:48 | Entreprises 4→5 (élite) | 3 | 8,25 s | 7,5 à 7,7 s |
| 01:40:11 | Entreprises 5→6 | 3 | 4,05 s | 3,8 à 3,85 s |
| 01:40:24 | Entreprises 6→7 | 3 | 5,35 s | 4,8 à 4,85 s |

- **Voie rapide :** Gouvernement de 0 à 4 en 10 s après la première action, 17 s après la liaison, pour environ 20 s estimées et 2 min 20 pour 0 à 3 au troisième essai. Vérification sur 1 attaque (Gouvernement) et 3 attaques (Entreprises).
- **Écart :** une durée de 3,0 s et une de 1,0 s dépassent de 0,05 s le maximum annoncé, à cause du tick de fin. Elles restent dans la tolérance de 0,15 s.
- **Deux types :** chaque action ne change que son type. Pause et reprise d'Entreprises sans effet sur Gouvernement. `previous_action_unverified` refusé 6 fois sur Entreprises, le temps de ses propres vérifications, sans budget consommé.
- **Infection :** les 10 comparaisons se sont faites pendant la pause, d'où la montée 5 s après la reprise. Aucune montée sur le niveau 8 : d'abord annoncé en échec avec la marge, puis incertain à la nouvelle puissance.
- **Puissance, changement naturel à 01:43:53 (42,37 à 52,96) :** détecté sur les deux types, attaques à cheval marquées incomplètes, stabilisation, prévisions recalculées, modèle d'infection à revérifier. Aucune action possible ensuite : la première montée après un changement n'a donc pas été observée.
- **Point mineur :** pendant une vérification, le régulateur repropose une montée, journalisée puis refusée. À clarifier dans le journal.
- **Non couvert en jeu :** échecs réels en mode actif, baisse en profil équilibré, prévision certaine démentie, première montée après un changement de puissance, rechargement avec régulation active.

**Session finale, première tentative, 2026-11-01, build `trial.5` : arrêtée à juste titre après 4 min.** Jérémy a ajouté un nœud `Payload critique` à 02:35. Dégâts annoncés : 87,39, coups réels : 52 à 53, et 132 environ une fois sur dix. Le mod a jugé le niveau 8 certain d'après la valeur annoncée (5,0 s au plus), l'a appliqué, puis la vérification a mesuré 5,25 s : `verification_failed:duration_out_of_range`, régulation arrêtée sur les deux types, aucune autre action. Le modèle a ensuite été corrigé. Le branchement de l'infection sur les deux nœuds a aussi été observé : infection divisée par 2, 4 échecs au niveau 8, sans baisse puisque la régulation était déjà arrêtée et la prévision incertaine.

**Session finale, deuxième tentative, 2026-11-01, build `trial.6`, 1 h 05 :** avec `Payload critique`, 0 action, aucun blocage, 1 026 + 677 attaques réussies. Rechargement avec pause validé : pause conservée, aucune action immédiate, reprise sans changement. **Défaut trouvé par Jérémy :** infection débranchée, 31 échecs au niveau 8 sans baisse. Le mod décidait bien de baisser dès le 2e échec, mais l'actionneur refusait (`target_forecast_not_reliable`, 27 fois), car le niveau 7 échouait aussi sans infection. Décision de Jérémy : 2 échecs d'affilée doivent suffire. Corrigé.

**Test de baisse, 2026-11-01, build `trial.7`, 11 min :** réussi, 7 actions, 0 anomalie. Infection débranchée à 16:41:12 : Entreprises 8→7→6→5→4 en 88 s. Rebranchée à 16:45:14 : 4→5→6→7 en 51 s. Niveaux finaux 7/9 et 4/5. **Remarque de Jérémy :** fonctionnel, mais trop lent partout.

**Limites connues de `v0.2.0-beta.1` :** une prévision certaine démentie n'est couverte qu'en simulation. Le mod compte sur le coup le plus faible observé : avec `Payload critique`, il peut rester sous un niveau qui réussit en pratique (7 au lieu de 8). Une anomalie arrête la régulation des deux types jusqu'au redémarrage. Plafonds et pauses : session uniquement. Vitesse × 5 : régulation suspendue. Toutes les mesures viennent d'une seule partie.

**Avant la validation de la bêta, décidé par Jérémy le 2026-11-01 :** changement de puissance contrôlé, rechargement d'une sauvegarde avec régulation active, session d'au moins une heure en profil équilibré, incompatibilités éventuelles avec ses autres mods.

Ensuite, si les essais réussissent : baisse automatique, ajustements successifs, anti-oscillation, deux nœuds, changements de puissance, session prolongée en profil équilibré. Aucun tag avant validation.

## Limites connues

- `failure_power` est une déduction : le jeu n'émet aucun événement d'échec. Il a été juste en jeu aux niveaux 3, 4 et 5, sans attaque furtive.
- Le modèle par salves ne couvre pas les attaques furtives. Les niveaux 7 et suivants n'ont jamais été joués.
- Les décisions simulées ne sont vérifiées en jeu que sur 2 propositions, confirmées par les changements du joueur.
- La vulnérabilité et les attaques furtives ne sont pas mesurées, faute de déblocage dans la partie.
- Avec une très grosse pile (dégâts par tick de l'ordre du double d'un coup), une salve pourrait ne plus être distinguée de l'infection.
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
