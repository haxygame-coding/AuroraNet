# Serveur auto-hébergé

Ce guide installe le serveur AuroraNet complet (management, signal, relais,
STUN/TURN et dashboard) avec Docker Compose et un reverse proxy Traefik intégré
qui gère les certificats Let's Encrypt.

## 1. Prérequis

- Un hôte Linux **amd64** : Ubuntu 22.04/24.04 ou Debian 12/13 recommandés.
- Docker Engine et le plugin Docker Compose (`docker compose version`).
- `curl` et `jq`.
- Un nom public (FQDN) qui pointe vers l'hôte, par exemple
  `vpn.dev.aurora-net.org`.
- Les ports **80/tcp**, **443/tcp** et **3478/udp** accessibles depuis Internet.
- Un accès `sudo` (le script manipule Docker et écrit des fichiers de config).

Le serveur doit pouvoir joindre Internet pour télécharger les images GHCR et
obtenir un certificat Let's Encrypt.

## 2. DNS

Créez l'enregistrement avant de lancer l'installation : Let's Encrypt valide le
domaine via HTTP-01 sur le port 80.

| Nom | Type | Valeur |
| --- | --- | --- |
| `vpn.dev.aurora-net.org` | `A` | IPv4 publique du serveur |
| `vpn.dev.aurora-net.org` | `AAAA` | IPv6 publique, uniquement si l'hôte en a une |

Points importants :

- Chez Cloudflare, mettez l'enregistrement en **DNS only** (nuage gris). Le proxy
  Cloudflare empêcherait la validation HTTP-01 et casserait le flux gRPC.
- N'utilisez ni schéma, ni port, ni point final dans le nom.
- Vérifiez la résolution avant de continuer :

```bash
dig +short vpn.dev.aurora-net.org
```

La commande doit renvoyer l'IP publique du serveur.

## 3. Ports et pare-feu

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 3478/udp
# uniquement si vous activez le proxy AuroraNet :
sudo ufw allow 51820/udp
sudo ufw reload
```

| Port | Usage |
| --- | --- |
| 80/tcp | Redirection HTTP vers HTTPS et validation ACME |
| 443/tcp | Dashboard, API de management, signal et relais (tout passe par Traefik) |
| 3478/udp | STUN/TURN, nécessaire au NAT traversal |
| 51820/udp | Optionnel, connexions P2P du proxy AuroraNet |

Si l'hôte est derrière un NAT (cloud privé, box), publiez aussi l'IP publique
dans `AURORANET_TURN_EXTERNAL_IP`, sinon les pairs distants auront des problèmes
de connexion.

## 4. Installation

Placez-vous dans un répertoire dédié : le script écrit ses fichiers dans le
répertoire courant et refuse de réinitialiser une installation existante.

```bash
mkdir -p ~/auroranet && cd ~/auroranet

curl -fsSL \
  https://raw.githubusercontent.com/haxygame-coding/auroranet/main/infrastructure_files/getting-started.sh \
  -o getting-started.sh
chmod +x getting-started.sh

sudo AURORANET_DOMAIN=vpn.dev.aurora-net.org \
     AURORANET_EMAIL=admin@aurora-net.org \
     AURORANET_NON_INTERACTIVE=true \
     ./getting-started.sh
```

Variables utiles :

| Variable | Rôle | Défaut |
| --- | --- | --- |
| `AURORANET_DOMAIN` | FQDN public | demandé |
| `AURORANET_EMAIL` | E-mail Let's Encrypt | demandé |
| `AURORANET_NON_INTERACTIVE` | `true` pour ne poser aucune question | `false` |
| `AURORANET_REVERSE_PROXY_TYPE` | `0` Traefik intégré, `1` Traefik externe, `2` Nginx, `3` NPM, `4` Caddy, `5` ports exposés | `0` |
| `AURORANET_ENABLE_PROXY` | Active le proxy sortant AuroraNet | `false` |
| `AURORANET_ENABLE_CROWDSEC` | Active CrowdSec | `false` |
| `AURORANET_TURN_EXTERNAL_IP` | IP publique du serveur derrière un NAT | vide |
| `AURORANET_MGMT_DNS_DOMAIN` | Domaine des noms de pairs (MagicDNS) | `auroranet.selfhosted` |

Sans `AURORANET_REVERSE_PROXY_TYPE=0`, Traefik intégré n'est pas utilisé : c'est
à votre reverse proxy de terminer TLS et de router le domaine vers le dashboard
et le serveur. Dans ce cas, n'ouvrez que les ports réellement utilisés.

## 5. Fichiers générés

Le script crée notamment :

```text
docker-compose.yml     # services Traefik, dashboard, auroranet-server (+ proxy/CrowdSec)
config.yaml            # configuration du serveur (management, signal, relais, TURN)
dashboard.env          # variables du dashboard (endpoints, OIDC)
.env                   # secrets locaux (ex. clé CrowdSec), mode 600
proxy.env              # token du proxy, si activé
traefik-dynamic.yaml   # routage TCP du proxy, si activé
crowdsec/              # configuration CrowdSec, si activé
```

Les données persistantes sont dans les volumes Docker, notamment
`auroranet_data` (base et état du serveur) et
`auroranet_traefik_letsencrypt` (certificats).

Ne modifiez pas `config.yaml` à la main sans sauvegarde : il est référencé par
le conteneur `auroranet-server`.

## 6. Démarrer et vérifier

Le script lance normalement les conteneurs lui-même. Sinon :

```bash
cd ~/auroranet
sudo docker compose up -d
sudo docker compose ps
```

Contrôles :

```bash
curl -I https://vpn.dev.aurora-net.org
sudo docker compose logs -f auroranet-server
sudo docker compose logs -f auroranet-traefik
```

Le dashboard est disponible sur `https://vpn.dev.aurora-net.org`. Le premier
compte créé lors de l'onboarding devient administrateur.

