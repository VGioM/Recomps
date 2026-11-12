# Recomps pour Linux

La version Linux de Recomps : même catalogue (recomplauncher.com), mêmes filtres,
mêmes téléchargements depuis les releases GitHub ou GitLab de chaque projet, même
suivi des versions. Une application native en Rust (l'app Mac est en SwiftUI, qui
n'existe pas sur Linux), distribuée en AppImage d'environ 6 Mo.

## Installer

Télécharger `Recomps-<version>-linux-x86_64.AppImage` dans les
[releases](https://github.com/VGioM/Recomps/releases), le rendre exécutable
(`chmod +x`, ou Propriétés → Autoriser l'exécution) et le lancer. Ensuite, l'app
vérifie elle-même au lancement s'il existe une nouvelle version et remplace son
AppImage.

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
  en cache) — les mêmes fichiers que la première version Linux, repris tels quels.
- Ctrl+R actualise, Ctrl+F cherche, Échap ferme la fiche.

## Développer

Une application Rust native ([egui](https://github.com/emilk/egui), rendu OpenGL,
Wayland et X11). Il faut Rust stable, et pour l'AppImage une Fedora — sur un système
immuable (Bazzite, Silverblue, Kinoite), un conteneur toolbox Fedora fait l'affaire :

```sh
toolbox create -c rustbuild --distro fedora --release 44
toolbox enter rustbuild
sudo dnf install -y gcc pkgconf-pkg-config squashfs-tools patchelf \
    wayland-devel libxkbcommon-devel libxkbcommon-x11 libX11-devel libXcursor libXrandr libXi mesa-libEGL-devel
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh    # Rust, si absent
```

Puis, dans `linux/` :

```sh
cargo run --release      # lance l'app
cargo test               # tests unitaires
./build-appimage.sh      # dist/Recomps-<version>-linux-x86_64.AppImage
```

`build-appimage.sh` compile, copie dans l'AppImage les bibliothèques dont le programme
a besoin — jamais la glibc, les pilotes graphiques, le son ni les bibliothèques de
base du bureau, qui restent celles du système — et la compresse (squashfs xz). Le
« runtime » AppImage placé en tête est pris dans `APPIMAGE_RUNTIME` (par défaut : celui
qu'electron-builder a mis en cache).

`src/common/` est le même dossier dans Biblifilm, Biblijeu et Recomps : thème, icônes,
cache des jaquettes (disque `~/.cache/Recomps/`, mémoire bornée), fenêtres de choix
(portail XDG), réglages, mise à jour intégrée (`selfupdate.rs`, l'équivalent de
`SelfUpdate.swift` : elle ne prend que le fichier `-linux-x86_64.AppImage` de la
release, vérifie son empreinte SHA-256 publiée par GitHub, puis remplace l'AppImage).

## Publier

```sh
cd linux && ./release-linux.sh 1.4.0    # l'AppImage, dans la release v1.4.0 (créée si besoin)
```

Mac et Linux partagent les releases du dépôt, pas leurs numéros : une release peut
contenir le zip Mac, l'AppImage, ou les deux. Chaque version ne prend que son fichier
(`-macOS-arm64.zip` ou `-linux-x86_64.AppImage`) et se met à jour vers la release la
plus récente qui le contient ; une release Mac seule ne cache pas une version Linux,
et inversement. Un numéro (un tag) ne sert qu'une fois.
