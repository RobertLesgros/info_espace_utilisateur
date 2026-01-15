# Analyseur d'Espace Disque - DiskSpaceAnalyzer

## Vue d'ensemble du projet

Créer un script PowerShell monolithique qui analyse l'espace disque du profil utilisateur courant (C:\Users\%username%) et affiche les résultats via une interface graphique WPF moderne. Le script doit également générer un rapport HTML interactif exportable et détectable des fichiers en double.

## Objectifs principaux

1. **Analyse complète** du répertoire utilisateur avec affichage de la hiérarchie des dossiers
2. **Interface WPF** avec thème système, onglets séparés et visualisations graphiques
3. **Tableau des 20 fichiers les plus volumineux** avec informations détaillées
4. **Détection des doublons** par nom et date/heure de modification
5. **Export HTML interactif** avec ouverture automatique dans le navigateur et option d'envoi par email
6. **Barre de progression** pendant l'analyse
7. **Système de filtrage** par extensions et options d'exclusion
8. **Intégration avec l'Explorateur Windows** pour ouvrir directement les emplacements

## Spécifications techniques

### Architecture
- **Format** : Script PowerShell monolithique (.ps1)
- **Interface** : WPF (Windows Presentation Foundation)
- **Thème** : Détection automatique du thème système (clair/sombre)
- **Export** : HTML5 avec CSS moderne et JavaScript (Chart.js pour les graphiques)

### Fonctionnalités détaillées

#### 1. Interface WPF

**Structure en onglets :**
- **Vue d'ensemble** : Graphique de répartition de l'espace (TreeMap ou graphique en secteurs)
- **Hiérarchie des dossiers** : TreeView avec taille de chaque dossier/sous-dossier
- **Top 20 fichiers** : DataGrid avec colonnes détaillées
- **Doublons** : Liste des fichiers en double détectés
- **Filtres** : Panneau de configuration des filtres et options d'analyse

**Colonnes du Top 20 :**
- Nom du fichier
- Chemin complet
- Taille (formatée : Mo, Go)
- Date de modification
- Date de création
- Extension
- Bouton "Ouvrir dans l'Explorateur"

**Thème :**
- Détection automatique via registry Windows (AppsUseLightTheme)
- Palette de couleurs adaptative (clair/sombre)
- Icônes et visuels modernes

#### 2. Analyse et performance

**Barre de progression :**
- Pourcentage d'avancement
- Nombre de fichiers analysés
- Dossier en cours d'analyse
- Estimation du temps restant

**Analyse récursive :**
- Scan complet sans limitation de profondeur
- Gestion des erreurs d'accès (permissions)
- Calcul de la taille totale par dossier
- Comptage des fichiers et sous-dossiers

**Optimisation :**
- Utilisation de jobs asynchrones pour ne pas bloquer l'UI
- Mise en cache des résultats pendant la session

#### 3. Détection des doublons

**Critères de détection :**
- Même nom de fichier (case-insensitive)
- Même date/heure de modification (à la seconde près)

**Affichage des doublons :**
- Regroupement par nom de fichier
- Liste de tous les emplacements pour chaque doublon
- Taille totale gaspillée par les doublons
- Bouton pour ouvrir chaque emplacement
- Option de suppression (avec confirmation)

#### 4. Système de filtrage

**Filtres disponibles :**
- **Par extension** : Inclusion/exclusion de types de fichiers spécifiques
  - Exemples prédéfinis : .tmp, .log, .bak, .cache
- **Par taille** : Fichiers de plus de X Mo
- **Par date** : Fichiers non modifiés depuis X jours
- **Exclusion de dossiers** : AppData, Temp, Cache (configurable)

**Interface de filtrage :**
- Cases à cocher pour filtres prédéfinis
- Champs de saisie personnalisés
- Bouton "Appliquer les filtres" avec ré-analyse
- Bouton "Réinitialiser" pour supprimer tous les filtres

#### 5. Export HTML

**Contenu du rapport :**
- Résumé de l'analyse (date, chemin, espace total/utilisé/libre)
- Graphique interactif de répartition (Chart.js)
- Tableau des 20 fichiers les plus volumineux (triable)
- Liste des doublons détectés
- Hiérarchie des dossiers (collapsible)
- Liens cliquables pour ouvrir dans l'Explorateur (file:///)

