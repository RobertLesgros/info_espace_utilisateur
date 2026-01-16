# DiskSpaceAnalyzer - Analyseur d'Espace Disque

Script PowerShell monolithique qui analyse l'espace disque du profil utilisateur courant et affiche les resultats via une interface graphique WPF moderne.

## Fonctionnalites

- **Analyse complete** du repertoire utilisateur avec hierarchie des dossiers
- **Interface WPF moderne** avec detection automatique du theme systeme (clair/sombre)
- **Detection des droits** : Mode Utilisateur ou Administrateur automatique
- **7 onglets** : Vue d'ensemble, Hierarchie, Top 20 fichiers, Doublons, Filtres, Nettoyage, Journal
- **Detection des doublons** par nom et date de modification
- **Export HTML interactif** avec graphiques Chart.js
- **Systeme de filtrage** par extensions, taille et date
- **Nettoyage guide** avec analyse, conseils personnalises puis options de nettoyage
- **Envoi de rapport par email** automatique apres nettoyage
- **Integration Explorateur Windows** (double-clic pour ouvrir)

## Prerequis

- Windows 10/11
- PowerShell 5.1 ou superieur
- .NET Framework 4.5+

## Installation

Aucune installation requise. Telecharger le fichier `DiskSpaceAnalyzer.ps1` et l'executer.

## Utilisation

```powershell
# Analyser le profil utilisateur courant
.\DiskSpaceAnalyzer.ps1

# Analyser un dossier specifique
.\DiskSpaceAnalyzer.ps1 -Path "D:\Data"

# Specifier un chemin d'export pour le HTML
.\DiskSpaceAnalyzer.ps1 -ExportPath "C:\Rapports"
```

## Raccourcis clavier

| Raccourci | Action |
|-----------|--------|
| F5 | Lancer l'analyse |
| Ctrl+E | Exporter en HTML |

## Structure du rapport HTML

Le rapport HTML genere contient :
- Statistiques globales (espace, fichiers, dossiers)
- Graphique de repartition par type de fichier
- Top 20 des fichiers les plus volumineux (triable, filtrable)
- Liste des doublons detectes
- Export CSV depuis le navigateur
- Option d'envoi par email au support

## Parametres

| Parametre | Description | Defaut |
|-----------|-------------|--------|
| `-Path` | Chemin a analyser | `$env:USERPROFILE` |
| `-ExportPath` | Dossier pour les exports HTML | `$env:TEMP` |
| `-SupportEmail` | Email pour l'envoi de rapport | `support@entreprise.com` |

## Filtres disponibles

- **Extensions** : .tmp, .log, .bak, .cache (et personnalisees)
- **Taille minimum** : Filtrer les fichiers en dessous d'une taille
- **Anciennete** : Fichiers non modifies depuis X jours
- **Dossiers exclus** : AppData\Local\Temp, etc.

## Nettoyage integre

L'onglet Nettoyage propose un parcours guide en 3 etapes :

### Etape 1 : Analyse
Cliquez sur "Analyser mon profil" pour scanner votre espace utilisateur.

### Etape 2 : Conseils
Apres analyse, vous recevez des conseils personnalises bases sur l'espace occupe.

### Etape 3 : Nettoyage
Selectionnez les elements a nettoyer parmi :

**Cache des navigateurs** (conserve mots de passe et favoris) :
- Microsoft Edge (Chromium)
- Mozilla Firefox
- Google Chrome

**Fichiers utilisateur** :
- Dossier Temp utilisateur
- Cache des miniatures
- Corbeille
- Documents recents
- Fichiers .log anciens

**Dossier Telechargements** :
- Option speciale avec avertissement
- Les fichiers sont generalement retelechargea­bles
- Responsabilite de l'utilisateur

**Options Administrateur** (visibles uniquement avec droits eleves) :
- Dossier Temp Windows
- Prefetch
- Cache des icones systeme
- Cache des polices
- Rapports d'erreurs Windows

## Configuration SMTP

Pour l'envoi automatique des rapports par email, modifiez ces variables dans le script :

```powershell
$Script:SmtpServer = "smtp.entreprise.com"      # Serveur SMTP
$Script:SmtpPort = 587                           # Port SMTP
$Script:SmtpUser = "noreply@entreprise.com"     # Login SMTP
$Script:SmtpPassword = "MotDePasseSMTP"         # Mot de passe SMTP
$Script:SmtpTo = "admin-it@entreprise.com"      # Destinataire
$Script:SmtpFrom = "noreply@entreprise.com"     # Expediteur
$Script:SmtpUseSsl = $true                       # Utiliser SSL/TLS
```

Le sujet de l'email contient : Nom de l'ordinateur + Nom d'utilisateur

## Capture d'ecran

L'interface s'adapte automatiquement au theme Windows :
- Theme clair : fond blanc, couleurs vives
- Theme sombre : fond sombre, couleurs attenuees
- Bouton de changement de theme en haut a droite

## Licence

Script libre d'utilisation.

## Version

1.5 - Janvier 2026
- Detection automatique des droits (Utilisateur vs Administrateur)
- Mode Utilisateur : chemin et filtres verrouilles sur le profil
- Nouveau parcours guide : Analyser > Conseils > Nettoyage
- Ajout du nettoyage du dossier Telechargements avec avertissement
- Envoi automatique du rapport par email apres nettoyage
- Conseils personnalises selon l'espace occupe

1.4 - Janvier 2026
- Separation des actions utilisateur/administrateur dans l'onglet Nettoyage
- Estimation incluant le nombre de fichiers
- Bouton Nettoyer actif uniquement apres estimation
- Barre de progression lors du nettoyage
