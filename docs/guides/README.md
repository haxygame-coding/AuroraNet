# Guides AuroraNet

Documentation pratique pour installer, rejoindre et exploiter AuroraNet.
Elle décrit la version **0.71.6** (novembre 2026) et le dépôt
`haxygame-coding/AuroraNet`.

AuroraNet est un réseau overlay basé sur WireGuard : un serveur de management
(distribué en Docker) coordonne des pairs, qui se parlent ensuite directement en
P2P ou via un relais. Le client est **en ligne de commande uniquement** : aucun
GUI n'est livré.

## Par où commencer ?

| Objectif | Guide |
| --- | --- |
| Héberger le serveur (DNS, TLS, Docker, sauvegardes) | [Serveur auto-hébergé](01-serveur.md) |
| Installer le client sur Debian, Ubuntu, Arch ou une autre distribution | [Client Linux](02-linux.md) |
| Installer le client sur Windows 10/11 | [Client Windows](03-windows.md) |
| Enrôler une machine dans un réseau avec une setup key | [Rejoindre un réseau](04-rejoindre-un-reseau.md) |
| Comprendre les fichiers de config, variables et options | [Configuration du client](05-configuration-client.md) |
| Diagnostiquer un problème | [Dépannage](06-depannage.md) |

Parcours type :

1. Installer le serveur et créer le premier compte administrateur.
2. Créer une **setup key** dans le dashboard.
3. Installer le client sur la machine à connecter.
4. Lancer `auroranet up` avec l'URL de management et la setup key.
5. Vérifier la présence du pair dans le dashboard, puis appliquer les politiques
   d'accès.

## Plateformes supportées

| Plateforme | Architecture | Artefact |
| --- | --- | --- |
| Linux — Debian/Ubuntu | amd64 | `.deb` |
| Linux — Arch | x86_64 | `.pkg.tar.zst` |
| Linux — autres distributions | amd64, arm64, 386 | `.tar.gz` |
| Windows 10/11 | x64 | `.msi` |
| Serveur | linux/amd64 | images Docker GHCR |

Ne sont **pas** supportés : macOS, FreeBSD, Linux armv6/armv7, Windows ARM et
les interfaces graphiques de bureau. Le script `install.sh` refuse explicitement
ces systèmes.

## Conventions utilisées dans les guides

- `<DOMAINE>` : le nom public du serveur, par exemple
  `vpn.dev.aurora-net.org`.
- `<CLE>` : la setup key copiée depuis le dashboard.
- Les commandes Linux sont à lancer en `root` ou précédées de `sudo`.
- Les commandes Windows sont à lancer dans **PowerShell en administrateur**.
- Les chemins et noms de service indiqués correspondent aux paquets officiels.
  Si vous avez installé le binaire manuellement, adaptez `/usr/local/bin`.

## Avertissements connus

- Le MSI Windows n'est **pas signé Authenticode** : SmartScreen affiche un
  avertissement. Vérifiez les sommes SHA-256 et la signature GPG de la release.
- Le client utilise par défaut `https://api.aurora-net.org`. Tant que ce nom ne
  résout pas vers votre serveur, passez **toujours** `--management-url`.
- Les archives `.tar.gz` du client sont produites par le pipeline de release :
  vérifiez leur présence dans les assets de la version téléchargée. Les paquets
  `.deb`, Arch et le MSI de la 0.71.6 sont, eux, publiés.
- Le script `release_files/install.sh` est un héritage : sur Debian/Ubuntu il
  configure encore un dépôt `pkgs.netbird.io` et tente d'installer une UI qui
  n'est plus publiée. Préférez les artefacts de release décrits dans ces guides.

## Documentation complémentaire

- [`packaging/README.md`](../../packaging/README.md) : matrice des artefacts et
  installation résumée.
- [`docs/agent-networks/`](../agent-networks/) : fonctionnement des réseaux
  d'agents.
- Le dashboard expose aussi une page **Setup Keys** et une page **Peers** qui
  restent la référence pour l'état réel du réseau.