Si le certificat n'est pas encore émis, attendez une minute et rechargez : le
temps que Traefik termine le challenge ACME.

## 7. Créer la première setup key

1. Connectez-vous au dashboard.
2. Terminez l'onboarding (compte administrateur, nom du réseau).
3. Ouvrez **Setup Keys** dans le menu.
4. Cliquez sur **Create Setup Key**.
5. Choisissez un nom, la durée de validité et le type :
   - **Reusable** : plusieurs machines, utile pour un parc ;
   - **Ephemeral** : la clé est consommée après un enrollment, adaptée aux
     machines jetables ou à la CI.
6. Associez éventuellement un groupe : c'est ce groupe qui déterminera les
   politiques d'accès appliquées au pair.
7. Copiez la clé : elle ne sera plus affichée en entier ensuite.

L'enrôlement d'un client est décrit dans
[Rejoindre un réseau](04-rejoindre-un-reseau.md).

## 8. Exploitation courante

### Mettre à jour

Sauvegardez d'abord (section suivante), puis :

```bash
cd ~/auroranet
sudo docker compose pull
sudo docker compose up -d
sudo docker compose ps
```

Les images utilisées sont publiées sur GHCR sous
`ghcr.io/haxygame-coding/auroranet-*`. Évitez `latest` en production : épinglez
des tags de version dans `docker-compose.yml`.

### Consulter les logs

```bash
sudo docker compose logs --tail=200 auroranet-server
sudo docker compose logs --tail=200 auroranet-traefik
sudo docker compose logs --tail=200 auroranet-dashboard
```

### Sauvegarder

Arrêtez les services pour obtenir une base cohérente :

```bash
cd ~/auroranet
sudo docker compose stop

sudo tar -czf ~/auroranet-config-$(date +%F).tar.gz \
  docker-compose.yml config.yaml dashboard.env .env proxy.env traefik-dynamic.yaml

# Trouvez le nom réel du volume (Compose peut le préfixer) :
sudo docker volume ls | grep auroranet_data
sudo docker run --rm \
  -v "$(sudo docker volume ls -q | grep auroranet_data | head -1)":/data \
  -v "$PWD":/backup alpine \
  tar -czf /backup/auroranet-data-$(date +%F).tar.gz -C /data .

sudo docker compose start
```

Conservez aussi le volume des certificats si vous voulez éviter de redemander un
certificat : `auroranet_traefik_letsencrypt`.

### Restaurer

```bash
cd ~/auroranet
sudo docker compose down
sudo tar -xzf ~/auroranet-config-AAAA-MM-JJ.tar.gz
sudo docker run --rm \
  -v "$(sudo docker volume ls -q | grep auroranet_data | head -1)":/data \
  -v "$PWD":/backup alpine \
  sh -c 'cd /data && tar -xzf /backup/auroranet-data-AAAA-MM-JJ.tar.gz'
sudo docker compose up -d
```

### Désinstaller

```bash
cd ~/auroranet
sudo docker compose down          # conserve les volumes
# ou, pour tout supprimer (irréversible) :
# sudo docker compose down --volumes
```

Les fichiers générés restent dans le répertoire. Supprimez-les uniquement après
avoir sauvegardé ce dont vous avez besoin.

## 9. Reverse proxy externe

| Type | Valeur | Particularité |
| --- | --- | --- |
| Traefik intégré | `0` | TLS et routage automatiques, ports 80/443 |
| Traefik externe | `1` | Renseignez le réseau, l'entrypoint et le certresolver |
| Nginx | `2` | Le script génère `nginx-auroranet.conf` |
| Nginx Proxy Manager | `3` | Le script génère `npm-advanced-config.txt` |
| Caddy | `4` | Le script génère `caddyfile-auroranet.txt` |
| Manuel | `5` | Ports exposés, à vous de router |

Avec un proxy externe, le dashboard et l'API doivent être accessibles sur le
même nom et le trafic gRPC doit être transmis en HTTP/2. Déclarez l'adresse du
proxy dans `AURORANET_TRUSTED_PEERS` pour que les IP clientes soient correctes.

## 10. Sécurité

- Gardez `config.yaml`, `.env` et `proxy.env` en mode `600`.
- N'exposez jamais la base ou les ports internes des conteneurs.
- Mettez à jour Docker et les images régulièrement.
- Limitez l'accès SSH à l'hôte et surveillez les logs Traefik.
- Sauvegardez avant chaque mise à jour et testez la restauration au moins une
  fois.

En cas de problème, voir [Dépannage](06-depannage.md).
