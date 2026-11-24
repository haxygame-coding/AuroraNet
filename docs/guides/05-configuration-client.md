# Configuration du client

Le client lit sa configuration depuis un fichier JSON, des variables
d'environnement et des options de ligne de commande. Le démon applique la
configuration ; la CLI lui envoie des demandes via un socket local.

## Fichiers et chemins

| Élément | Linux | Windows |
| --- | --- | --- |
| Configuration | `/etc/auroranet/config.json` | `C:\ProgramData\AuroraNet\config.json` |
| Logs | `/var/log/auroranet/client.log` | `C:\ProgramData\AuroraNet\client.log` |
| Socket du démon | `/var/run/auroranet.sock` | named pipe `auroranet` |
| Service | `auroranet` (systemd) | `AuroraNet` |

L'option `--config` permet de pointer vers un autre fichier. Sur Windows, le MSI
passe explicitement `C:\ProgramData\AuroraNet\config.json` au service.

Ne modifiez pas le fichier à chaud : arrêtez le service, sauvegardez, éditez,
puis redémarrez. Préférez les commandes `auroranet up` / `auroranet down`, qui
maintiennent la cohérence.

## Options principales

Options globales utilisables avant ou après la sous-commande :

| Option | Rôle |
| --- | --- |
| `-m`, `--management-url` | URL du serveur de management |
| `-k`, `--setup-key` | Setup key d'enrôlement |
| `--setup-key-file` | Chemin d'un fichier contenant la clé (exclusif avec `-k`) |
| `-n`, `--hostname` | Nom du pair dans le dashboard |
| `-c`, `--config` | Chemin du fichier de configuration |
| `--daemon-addr` | Adresse du démon local |
| `-l`, `--log-level` | `trace`, `debug`, `info`, `warn`, `error` |
| `--log-file` | Fichier(s) de log, `console` ou `syslog` |
| `-s`, `--service` | Nom du service (défaut `auroranet`, `AuroraNet` sous Windows) |
| `--anonymize` | Anonymise IP/MAC/domaines dans les logs et `status` |
| `--anonymize-level` | `default` ou `strict` |

Options spécifiques à `up` :

| Option | Rôle |
| --- | --- |
| `-F`, `--foreground-mode` | Lance le démon au premier plan |
| `--interface-name` | Nom de l'interface WireGuard |
| `--wireguard-port` | Port d'écoute WireGuard local |
| `--mtu` | MTU de l'interface |
| `--disable-auto-connect` | Ne pas se reconnecter au démarrage du service |
| `--network-monitor` | Surveillance réseau (activée par défaut sous Windows) |
| `--extra-dns-labels` | Labels DNS supplémentaires (32 max) |
| `--external-ip-map` | Mappage d'IP publiques/privées |
| `--dns-resolver-address` | Adresse du resolver DNS local |
| `--enable-local-metrics` | Endpoint Prometheus local |
| `--no-browser` | Ne pas ouvrir le navigateur pour le SSO |
| `--qr` | Afficher un QR code pour le SSO |

Exemple :

```bash
sudo auroranet up \
  --management-url https://vpn.dev.aurora-net.org \
  --setup-key-file /root/aurora.key \
  --hostname passerelle \
  --wireguard-port 51821 \
  --mtu 1280 \
  --disable-auto-connect
```

## Variables d'environnement

Chaque option peut être fournie par une variable préfixée `NB_` (ou `WT_` pour
la compatibilité historique), en majuscules et avec des underscores :

| Option | Variable |
| --- | --- |
| `--management-url` | `NB_MANAGEMENT_URL` |
| `--setup-key` | `NB_SETUP_KEY` |
| `--hostname` | `NB_HOSTNAME` |
| `--config` | `NB_CONFIG` |
| `--log-level` | `NB_LOG_LEVEL` |
| `--wireguard-port` | `NB_WIREGUARD_PORT` |
| `--mtu` | `NB_MTU` |
| `--disable-auto-connect` | `NB_DISABLE_AUTO_CONNECT` |
| `--interface-name` | `NB_INTERFACE_NAME` |
| `--extra-dns-labels` | `NB_EXTRA_DNS_LABELS` |