**Fonctionnalités HTML :**
- Responsive design
- Recherche/filtrage dans les tableaux (JavaScript)
- Export CSV depuis le HTML
- Graphiques interactifs avec survol

**Option d'envoi par email :**
- Bouton "Envoyer au support" dans le HTML
- Ouverture du client email par défaut avec :
  - Destinataire : support@entreprise.com (configurable)
  - Sujet : "Rapport d'analyse disque - [username] - [date]"
  - Fichier HTML en pièce jointe
  - Corps du message pré-rempli

**Ouverture automatique :**
- Génération du fichier HTML dans %TEMP%
- Ouverture automatique dans le navigateur par défaut
- Conservation du fichier pour consultation ultérieure

#### 6. Intégration Explorateur Windows

**Actions disponibles :**
- Double-clic sur un fichier/dossier : ouvre l'Explorateur à cet emplacement
- Bouton "Ouvrir" dans chaque ligne du tableau
- Clic droit : menu contextuel avec options
  - Ouvrir l'emplacement
  - Copier le chemin
  - Propriétés du fichier
  - Supprimer (avec confirmation)

### Interface utilisateur détaillée

#### Fenêtre principale

```
┌─────────────────────────────────────────────────────────────┐
│ 📊 Analyseur d'Espace Disque - C:\Users\[Username]         │
├─────────────────────────────────────────────────────────────┤
│ [Analyser] [Exporter HTML] [Paramètres] [?]                │
├─────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ [Vue d'ensemble] [Hiérarchie] [Top 20] [Doublons]       │ │
│ ├─────────────────────────────────────────────────────────┤ │
│ │                                                          │ │
│ │  [Contenu de l'onglet actif]                            │ │
│ │                                                          │ │
│ │                                                          │ │
│ └─────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│ Status: Prêt | Fichiers: 15,234 | Taille: 45.2 Go         │
│ [████████████████████░░░░░░░░░] 78% - Analyse en cours...  │
└─────────────────────────────────────────────────────────────┘
```

#### Onglet "Vue d'ensemble"
- Graphique circulaire ou TreeMap de la répartition
- Statistiques globales
  - Espace total du lecteur
  - Espace utilisé par le profil
  - Nombre total de fichiers/dossiers
  - Top 5 des types de fichiers les plus volumineux

#### Onglet "Hiérarchie"
- TreeView avec colonnes :
  - Nom du dossier
  - Taille
  - % du total
  - Nombre de fichiers
  - Nombre de sous-dossiers
- Tri et recherche intégrés

#### Onglet "Top 20"
- DataGrid avec toutes les colonnes mentionnées
- Tri cliquable sur chaque colonne
- Recherche rapide
- Boutons d'action par ligne

#### Onglet "Doublons"
- Vue groupée par nom de fichier
- Expandable pour voir tous les emplacements
- Statistiques :
  - Nombre de groupes de doublons
  - Espace total gaspillé
  - Bouton "Tout sélectionner" et "Supprimer sélection"

### Gestion des erreurs

**Erreurs à gérer :**
- Accès refusé (permissions insuffisantes)
- Fichiers/dossiers en cours d'utilisation
- Chemin trop long (> 260 caractères)
- Lecteur non disponible
- Espace disque insuffisant pour l'export

**Affichage des erreurs :**
- Toast notifications dans l'interface
- Log des erreurs dans un onglet "Journal"
- Option d'ignorer et continuer l'analyse

### Configuration et paramètres

**Paramètres enregistrés (registry ou fichier JSON) :**
- Chemin d'analyse par défaut
- Filtres favoris
- Thème forcé (si différent du système)
- Email du support pour l'envoi
- Options d'export par défaut

## Structure du code

### Sections principales du script

1. **En-tête et configuration**
   - Commentaires d'aide
   - Variables globales
   - Configuration par défaut

2. **Classes et types personnalisés**
   - Classe FileInfo étendue
   - Classe FolderNode pour la hiérarchie

3. **Fonctions utilitaires**
   - Format-FileSize
   - Get-SystemTheme
   - Test-FileAccess
   - Get-FileHash (optionnel)

