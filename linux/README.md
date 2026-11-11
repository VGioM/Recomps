# Recomps pour Linux

La version Linux de Recomps : même catalogue (recomplauncher.com), mêmes filtres,
mêmes téléchargements depuis les releases GitHub ou GitLab de chaque projet, même
suivi des versions. Écrite en Electron (l'app Mac est en SwiftUI, qui n'existe pas
sur Linux), distribuée en AppImage.

## Installer

Télécharger `Recomps-<version>-linux-x86_64.AppImage` dans les
[releases](https://github.com/VGioM/Recomps/releases), le rendre exécutable
(`chmod +x`, ou Propriétés → Autoriser l'exécution) et le lancer. Ensuite, l'app
vérifie elle-même au lancement s'il existe une nouvelle version et remplace son
AppImage (menu Aide → « Rechercher les mises à jour… »).

## Ce qui change par rapport au Mac

- **Jeux Linux prêts à lancer.** Pour le système Linux, l'archive (`.zip`, `.tar.gz`,
  `.tar.xz`, `.7z`) est décompressée dans `<dossier Linux>/<jeu>/<nom de l'archive>/`
  et ses programmes rendus exécutables ; une AppImage est rendue exécutable. Le bouton
  **Lancer** de la fiche démarre le jeu (l'AppImage, ou le programme principal trouvé
  dans le dossier).
- Les fichiers Windows et Mac restent tels quels dans leur dossier (une `.dmg` ne
  s'ouvre pas sous Linux).
- Le bouton rapide propose d'abord **Linux** (sur Mac : Mac).
- Les anciennes versions vont à la corbeille du bureau ; « Afficher dans le dossier »
  ouvre le gestionnaire de fichiers.
- Données : `~/.config/Recomps/` (`settings.json`, `installed.json`, catalogue et notes
  en cache).
- Ctrl+R actualise, Ctrl+F cherche, Échap ferme la fiche.

## Développer

```sh
cd linux
npm install
npm start            # lance l'app depuis les sources
npm test             # tests unitaires (node --test)
npm run dist         # dist/Recomps-<version>-linux-x86_64.AppImage
```

`src/shared.js` porte la logique (versions, modèles de fichiers, état de chaque jeu,
filtres) : c'est la traduction de `App/main.swift`, chargée à la fois par le processus
principal (`src/main.js`) et par l'interface (`src/renderer/`). `src/selfupdate.js` est
l'équivalent de `SelfUpdate.swift`, le même fichier dans Biblifilm, Biblijeu et Recomps.

## Publier

```sh
./release.sh 1.4.0          # sur main, sur un Mac : la release et le zip macOS
cd linux && ./release-linux.sh 1.4.0   # ici : ajoute l'AppImage à cette release
```

La version Mac ne prend que le fichier marqué `macOS`, la version Linux que
`-linux-x86_64.AppImage` : les deux vivent dans la même release sans se gêner.
L'AppImage remplacée est vérifiée avec l'empreinte SHA-256 que GitHub publie pour
chaque fichier.
