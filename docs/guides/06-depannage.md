# Dépannage

Ce guide couvre les pannes les plus courantes. Commencez par identifier la couche
en cause : DNS/TLS, serveur, démon local, enrôlement, puis connectivité entre
pairs.

## Triage rapide

| Symptôme | Couche | Première vérification |
| --- | --- | --- |
| `curl: (6) Could not resolve host` | DNS | `dig +short <DOMAINE>` |
| `curl: (7) Connection refused` | ports / serveur arrêté | `docker compose ps`, pare-feu |
| certificat invalide ou expiré | TLS / ACME | logs Traefik, port 80 |
| `failed to connect to daemon` | démon local | `systemctl status auroranet` |
| `context deadline exceeded` | management injoignable | `curl -I https://<DOMAINE>` |
| `setup key is invalid` | enrôlement | clé révoquée/expirée |
| pair `Connected` mais pas de ping | politiques / routes | dashboard, `auroranet networks` |
| connexion lente ou instable | NAT / relais | `auroranet status -d` |

## Serveur

### Le domaine ne résout pas

```bash
dig +short vpn.dev.aurora-net.org
```

- Vérifiez l'enregistrement `A` (et `AAAA` si IPv6).
- Chez Cloudflare, désactivez le proxy (nuage gris).
- Attendez la propagation DNS (TTL).

### Le port 80 ou 443 est fermé

```bash
sudo ss -lntp | grep -E ':80|:443'
curl -I http://vpn.dev.aurora-net.org
```

Ouvrez les ports dans le pare-feu de l'hôte **et** chez le fournisseur cloud
(security group / firewall réseau).

### Le certificat n'est pas émis

```bash
cd ~/auroranet
sudo docker compose logs --tail=200 auroranet-traefik
```

Causes fréquentes :

- port 80 inaccessible depuis Internet ;
- proxy Cloudflare activé ;
- domaine mal orthographié ou pointant ailleurs ;
- quota Let's Encrypt atteint (réessayez plus tard).

### Le dashboard répond mais pas l'API / le signal

Vérifiez que le routage du domaine couvre `/api`, `/oauth2`, `/relay`,
`/ws-proxy/` et les chemins gRPC. Avec Traefik intégré, c'est automatique ; avec
un reverse proxy externe, comparez votre configuration aux fichiers générés
(`nginx-auroranet.conf`, `caddyfile-auroranet.txt`,
`npm-advanced-config.txt`).

### Les conteneurs redémarrent en boucle

```bash
sudo docker compose ps
sudo docker compose logs --tail=200 auroranet-server
sudo docker compose logs --tail=200 auroranet-dashboard
```

Vérifiez les permissions des fichiers (`config.yaml` lisible par le conteneur),
la validité de `config.yaml` et l'espace disque (`df -h`).

### Les pairs se connectent mais le trafic est lent

- Vérifiez que **3478/udp** est ouvert : sans STUN/TURN, les pairs passent par
  le relais.
- Derrière un NAT, renseignez `AURORANET_TURN_EXTERNAL_IP`.
- `auroranet status -d` indique si la connexion est `P2P` ou `Relayed`.

## Linux

### Le service ne démarre pas

```bash
systemctl status auroranet
sudo journalctl -u auroranet -n 100 --no-pager
```

Causes fréquentes : binaire absent, configuration illisible, port occupé,
interface TUN indisponible.

### `failed to connect to daemon`

Le service est arrêté ou le socket a changé :

```bash
sudo systemctl start auroranet
ls -l /var/run/auroranet.sock
```

Si vous avez changé `--daemon-addr` ou le nom du service, utilisez la même
valeur pour la CLI.

### `/dev/net/tun` absent

```bash
sudo modprobe tun
ls -l /dev/net/tun
```

Dans un conteneur, ajoutez `--device /dev/net/tun --cap-add NET_ADMIN`.

### Conflit de DNS

Si la résolution Internet casse après `auroranet up` :

```bash
resolvectl status
cat /etc/resolv.conf
```

Arrêtez le client (`auroranet down`) pour confirmer la cause, puis vérifiez les
options DNS du profil et du serveur.

### Port WireGuard déjà utilisé

