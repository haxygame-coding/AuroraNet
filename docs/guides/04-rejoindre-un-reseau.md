# Rejoindre un réseau

Un pair rejoint un réseau AuroraNet avec deux informations :

1. l'URL du serveur de management ;
2. une **setup key** créée par un administrateur du réseau.

## Avant de commencer

- Le client est installé ([Linux](02-linux.md) ou [Windows](03-windows.md)).
- Le serveur est joignable en HTTPS sur son domaine.
- Vous avez un compte administrateur sur le dashboard, ou un administrateur vous
  a fourni une setup key.

## Créer une setup key (administrateur)

1. Ouvrez le dashboard : `https://vpn.dev.aurora-net.org`.
2. Menu **Setup Keys** → **Create Setup Key**.
3. Renseignez :
   - **Name** : un nom explicite (`portable-alice`, `serveur-ci`, …) ;
   - **Type** : `Reusable` pour plusieurs machines, `Ephemeral` pour une seule ;
   - **Expiration** : durée de validité ;
   - **Auto-groups** : groupe(s) auxquels les pairs seront rattachés.
4. Créez, puis copiez la clé immédiatement : elle n'est affichée qu'une fois.

Une setup key est un secret. Ne la mettez pas dans un dépôt Git public, un ticket
ou un chat d'équipe. Pour un parc, préférez plusieurs clés nommées, afin de
pouvoir en révoquer une sans toucher aux autres.

## Enrôler la machine

### Linux

```bash
sudo auroranet up \
  --management-url https://vpn.dev.aurora-net.org \
  --setup-key <CLE>
```

### Windows (PowerShell administrateur)

```powershell
auroranet up `
  --management-url https://vpn.dev.aurora-net.org `
  --setup-key <CLE>
```

Si le binaire n'est pas dans le PATH :

```powershell
& "C:\Program Files\AuroraNet\auroranet.exe" up `
  --management-url https://vpn.dev.aurora-net.org `
  --setup-key <CLE>
```

### Sans setup key (SSO)

Si le serveur est configuré avec un fournisseur d'identité :

```bash
sudo auroranet up --management-url https://vpn.dev.aurora-net.org
```

Le client ouvre le navigateur. Sur une machine sans affichage :

```bash
sudo auroranet up -m https://vpn.dev.aurora-net.org --no-browser
# ou
sudo auroranet up -m https://vpn.dev.aurora-net.org --qr
```

## Ce qui se passe

1. Le client contacte le management en HTTPS.
2. Il s'authentifie avec la setup key.
3. Le serveur crée un pair, lui attribue une adresse overlay `100.x.y.z` et
   l'ajoute aux groupes prévus.
4. Le client récupère la configuration WireGuard, le signal et les relais.
5. Les connexions aux autres pairs s'établissent en P2P si possible, sinon via
   le relais.

## Vérifier l'enrôlement

Sur la machine :

```bash
auroranet status
auroranet status -d
```

Attendu :

```text
Management: Connected
Signal: Connected
```

Et une adresse `100.x.y.z`.

Dans le dashboard :

- **Peers** doit afficher la machine avec le nom d'hôte utilisé ;
- le pair doit être `Connected` ;
- les groupes doivent correspondre à ceux de la setup key.

Test de connectivité vers un autre pair :

```bash
ping 100.x.y.z
```

## Noms de pairs (MagicDNS)

Par défaut, le domaine DNS interne est `auroranet.selfhosted`. Un pair nommé
`serveur-web` est alors joignable par :

```text
serveur-web.auroranet.selfhosted
```

Le domaine est configurable côté serveur via `AURORANET_MGMT_DNS_DOMAIN`.
Vérifiez la valeur dans le dashboard ou dans `config.yaml`, puis testez :

```bash
nslookup serveur-web.auroranet.selfhosted
```

Si la résolution ne fonctionne pas, le DNS du client est peut-être désactivé ou
un autre resolver est prioritaire. Voir
[Configuration du client](05-configuration-client.md).

## Accès et politiques

Un pair connecté ne voit pas forcément tous les autres : l'accès dépend des
politiques du dashboard.

- Par défaut, un nouveau compte peut avoir une politique « all-to-all ».
- Pour segmenter, créez des groupes et des politiques dans **Access Control**.
- La setup key détermine le groupe initial du pair ; sans groupe, il peut ne
  rien voir.
- Après modification d'une politique, la configuration se propage en quelques
  secondes à minutes.

## Plusieurs machines

- Utilisez une clé **Reusable** pour un parc, ou une clé par machine.
- Donnez un `--hostname` explicite pour retrouver les machines dans le dashboard.
- Les profils du client permettent de garder plusieurs configurations sur une
  même machine (`auroranet profile --help`).

## Révoquer ou retirer un pair

- **Retirer un pair** : dashboard → **Peers** → sélectionner → **Delete**. Le
  client perd l'accès au réseau.
- **Révoquer une clé** : dashboard → **Setup Keys** → supprimer la clé. Les
  pairs déjà enrôlés ne sont pas supprimés, mais la clé ne peut plus servir.
- **Déconnecter localement** : `auroranet down`. Cela coupe le tunnel mais ne
  supprime pas le pair côté serveur.

Après suppression, pensez à supprimer la configuration locale si la machine
change d'usage :

```bash
sudo auroranet down
sudo auroranet service stop
# Linux : sauvegardez avant de supprimer
sudo rm -rf /etc/auroranet
```

Sous Windows, supprimez `C:\ProgramData\AuroraNet` après désinstallation.

## Erreurs fréquentes

| Message / symptôme | Cause probable | Solution |
| --- | --- | --- |
| `failed to connect to daemon` | service arrêté | démarrer le service |
| `context deadline exceeded` vers le management | DNS, port 443, TLS | tester `curl -I https://<DOMAINE>` |
| `setup key is invalid` | clé révoquée, mal copiée ou expirée | recréer une clé |
| `peer is already registered` | configuration locale existante | `auroranet down`, nettoyer le profil |
| `x509: certificate signed by unknown authority` | proxy TLS d'entreprise | ajouter le certificat racine |
| pair connecté mais aucun accès | politiques / groupes | vérifier **Access Control** |

Voir aussi [Dépannage](06-depannage.md).
