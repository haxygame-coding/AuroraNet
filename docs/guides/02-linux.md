# Client Linux

Le client AuroraNet installe un binaire `auroranet`, un démon local et, via le
paquet, un service systemd. Il n'y a pas d'interface graphique.

## Plateformes couvertes

| Distribution | Architecture | Artefact |
| --- | --- | --- |
| Debian / Ubuntu | amd64 | `auroranet_<VERSION>_amd64.deb` |
| Arch Linux | x86_64 | `auroranet-<VERSION>-1-x86_64.pkg.tar.zst` |
| Autres distributions | amd64, arm64, 386 | `auroranet_<VERSION>_linux_<ARCH>.tar.gz` |

macOS, FreeBSD et Linux armv6/armv7 ne sont pas supportés.

## Prérequis

- Noyau avec TUN activé (`/dev/net/tun`).
- systemd pour le service (ou lancer le démon manuellement).
- Accès `root` / `sudo`.
- Sortie réseau autorisée vers le serveur sur **443/tcp** et **3478/udp**.

Vérifiez TUN :

```bash
ls -l /dev/net/tun
```

Si le fichier n'existe pas, chargez le module :

```bash
sudo modprobe tun
```

## Installation

### Debian / Ubuntu

Téléchargez le `.deb` depuis la release GitHub, puis :

```bash
sudo apt install ./auroranet_0.71.6_amd64.deb
```

Le post-installation enregistre et démarre le service `auroranet`.

### Arch Linux

```bash
sudo pacman -U auroranet-0.71.6-1-x86_64.pkg.tar.zst
```

Le hook `post_install` installe et démarre le service.

### Archive binaire (autres distributions)

```bash
tar -xzf auroranet_0.71.6_linux_amd64.tar.gz
sudo install -m 0755 auroranet /usr/local/bin/auroranet
sudo auroranet service install
sudo auroranet service start
```

Remplacez `amd64` par `arm64` ou `386` selon la machine. Les archives `.tar.gz`
sont générées par le pipeline de release : si elles ne sont pas présentes dans
les assets de la version visée, utilisez le `.deb`, le paquet Arch ou attendez
la release suivante.

> **Script `install.sh` historique** : sur Debian/Ubuntu, il ajoute encore le
> dépôt `pkgs.netbird.io` et tente d'installer une UI qui n'est plus publiée.
> Préférez les artefacts ci-dessus. Si vous devez vraiment l'utiliser, forcez
> l'installation binaire et désactivez l'UI :
> `USE_BIN_INSTALL=true SKIP_UI_APP=true ... ./install.sh`.

## Vérifier l'installation

```bash
auroranet version
systemctl status auroranet
```

Emplacements par défaut :

| Élément | Chemin |
| --- | --- |
| Binaire | `/usr/bin/auroranet` (paquet) ou `/usr/local/bin/auroranet` |
| Configuration | `/etc/auroranet/config.json` |
| Logs | `/var/log/auroranet/client.log` |
| Socket du démon | `/var/run/auroranet.sock` |
| Service | `auroranet.service` |

Le service est de type `simple` et redémarre en cas d'échec
(`Restart=on-failure`). Son unité est fournie dans
`release_files/systemd/auroranet@.service` pour les installations multi-profils.

## Rejoindre un réseau

```bash
sudo auroranet up \
  --management-url https://vpn.dev.aurora-net.org \
  --setup-key <CLE>
```

`--management-url` est indispensable tant que le défaut compilé
(`https://api.aurora-net.org`) ne pointe pas vers votre serveur.

Variantes utiles :

```bash
# Nom d'hôte personnalisé
sudo auroranet up -m https://vpn.dev.aurora-net.org -k <CLE> --hostname serveur-web

# Clé lue depuis un fichier (évite l'historique du shell)
sudo auroranet up -m https://vpn.dev.aurora-net.org --setup-key-file /root/aurora.key

# Connexion SSO dans le navigateur, sans setup key
sudo auroranet up -m https://vpn.dev.aurora-net.org

# Machine sans navigateur ou sans affichage
sudo auroranet up -m https://vpn.dev.aurora-net.org --no-browser
# ou afficher un QR code à scanner
sudo auroranet up -m https://vpn.dev.aurora-net.org --qr
```

Le détail du processus d'enrôlement est dans
[Rejoindre un réseau](04-rejoindre-un-reseau.md).

## État et diagnostic

```bash
auroranet status              # résumé management / signal / pairs
auroranet status -d           # détail
auroranet status -j           # JSON
auroranet status --check ready
auroranet networks            # réseaux et routes proposés par le serveur
```

`auroranet status --check ready` renvoie un code de sortie 0 si le pair est
prêt, ce qui est pratique en script ou en healthcheck.

Logs :

```bash
sudo journalctl -u auroranet -f
sudo tail -f /var/log/auroranet/client.log
```

## Gérer le service

```bash
sudo systemctl start auroranet
sudo systemctl stop auroranet
sudo systemctl restart auroranet
sudo systemctl disable auroranet
sudo auroranet service status
```

Le démon conserve la configuration et se reconnecte au démarrage. Pour empêcher
la reconnexion automatique, utilisez `--disable-auto-connect` lors du `up`, ou
`auroranet down`.

## Mettre à jour

- **Debian/Ubuntu** : téléchargez le nouveau `.deb` puis
  `sudo apt install ./auroranet_<VERSION>_amd64.deb`.
- **Arch** : `sudo pacman -U auroranet-<VERSION>-1-x86_64.pkg.tar.zst`.
- **Archive** : remplacez le binaire, puis
  `sudo auroranet service restart`.

Après mise à jour, vérifiez `auroranet version` et `auroranet status`.

## Désinstaller

```bash
# Debian / Ubuntu
sudo apt remove auroranet

# Arch
sudo pacman -R auroranet

# Archive binaire
sudo auroranet service stop
sudo auroranet service uninstall
sudo rm /usr/local/bin/auroranet
```

La configuration et les logs peuvent rester dans `/etc/auroranet` et
`/var/log/auroranet`. Supprimez-les manuellement si vous ne voulez pas les
réutiliser.

## Cas particuliers

- **Serveur sans GUI** : tout fonctionne en SSH ; utilisez `--no-browser` ou
  `--qr` pour le SSO.
- **Plusieurs réseaux** : les profils permettent de garder plusieurs
  configurations (`auroranet profile --help`).
- **Port WireGuard occupé** : changez le port local avec `--wireguard-port`.
- **MTU / PMTU** : si certains flux TCP se bloquent, testez `--mtu 1280`.
- **DNS système** : AuroraNet peut modifier la résolution ; en cas de conflit,
  voir [Dépannage](06-depannage.md).

Pour les options détaillées, voir
[Configuration du client](05-configuration-client.md).
