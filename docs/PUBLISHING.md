# Publication

Procédure de publication du mod, d'abord sur GitHub Releases, puis sur le Steam Workshop d'Upload Labs. Rien n'est publié sans l'accord de Daneisra.

## Avant chaque publication

1. Tests : `godot --headless --path . --script tests/run_tests.gd`, aucun échec.
2. `BUILD` (dans `mod_main.gd`) et `version_number` (dans `manifest.json`) portent la même version, sans suffixe `-dev`.
3. `python tools/build_zip.py`, puis `python tools/verify_zip.py`. Le second vérifie l'archive :
   - un seul dossier, `mods-unpacked/Daneisra-BreachPilot/` ;
   - exactement les fichiers du dossier du mod, sans tests, journaux, sauvegardes, données du jeu ni chemins privés ;
   - un manifeste valide, une régulation désactivée par défaut, une version de publication.

   Il écrit ensuite l'empreinte SHA-256 dans `build/<archive>.zip.sha256`.
4. Changelog daté, tag `vX.Y.Z` sur le commit publié.

## GitHub Releases

1. Pousser `main` et le tag.
2. Créer la Release sur le tag, avec pour titre `BreachPilot X.Y.Z`. Le texte reprend la section du changelog, l'empreinte SHA-256 et les liens d'installation du README.
3. Joindre `Daneisra-BreachPilot-vX.Y.Z.zip` et son fichier `.sha256`.

Avec l'outil `gh` :

```
gh release create vX.Y.Z build/Daneisra-BreachPilot-vX.Y.Z.zip build/Daneisra-BreachPilot-vX.Y.Z.zip.sha256 --title "BreachPilot X.Y.Z" --notes-file <notes>
```

Le dépôt doit être public pour que les joueurs voient la Release. Changer sa visibilité est une décision de Daneisra.

## Steam Workshop d'Upload Labs (app 3606890)

**Constaté sur l'installation de Daneisra, novembre 2026 :**

- Un objet du Workshop contient un zip du Godot Mod Loader, au même format que notre archive : `steamapps/workshop/content/3606890/<id>/<Namespace-Mod>.zip`.
- Le Mod Loader du jeu le charge directement depuis ce dossier, sans copie dans `mods`.
- Les mises à jour arrivent avec Steam.

**Envoi :** le jeu ne propose pas d'outil d'envoi. On reprend la méthode suivie pour Research Freedom, décrite dans le suivi de ce projet, section « Élément Steam Workshop » :

1. SteamCMD, avec le compte de Daneisra qui possède le jeu : `steamcmd +login <compte> +workshop_build_item <fichier.vdf> +quit`.
2. Création en **privé** (`visibility` 2), avec `publishedfileid` 0 au premier envoi.
3. Contenu : le **ZIP exact de la Release GitHub**, identique octet par octet, seul dans son dossier.
4. Aperçu : la vignette originale `docs/workshop/preview.png`.
5. Captures ajoutées ensuite depuis la page Steam.
6. Description : relue sur la page après l'envoi, et corrigée à la main si elle est coupée.
7. Catégorie `QOL` : SteamCMD ne pose pas les tags. Pour Research Freedom, elle a été posée par `ISteamUGC::SetItemTags`.
8. Vérification par un abonnement :
   - copie locale retirée ;
   - une seule entrée du mod dans le profil du Mod Loader ;
   - ZIP installé par Steam identique à celui de la Release ;
   - journal et régulation contrôlés.
9. Passage en public seulement après l'accord de Daneisra.

Le fichier `.vdf` :

```
"workshopitem"
{
  "appid" "3606890"
  "publishedfileid" "0"
  "contentfolder" "<dossier contenant uniquement le zip>"
  "previewfile" "<docs/workshop/preview.png>"
  "visibility" "2"
  "title" "BreachPilot – Hacking Automation & Advisor"
  "description" "<texte de docs/workshop, sans guillemet droit>"
  "changenote" "vX.Y.Z"
}
```