```bash
sudo ss -lunp | grep 51820
```

Changez le port local :

```bash
sudo auroranet up ... --wireguard-port 51821
```

### MTU / paquets perdus

Si les petits paquets passent mais pas les gros (SSH qui se bloque, pages web
incomplètes), testez :

```bash
sudo auroranet up ... --mtu 1280
```

## Windows

### `auroranet` n'est pas reconnu

Le MSI n'ajoute pas le dossier au PATH. Utilisez :

```powershell
& "C:\Program Files\AuroraNet\auroranet.exe" status
```

ou ajoutez `C:\Program Files\AuroraNet` au PATH (voir
[Client Windows](03-windows.md)).

### Le service ne démarre pas

```powershell
Get-Service AuroraNet
Get-EventLog -LogName Application -Source AuroraNet -Newest 20
```

Vérifiez que `wintun.dll` est présent dans `C:\Program Files\AuroraNet`, que le
service tourne en LocalSystem et qu'aucun antivirus ne bloque le pilote.

### Le client reste `Connecting`

- Vérifiez l'heure Windows (décalage TLS).
- Testez `curl.exe -I https://<DOMAINE>` dans PowerShell.
- Un proxy d'entreprise qui intercepte TLS peut nécessiter l'import du
  certificat racine.
- Vérifiez que le port 443 sortant n'est pas filtré.

### Supprimer une configuration corrompue

```powershell
Stop-Service AuroraNet
Remove-Item -Recurse -Force "C:\ProgramData\AuroraNet"
Start-Service AuroraNet
```

Puis ré-enrôlez la machine.

## Enrôlement

### `setup key is invalid`

- La clé a peut-être expiré ou été révoquée.
- Vérifiez qu'elle a été copiée en entier, sans espace ni retour à la ligne.
- Une clé `Ephemeral` ne peut servir qu'une fois.

### `context deadline exceeded`

Le client n'atteint pas le management :

```bash
curl -v https://vpn.dev.aurora-net.org/api/health
```

Vérifiez DNS, port 443, certificat et éventuel proxy.

### `x509: certificate signed by unknown authority`

Un proxy TLS d'entreprise intercepte la connexion. Importez son certificat
racine dans le magasin de la machine, ou utilisez un réseau non filtré.

### Le pair apparaît deux fois

Une ancienne configuration locale a été réutilisée. Supprimez le pair en double
dans le dashboard, réinitialisez la configuration locale, puis ré-enrôlez.

## Connectivité entre pairs

```bash
auroranet status -d
ping 100.x.y.z
auroranet networks
```

- `Relayed` est normal si le NAT est restrictif ; le trafic fonctionne mais avec
  plus de latence.
- Si le ping échoue, vérifiez les politiques d'accès et les groupes.
- Si seuls certains réseaux/routes manquent, vérifiez la sélection avec
  `auroranet networks list`, puis `auroranet networks select <NOM>` ou
  `auroranet networks select all`.
- Un pare-feu local peut bloquer l'interface overlay : autorisez le trafic
  entrant sur l'interface AuroraNet.

## Collecter un diagnostic

```bash
auroranet status -d
auroranet debug bundle
sudo journalctl -u auroranet --since "1 hour ago" > /tmp/auroranet.log
```

Sous Windows :

```powershell
auroranet status -d
auroranet debug bundle
```

Anonymisez les données sensibles avant de partager :

```bash
auroranet status -d --anonymize
```

## Limitations connues

- **MSI non signé Authenticode** : SmartScreen s'affiche à chaque installation.
- **Pas de GUI** : aucune application de bureau ni icône de tray.
- **macOS, FreeBSD, Windows ARM, Linux armv6/armv7** ne sont pas produits.
- **`--management-url` requis** tant que `api.aurora-net.org` ne pointe pas vers
  votre serveur.
- **Archives `.tar.gz`** : vérifiez leur présence dans la release ; sinon,
  utilisez le `.deb`, le paquet Arch ou la release suivante.
- **`install.sh` historique** : dépôt apt `pkgs.netbird.io` et UI non publiée ;
  préférez les artefacts de release.

Si le problème persiste, joignez le bundle de debug, la version
(`auroranet version`), l'OS et les étapes de reproduction.