Exemple :

```bash
export NB_MANAGEMENT_URL=https://vpn.dev.aurora-net.org
export NB_SETUP_KEY='<CLE>'
sudo -E auroranet up
```

Évitez de définir à la fois la variable et l'option : le comportement de
priorité dépend de l'ordre d'application et prête à confusion.

Pour le service systemd, les variables peuvent être persistées dans
`/etc/default/auroranet` (référencé par l'unité) ou via :

```bash
sudo auroranet service install --service-env NB_LOG_LEVEL=debug
```

## Profils

Les profils permettent de conserver plusieurs configurations (par exemple un
réseau de production et un réseau de test) :

```bash
auroranet profile list
auroranet profile add lab
auroranet profile select lab
auroranet profile remove lab
```

Le profil actif est utilisé par `up`, `status` et les autres commandes. Le
détail des options est disponible avec `auroranet profile --help`.

## DNS et résolution des pairs

- Le domaine interne est défini côté serveur (`AURORANET_MGMT_DNS_DOMAIN`,
  `auroranet.selfhosted` par défaut).
- Les noms prennent la forme `<hostname>.<domaine>`.
- `--extra-dns-labels` ajoute des labels pour des cas multi-réseaux.
- Si un resolver local entre en conflit, testez avec `nslookup` et vérifiez que
  le client a bien installé ses règles DNS.
- Pour désactiver la gestion DNS côté client, utilisez les réglages du profil
  ou l'option correspondante de `auroranet up` (voir `auroranet up --help`).

## Réseaux et routes

```bash
auroranet networks                 # équivaut à `networks list`
auroranet networks list
auroranet networks select <NOM>    # remplace la sélection courante
auroranet networks select -a <NOM> # ajoute à la sélection
auroranet networks select all      # accepte tous les réseaux, y compris futurs
auroranet networks deselect <NOM>
auroranet networks deselect all    # n'accepte plus aucun réseau
```

Ces commandes choisissent les réseaux (et leurs routes) proposés par le serveur :
réseaux d'entreprise, sous-réseaux, ressources. `select all` accepte aussi les
réseaux créés plus tard ; `deselect all` coupe l'accès à tous les réseaux
optionnels. L'alias historique `auroranet routes` existe encore.

## SSH, exposition et posture

- `auroranet ssh` ouvre une session SSH vers un pair via le tunnel.
- `auroranet expose` publie un service local via le proxy AuroraNet (si le
  serveur a été installé avec `AURORANET_ENABLE_PROXY=true`).
- `auroranet posture` envoie les informations de posture demandées par le
  serveur.

Ces fonctions dépendent de la configuration du serveur et des politiques.

## Journalisation et diagnostic

```bash
auroranet status -d
auroranet debug bundle          # archive de diagnostic
auroranet debug log --help
auroranet debug log level debug
```

Le bundle de debug contient la configuration, les logs et l'état réseau. Il peut
contenir des adresses IP et des noms de pairs : utilisez `--anonymize` si vous
le partagez.

## Sauvegarde de la configuration

- **Linux** : sauvegardez `/etc/auroranet/config.json` (et le profil actif dans
  `/etc/auroranet/`).
- **Windows** : sauvegardez `C:\ProgramData\AuroraNet\config.json`.

La configuration contient la clé privée WireGuard et éventuellement des secrets :
traitez-la comme un fichier sensible (`chmod 600` sous Linux, ACL restrictives
sous Windows).

## Réinitialiser un client

```bash
sudo auroranet down
sudo auroranet service stop
sudo rm -rf /etc/auroranet
sudo auroranet service start
```

Sous Windows :

```powershell
auroranet down
Stop-Service AuroraNet
Remove-Item -Recurse -Force "C:\ProgramData\AuroraNet"
Start-Service AuroraNet
```

Vous devrez ensuite ré-enrôler la machine avec une nouvelle setup key.
