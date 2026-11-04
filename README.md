# Upload Labs – BreachPilot

[Français](#français) · [English](#english)

> Mod non officiel, sans lien avec EnigmaDev Studios. *Unofficial mod, not affiliated with EnigmaDev Studios.*

---

## Français

Mod de confort consacré au **hacking** d'[Upload Labs](https://store.steampowered.com/app/3606890/Upload_Labs/). Il règle le niveau de menace de vos nœuds d'infiltration sur le niveau le plus rentable, et un panneau de conseil vous propose le meilleur branchement de votre chaîne. Le mod respecte les mécaniques du jeu : il ne modifie ni les dégâts, ni les récompenses, ni les ressources, et ne crée rien gratuitement.

**Version actuelle : 0.6.0.** Interface en français et en anglais : le mod suit la langue du jeu, sans redémarrage.

### Fonctionnalités

**Auto Threat Manager : régulation de la menace** (désactivée par défaut)

- Règle chaque nœud d'infiltration (Entreprises, Gouvernement, Anonymous, Banque…) sur le niveau qui rapporte le plus par minute pour l'objectif choisi dans le panneau : XP, données, renseignements ou équilibré. Les niveaux élites sont pris en compte.
- Monte une fois au plus haut niveau débloqué quand il peut être gagné, pour ouvrir le suivant, puis revient au niveau rentable.
- Trois profils : conservateur, équilibré (par défaut), agressif. Après un essai de déblocage raté, le conservateur et l'équilibré attendent que la chance de gagner ait nettement augmenté. L'agressif réessaie de temps en temps.
- Les estimations viennent des attaques réellement observées sur votre chaîne : un nœud inconnu ou ajouté par un autre mod ne bloque rien. Tant que la mesure manque, la régulation vise le plus haut niveau qui tient.
- Sous les boutons du nœud : état de l'automatisation, `Pause` et `Reprendre`. Changer le niveau vous-même met ce type de nœud en pause pour la session.
- Protections : suspension à vitesse accélérée ou si l'option native du jeu est active, vérification après chaque changement de niveau, arrêt en cas d'anomalie, arrêt d'urgence `Ctrl+Alt+F10`.
- Les changements passent par les boutons du jeu (`level_up` / `level_down`) et sont enregistrés normalement dans la partie.

**Smart Hacking Advisor : conseiller en lecture seule**

- `Ctrl+Alt+F8`, ou le bouton `Conseil` (`Advice` en anglais) d'un nœud d'infiltration.
- Affiche d'abord le meilleur branchement pour l'objectif choisi, étape par étape, avec le gain estimé, les inconvénients et la fiabilité, puis l'achat conseillé.
- Section **« À essayer »** : nœuds sans puissance ou sans dégâts, sorties ou entrées libres, nœuds débloqués pas encore posés. Pas de chiffre tant que rien n'est mesuré.
- Le détail des calculs (branchements comparés, achats, niveaux) est dans une section repliable.
- Il ne fait qu'afficher : vous gardez la main sur vos branchements et vos achats.

### Compatibilité

| | Testé |
|---|---|
| Upload Labs | 3.0.12 (Steam, Windows) |
| Godot Mod Loader | 7.0.1, intégré au jeu |
| Autres mods | Smart GPU Manager, Smart Thread Manager, Better Splitters, Where Should I Connect?, Easy Tokens, ModManager |

Le mod n'étend aucun script du jeu. Au démarrage, il vérifie les fonctions du jeu dont il a besoin et se désactive proprement s'il en manque une. Linux et macOS n'ont pas été testés.

### Installation

**Depuis le Steam Workshop, méthode recommandée :** abonnez-vous à [BreachPilot sur le Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3833859813), puis lancez le jeu. Steam installe le mod et ses mises à jour.

**Depuis GitHub, en alternative** :

1. Téléchargez `Daneisra-BreachPilot-v<version>.zip` dans les [Releases](https://github.com/Daneisra/UploadLabs-BreachPilot/releases). Vous pouvez contrôler son empreinte SHA-256, indiquée à côté.
2. Ouvrez le dossier du jeu : dans Steam, clic droit sur Upload Labs, *Gérer*, *Parcourir les fichiers locaux*.
3. Créez un dossier `mods` à côté de `Upload Labs.exe` s'il n'existe pas, et copiez-y le zip **sans le décompresser**.
4. Lancez le jeu.

N'installez jamais deux copies du mod en même temps : si vous passez au Workshop, supprimez d'abord le zip du dossier `mods`, et si vous revenez à GitHub, désabonnez-vous d'abord.

### Activer la régulation

La régulation est **désactivée par défaut** : le mod observe et le conseiller fonctionne, mais aucun niveau n'est changé. Pour l'activer, mettez l'option `regulation_mode` sur `active`, par exemple avec le mod **ModManager** du Workshop. Les autres options :

| Option | Valeurs | Rôle |
|---|---|---|
| `regulation_mode` | `off` (défaut), `dry_run`, `active` | `dry_run` journalise les décisions sans agir |
| `regulation_profile` | `conservative`, `balanced` (défaut), `aggressive` | Prudence de la régulation |
| `max_allowed_level` | entier, `0` (défaut) = sans limite | Plus haut niveau visé |
| `min_level` | entier, `0` par défaut | Plus bas niveau visé |
| `log_level` | `debug`, `info` (défaut), `warning` | Détail du journal |

### Désinstallation

Supprimez le zip du dossier `mods`, ou désabonnez-vous sur le Workshop. Vos parties restent intactes : le mod n'écrit rien dans les sauvegardes, et les niveaux qu'il a choisis restent des niveaux normaux du jeu. Ses réglages sont dans `%APPDATA%\Upload Labs\mod_configs\Daneisra-BreachPilot`, que vous pouvez supprimer.

### Limites connues

- Interface en français et en anglais. Une autre langue du jeu donne l'interface anglaise. Après un changement de langue, le jeu laisse certains de ses propres textes dans l'ancienne langue jusqu'à son redémarrage : BreachPilot, lui, change aussitôt.
- Une nouvelle chaîne ou un nouveau nœud demande quelques attaques avant d'être chiffré : le panneau affiche alors « données insuffisantes ».
- Une anomalie (niveau inattendu, état incohérent) arrête la régulation de tous les nœuds jusqu'au redémarrage du jeu. C'est voulu, par prudence.
- Les achats sont comparés un par un : leurs gains ne s'additionnent pas.
- Le mod ne sait pas encore lire les emplacements libres d'un type de nœud déjà posé (par exemple « 1/3 »).
- Certaines mécaniques d'infection n'ont été mesurées que sur une chaîne : les estimations correspondantes sont moins sûres, et la fiabilité affichée le dit.
- Après une mise à jour du jeu, le mod peut se désactiver si une fonction attendue a changé. Le journal le signale.

### Journal et signalement d'un problème

Le journal est `%APPDATA%\Upload Labs\logs\modloader.log`, lignes `Daneisra-BreachPilot`. Pour signaler un problème, ouvrez une issue avec la version du jeu, la liste de vos mods et ces lignes du journal.

---

## English

A quality-of-life mod for **hacking** in [Upload Labs](https://store.steampowered.com/app/3606890/Upload_Labs/). It sets the threat level of your Breach nodes to the most profitable level, and an advisor panel suggests the best wiring for your chain. It plays by the game's rules: no damage, reward or resource is changed, and nothing is created for free.

**Current version: 0.6.0.** The interface is in English and French: the mod follows the game's language, without a restart.

### Features

**Auto Threat Manager: threat regulation** (off by default)

- Sets each Breach node (Corporations, Government, Anonymous, Bank…) to the level that pays most per minute for the objective chosen in the panel: XP, data, intel or balanced. Elite levels are taken into account.
- Climbs once to the highest unlocked level when it can be won, to open the next one, then returns to the profitable level.
- Three profiles: conservative, balanced (default), aggressive. After a failed unlock try, conservative and balanced wait until the chance of winning is clearly better. Aggressive retries from time to time.
- Estimates come from the attacks actually observed on your chain, so an unknown node or one added by another mod does not get in the way. Until the measurement is there, the regulation aims at the highest level that holds.
- Below the node's buttons: automation status, `Pause` and `Resume`. Changing a level yourself pauses that node type for the session.
- Safeguards: suspended at higher game speed or while the game's own auto level option is on, a check after every level change, a stop on any anomaly, and an emergency stop on `Ctrl+Alt+F10`.
- Changes go through the game's own level buttons (`level_up` / `level_down`) and are saved with your game as usual.

**Smart Hacking Advisor: read-only**

- `Ctrl+Alt+F8`, or the `Advice` button (`Conseil` in French) of a Breach node.
- Shows the best wiring for the chosen objective first, step by step, with the estimated gain, the drawbacks and how reliable it is, then the recommended purchase.
- **"Things to try"**: nodes without power or damage, free outputs or inputs, unlocked nodes not placed yet. No figure until something has been measured.
- The detailed figures (wirings compared, purchases, levels) are in a collapsible section.
- It only displays: your wiring and purchases stay in your hands.

### Compatibility

| | Tested |
|---|---|
| Upload Labs | 3.0.12 (Steam, Windows) |
| Godot Mod Loader | 7.0.1, bundled with the game |
| Other mods | Smart GPU Manager, Smart Thread Manager, Better Splitters, Where Should I Connect?, Easy Tokens, ModManager |

The mod extends no game script. At start-up it checks the game functions it relies on and disables itself cleanly if one is missing. Linux and macOS are untested.

### Installation

**From the Steam Workshop, recommended:** subscribe to [BreachPilot on the Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3833859813), then start the game. Steam installs the mod and its updates.

**From GitHub, as an alternative**:

1. Download `Daneisra-BreachPilot-v<version>.zip` from the [Releases](https://github.com/Daneisra/UploadLabs-BreachPilot/releases). Its SHA-256 checksum is listed next to it.
2. Open the game folder: in Steam, right-click Upload Labs, *Manage*, *Browse local files*.
3. Create a `mods` folder next to `Upload Labs.exe` if there is none, and copy the zip into it **without extracting it**.
4. Start the game.

Never install two copies of the mod at once: if you switch to the Workshop, delete the zip from the `mods` folder first, and if you go back to GitHub, unsubscribe first.

### Turning the regulation on

The regulation is **off by default**: the mod observes and the advisor works, but no level is changed. To turn it on, set the `regulation_mode` option to `active`, for example with the **ModManager** mod from the Workshop. Other options:

| Option | Values | Purpose |
|---|---|---|
| `regulation_mode` | `off` (default), `dry_run`, `active` | `dry_run` logs the decisions without acting |
| `regulation_profile` | `conservative`, `balanced` (default), `aggressive` | How cautious the regulation is |
| `max_allowed_level` | integer, `0` (default) = no limit | Highest level aimed at |
| `min_level` | integer, `0` by default | Lowest level aimed at |
| `log_level` | `debug`, `info` (default), `warning` | Log detail |

### Uninstalling

Delete the zip from the `mods` folder, or unsubscribe on the Workshop. Your saves stay intact: the mod writes nothing into them, and the levels it chose are ordinary game levels. Its settings live in `%APPDATA%\Upload Labs\mod_configs\Daneisra-BreachPilot`, which you may delete.

### Known limitations

- The interface is in English and French. Any other game language gives the English interface. After a language change, the game keeps some of its own texts in the former language until it restarts: BreachPilot switches at once.
- A new chain or node needs a few attacks before it gets figures; meanwhile the panel shows "données insuffisantes" (not enough data).
- An anomaly (unexpected level, inconsistent state) stops the regulation of every node until the game is restarted. This is deliberate, out of caution.
- Purchases are compared one at a time: their gains do not add up.
- The mod cannot read the free slots of a node type already placed yet (for example "1/3").
- Some infection mechanics were measured on one chain only: the related estimates are less certain, and the reliability shown says so.
- After a game update, the mod may disable itself if a function it relies on changed. The log says so.

### Log and bug reports

The log is `%APPDATA%\Upload Labs\logs\modloader.log`, lines starting with `Daneisra-BreachPilot`. To report a problem, open an issue with the game version, your mod list and those log lines.

---

## Développement · Development

- Construire l'archive / build the archive: `python tools/build_zip.py`, puis / then `python tools/verify_zip.py`.
- Tests: `godot --headless --path . --script tests/run_tests.gd`.
- [Changelog](CHANGELOG.md) · [Architecture](docs/ARCHITECTURE.md) · [Suivi du projet](docs/PROJECT_TRACKING.md) · [Publication](docs/PUBLISHING.md)

Ce dépôt ne contient aucun fichier du jeu, aucune sauvegarde et aucun secret. *This repository contains no game file, no save and no secret.*

## Licence · License

Le code et la documentation de BreachPilot sont publiés sous [licence MIT](LICENSE), © 2026 Daneisra. Cette licence ne porte que sur ce projet. Elle n'accorde aucun droit sur Upload Labs, son code, ses ressources graphiques ou sonores, ses données ni ses autres éléments protégés, qui appartiennent à EnigmaDev Studios. Le mod ne contient aucun de ces éléments : il lit l'état du jeu pendant l'exécution.

*BreachPilot's code and documentation are released under the [MIT License](LICENSE), © 2026 Daneisra. The license covers this project only. It grants no right on Upload Labs, its code, art, sound, data or any other protected element, which belong to EnigmaDev Studios. The mod contains none of them: it reads the game's state while it runs.*
