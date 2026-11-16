# Recomps pour Windows

La version Windows de Recomps : même catalogue (recomplauncher.com), mêmes filtres,
mêmes téléchargements depuis les releases GitHub ou GitLab de chaque projet, même
suivi des versions. Une application native en Rust ([egui](https://github.com/emilk/egui)),
tirée de la version Linux, distribuée en zip portable.

## Installer

Télécharger `Recomps-<version>-windows-x64.zip` dans les
[releases](https://github.com/VGioM/Recomps/releases), le décompresser où l'on veut
(par exemple `C:\Apps\Recomps`) et lancer `Recomps.exe`. Ensuite, l'app vérifie
elle-même au lancement s'il existe une nouvelle version et se remplace (menu ··· →
Rechercher les mises à jour…).

## Ce qui change par rapport au Mac et à Linux

- **Jeux Windows prêts à lancer.** Pour le système Windows, l'archive (`.zip`,
  `.tar.*`, `.7z`) est décompressée dans `<dossier Windows>/<jeu>/<nom de l'archive>/`
  avec le `tar` de Windows (7-Zip en secours, s'il est installé). Le bouton **Lancer**
  de la fiche démarre le `.exe` principal trouvé dans le dossier.
- Le bouton rapide propose d'abord **Windows**.
- Les anciennes versions vont à la Corbeille ; « Afficher dans le dossier » ouvre
  l'Explorateur, le fichier sélectionné.
- Données : `%APPDATA%\Recomps\` (`settings.json`, `installed.json`, catalogue et notes
  en cache).
- Ctrl+R actualise, Ctrl+F cherche, Échap ferme la fiche.

## Développer

Il faut Rust stable (cible `x86_64-pc-windows-msvc`, avec les Build Tools de Visual
Studio). Dans `windows/` :

```sh
cargo run --release      # lance l'app
cargo test               # tests unitaires
./build-windows.sh       # dist/Recomps-<version>-windows-x64.zip
```

`build-windows.sh` compile, renomme l'exe en `Recomps.exe` (l'icône est intégrée par
`build.rs` depuis `resources/icon.ico`) et fait le zip que la mise à jour intégrée
cherche dans les releases : un fichier `-windows-x64.zip` par release, à côté du zip
Mac et de l'AppImage Linux.

`src/common/` est le même dossier dans Biblifilm, Biblijeu et Recomps : thème, icônes,
images, réglages, mise à jour intégrée et accès au bureau Windows (`sys.rs`).
