# Client Windows

Le client Windows est un MSI **x64** pour Windows 10 et Windows 11. Il installe
le binaire, `wintun.dll` et un service Windows. Il n'y a ni GUI ni icône de
notification : tout se pilote en PowerShell.

Windows ARM, Windows 7/8 et l'architecture x86 ne sont pas supportés.

## Télécharger

Depuis la release GitHub, prenez :

```text
auroranet_0.71.6_windows_amd64.msi
```

Vérifiez si possible `SHA256SUMS` et sa signature GPG avant installation.

## Installer

1. Double-cliquez sur le MSI.
2. SmartScreen affiche un avertissement car le MSI n'est **pas signé
   Authenticode** : **More info** → **Run anyway**.
3. L'installation est `perMachine` : elle nécessite les droits administrateur.
4. Le service **AuroraNet** est créé en démarrage automatique et lancé
   immédiatement.

Contenu installé :

| Élément | Emplacement |
| --- | --- |
| Binaire | `C:\Program Files\AuroraNet\auroranet.exe` |
| Pilote TUN | `C:\Program Files\AuroraNet\wintun.dll` |
| Configuration | `C:\ProgramData\AuroraNet\config.json` |
| Logs | `C:\ProgramData\AuroraNet\client.log` |
| Service | `AuroraNet` (LocalSystem, démarrage automatique) |

Le service est lancé avec :

```text
service run config C:\ProgramData\AuroraNet\config.json log-level info
```

## Le binaire n'est pas dans le PATH

Le MSI n'ajoute pas `C:\Program Files\AuroraNet` au `PATH`. Deux options :

**Option A — utiliser le chemin complet** dans chaque commande :

```powershell
& "C:\Program Files\AuroraNet\auroranet.exe" version
```

**Option B — ajouter le dossier au PATH** (une fois, en admin) :

```powershell
[Environment]::SetEnvironmentVariable(
  "Path",
  [Environment]::GetEnvironmentVariable("Path", "Machine") + ";C:\Program Files\AuroraNet",
  "Machine"
)
```

Fermez puis rouvrez PowerShell. `auroranet` sera alors reconnu.

## Rejoindre un réseau

Ouvrez **PowerShell en administrateur** :

```powershell
auroranet up `
  --management-url https://vpn.dev.aurora-net.org `
  --setup-key <CLE>
```

Ou avec le chemin complet :

```powershell
& "C:\Program Files\AuroraNet\auroranet.exe" up `
  --management-url https://vpn.dev.aurora-net.org `
  --setup-key <CLE>
```

Si `auroranet` n'est pas reconnu, c'est que le PATH n'a pas été mis à jour :
rouvrez le terminal ou utilisez le chemin complet.

L'option `--management-url` est obligatoire tant que le défaut compilé
(`https://api.aurora-net.org`) ne résout pas vers votre serveur.

## Vérifier

```powershell
auroranet status
auroranet status -d
Get-Service AuroraNet
```

Résultat attendu : `Management: Connected`, `Signal: Connected`, et une adresse
overlay `100.x.y.z` pour le pair.

Si le service ne démarre pas :

```powershell
Get-Service AuroraNet | Format-List *
Get-EventLog -LogName Application -Source AuroraNet -Newest 20
```

Les logs applicatifs sont aussi dans
`C:\ProgramData\AuroraNet\client.log`.

## Gérer le service

```powershell
Get-Service AuroraNet
Start-Service AuroraNet
Stop-Service AuroraNet
Restart-Service AuroraNet
```

Après un redémarrage de Windows, le service repart automatiquement et le client
se reconnecte avec la configuration enregistrée. Pour désactiver ce comportement,
utilisez `--disable-auto-connect` lors du `up`, ou `auroranet down`.

## Mettre à jour

Installez le MSI de la nouvelle version par-dessus l'existante : le
`UpgradeCode` est stable, donc Windows effectue une mise à jour en place et
conserve `C:\ProgramData\AuroraNet\config.json`.

Après installation :

```powershell
auroranet version
auroranet status
```

Il n'y a pas de mise à jour automatique intégrée au MSI : téléchargez la nouvelle
version depuis les releases.

## Désinstaller

1. **Paramètres → Applications → Applications installées → AuroraNet →
   Désinstaller**.
2. Le service est arrêté et supprimé par le MSI.
3. Le dossier `C:\ProgramData\AuroraNet` (configuration et logs) n'est pas
   supprimé automatiquement. Effacez-le manuellement si nécessaire :

```powershell
Remove-Item -Recurse -Force "C:\ProgramData\AuroraNet"
```

## Limitations et précautions

- **Pas de GUI** : aucune icône de tray, aucun installeur graphique de réseau.
  Utilisez la CLI et le dashboard.
- **MSI non signé** : distribuez-le avec son empreinte SHA-256 et sa signature
  GPG ; SmartScreen restera affiché.
- **Antivirus / EDR** : certains produits inspectent le pilote Wintun. Autorisez
  `auroranet.exe` et le service si nécessaire.
- **Horloge** : une horloge Windows décalée casse TLS et l'authentification.
  Activez la synchronisation automatique.
- **Réseaux d'entreprise** : un proxy TLS qui intercepte le trafic peut faire
  échouer la connexion au management. Ajoutez le certificat racine de
  l'entreprise au magasin Windows, ou utilisez un réseau non filtré.

Pour les options de configuration, voir
[Configuration du client](05-configuration-client.md). En cas d'échec, voir
[Dépannage](06-depannage.md).