- Le premier envoi donne un `publishedfileid`. Il faut le reporter ici et dans le `.vdf` pour chaque mise à jour, sinon un nouvel objet est créé.
- **L'identifiant `3833196182` est celui de Research Freedom.** Il ne doit jamais servir pour BreachPilot.

**Contenu attendu :**

- Le dossier envoyé ne contient que `Daneisra-BreachPilot-vX.Y.Z.zip`.
- L'image de présentation se trouve dans `docs/workshop/preview.png`.
- La description, en BBCode Steam, se trouve dans `docs/workshop/description_en.txt` et `description_fr.txt`.
- Captures d'écran : à ajouter depuis la page de l'objet.

**Dépendances :** aucune. Le Mod Loader est intégré au jeu, et le manifeste ne déclare aucune dépendance. ModManager n'est utile que pour régler les options : il est recommandé dans la description, pas exigé.

**Double installation :**

- Un même identifiant `Daneisra-BreachPilot` présent à la fois dans `mods` et sur le Workshop donne deux copies du mod. Le Mod Loader n'en garde qu'une, et on ne sait pas laquelle.
- La description et le README demandent de ne garder qu'une source.
- Daneisra doit retirer son zip local avant de s'abonner à sa propre version du Workshop.

**Mises à jour :**

- Une nouvelle version garde le même identifiant de mod et le même `publishedfileid`.
- Le nom du zip change avec la version.
- Les options des joueurs, dans `mod_configs`, sont conservées.

## Licence

BreachPilot est publié sous licence MIT (`LICENSE`, © 2026 Daneisra), incluse dans l'archive. Elle ne couvre que le code et la documentation du projet, jamais le jeu ni ses éléments.

## Texte du VDF

Le lecteur de VDF de SteamCMD ne traite pas les séquences d'échappement : un guillemet droit, même écrit `\"`, termine la valeur et tronque la description. C'est arrivé avec Research Freedom. Les descriptions de `docs/workshop/` n'utilisent que des guillemets typographiques. Le fichier VDF doit être vérifié sans aucun guillemet droit à l'intérieur d'une valeur, avant tout envoi.

## Droits et redistribution

Ces points résument l'avis demandé en novembre 2026 avant la décision d'architecture générique. Ce n'est pas un avis juridique.

- **Contenu du mod :** il ne contient que du code original. Il lit pendant l'exécution les propriétés que le jeu expose, et observe les attaques. Aucun code, asset, texte ou table du jeu n'est recopié dans le dépôt ni dans l'archive.
- **Observation :** l'observation et l'étude du fonctionnement d'un logiciel par son utilisateur légitime sont encadrées par la directive européenne 2009/24/CE, article 5(3). La décompilation relève de l'article 6, plus restrictif. Le projet a renoncé à toute décompilation.
- **Règles écrites :** les quelques règles mesurées écrites dans le mod (partage de puissance, délai de l'infection) sont des observations rédigées par nous, pas des données du jeu.
- **Steam :** l'accord de souscription Steam et les conditions du Workshop s'appliquent à l'envoi. En publiant, l'auteur accorde à Valve et aux joueurs les droits d'utilisation prévus par le Workshop.
- **Éditeur :** EnigmaDev Studios accepte les mods de fait, avec un Workshop ouvert et un Mod Loader intégré au jeu. Aucune règle écrite propre aux mods n'a été trouvée sur leurs pages publiques. Le projet ne contacte pas l'éditeur.
- **Nom et image :** le mod se présente comme non officiel. Il n'utilise ni le logo ni les illustrations du jeu.

Références : [directive 2009/24/CE](https://eur-lex.europa.eu/legal-content/FR/TXT/?uri=CELEX:32009L0024), [accord de souscription Steam](https://store.steampowered.com/subscriber_agreement/french/).
