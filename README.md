# Recomps

Petite app macOS (SwiftUI, un seul fichier) pour parcourir les recomps PC listés sur [recomplauncher.com](https://recomplauncher.com/all) :

- recherche (nom, jeu d'origine, auteur, tags) et filtres par console, genre et système (Windows, Mac, Linux) ;
- tri par nom, dernière version, ajout au catalogue ou popularité ;
- téléchargement des builds Windows, Mac ou Linux depuis les releases GitHub de chaque projet, avec vérification SHA-256 quand le catalogue la donne ;
- état de chaque jeu : **à jour**, **mise à jour disponible** ou absent, d'après ce qui a été téléchargé ici et les fichiers déjà présents dans le dossier de bibliothèque.

## Construire

```sh
./build.sh          # dist/Recomps.app
./build.sh install  # et copie dans /Applications
```

Swift 5.9+ (Xcode ou Command Line Tools), macOS 14 ou plus.

## Fonctionnement

- Catalogue : `https://recomplauncher.com/pc-catalog.json`, le fichier que le site lit lui-même, gardé en cache (`~/Library/Application Support/Recomps/`) et rechargé seulement s'il a changé (ETag).
- Fichiers : `github.com/<dépôt>/releases/download/<tag>/<fichier>` quand le catalogue nomme le fichier ; sinon le modèle du catalogue (`Nom-*-macOS.zip`) est cherché dans la release via l'API GitHub (sans compte : 60 requêtes par heure).
- Les téléchargements vont dans `<bibliothèque>/<nom du jeu>/` (par défaut `~/Downloads/Recomps`, à changer en bas de la barre latérale). Une nouvelle version remplace l'ancienne téléchargée ici ; l'ancienne va à la corbeille.
- Jeux déjà présents : l'app cherche dans la bibliothèque (3 niveaux) les archives ou dossiers dont le nom suit le modèle du jeu. Si le nom contient la version, elle est comparée à la dernière ; sinon, c'est la date du fichier qui est comparée à celle de la release.
