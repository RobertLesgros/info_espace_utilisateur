# DiskSpaceAnalyzer - Analyseur d'Espace Disque

Script PowerShell monolithique qui analyse l'espace disque du profil utilisateur courant et affiche les resultats via une interface graphique WPF moderne.

## Fonctionnalites

- **Analyse complete** du repertoire utilisateur avec hierarchie des dossiers
- **Interface WPF moderne** avec detection automatique du theme systeme (clair/sombre)
- **Bouton de changement de theme** pour basculer entre mode clair et sombre
- **7 onglets** : Vue d'ensemble, Hierarchie, Top 20 fichiers, Doublons, Filtres, Nettoyage, Journal
- **Detection des doublons** par nom et date de modification
- **Export HTML interactif** avec graphiques Chart.js
- **Systeme de filtrage** par extensions, taille et date
- **Nettoyage integre** des caches navigateurs et fichiers temporaires
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

L'onglet Nettoyage permet de liberer de l'espace disque en supprimant :

**Cache des navigateurs** (conserve mots de passe et favoris) :
- Microsoft Edge (Chromium)
- Mozilla Firefox
- Google Chrome

**Fichiers temporaires Windows** :
- Dossier Temp utilisateur
- Dossier Temp Windows
- Prefetch

**Cache systeme** :
- Cache des miniatures
- Cache des icones
- Cache des polices

**Autres** :
- Corbeille
- Historique des documents recents
- Fichiers journaux anciens (> 30 jours)
- Rapports d'erreurs Windows

## Capture d'ecran

L'interface s'adapte automatiquement au theme Windows :
- Theme clair : fond blanc, couleurs vives
- Theme sombre : fond sombre, couleurs attenuees
- Bouton de changement de theme en haut a droite

## Licence

Script libre d'utilisation.

## Version

1.4 - Janvier 2026
- Separation des actions utilisateur/administrateur dans l'onglet Nettoyage
- Estimation incluant le nombre de fichiers
- Bouton Nettoyer actif uniquement apres estimation
- Barre de progression lors du nettoyage