4. **Fonctions d'analyse**
   - Scan-Directory (récursif)
   - Find-Duplicates
   - Calculate-FolderSizes
   - Update-ProgressBar

5. **Génération du rapport**
   - Generate-HTMLReport
   - Create-ChartData
   - Send-EmailReport

6. **Interface WPF**
   - XAML en HereString
   - Event handlers
   - Data binding

7. **Main / Point d'entrée**
   - Initialisation
   - Vérifications préalables
   - Lancement de l'interface

## Livrables attendus

1. **Script PowerShell** : DiskSpaceAnalyzer.ps1
   - Code commenté et structuré
   - Gestion d'erreurs robuste
   - Compatible PowerShell 5.1 et 7+

2. **Documentation intégrée**
   - Help (Get-Help DiskSpaceAnalyzer.ps1)
   - Commentaires dans le code
   - Exemples d'utilisation

3. **Fichier README.md** (optionnel)
   - Instructions d'installation
   - Captures d'écran
   - Prérequis système

## Prérequis techniques

- **OS** : Windows 10/11
- **PowerShell** : Version 5.1 minimum (7+ recommandé)
- **Permissions** : Accès en lecture au profil utilisateur
- **.NET Framework** : 4.5+ (pour WPF)
- **Navigateur** : Pour l'export HTML (Edge, Chrome, Firefox)

## Contraintes et considérations

### Performance
- Optimiser pour des profils de 50-100 Go
- Utiliser RunspacePool pour parallélisation si nécessaire
- Limiter l'utilisation mémoire (streaming des résultats)

### Sécurité
- Ne pas élever les privilèges automatiquement
- Valider tous les chemins d'accès
- Confirmation obligatoire avant suppression
- Pas de stockage de données sensibles

### Compatibilité
- Tester sur différentes résolutions d'écran
- Support du multi-écran
- Gestion des DPI élevés (scaling)

### UX
- Temps de réponse < 2s pour l'ouverture de l'interface
- Feedback visuel pour toutes les actions longues
- Messages d'erreur clairs et actionnables
- Raccourcis clavier (Ctrl+E pour export, F5 pour rafraîchir, etc.)

## Extensions futures possibles

- Support d'autres lecteurs/chemins
- Planification d'analyses automatiques
- Historique des analyses avec comparaison
- Détection de fichiers inutiles (cache, temp, etc.)
- Suggestions de nettoyage intelligentes
- Export vers d'autres formats (PDF, Excel)
- Mode ligne de commande (sans GUI) pour scripts automatisés
- Intégration avec OneDrive/cloud pour analyse d'espace cloud

## Critères de succès

✅ L'interface WPF se lance sans erreur et affiche les données correctement
✅ L'analyse complète un profil de 50 Go en moins de 2 minutes
✅ Le rapport HTML s'ouvre automatiquement et est fonctionnel
✅ Les doublons sont détectés avec précision
✅ Le thème s'adapte automatiquement au système
✅ Aucun crash sur les erreurs d'accès courantes
✅ L'intégration avec l'Explorateur fonctionne parfaitement
✅ Le code est lisible, commenté et maintenable

---

## Notes pour l'implémentation

### Ordre de développement recommandé

1. Structure de base et fonctions utilitaires
2. Fonction d'analyse du système de fichiers
3. Interface WPF minimaliste (vue d'ensemble)
4. Ajout des autres onglets
5. Détection des doublons
6. Système de filtrage
7. Génération du rapport HTML
8. Intégration Explorateur et actions
9. Thème et polish final
10. Tests et optimisation

### Bibliothèques à utiliser

- **System.Windows.Forms** : Dialogs et intégration système
- **System.Windows.Markup** : Pour le parsing XAML
- **System.Web** : Pour l'encodage HTML
- **Chart.js** (CDN) : Pour les graphiques dans le HTML

### Points d'attention

⚠️ Gestion de la mémoire pour les gros volumes de données
⚠️ Thread safety pour l'UI WPF (Dispatcher.Invoke)
⚠️ Chemins avec caractères spéciaux ou très longs
⚠️ Performances sur des dossiers avec des milliers de fichiers
⚠️ Compatibilité des liens file:/// selon les navigateurs

---

**Version du document** : 1.0
**Date de création** : 15 janvier 2026
**Prêt pour implémentation** : ✅
