' ============================================
' Lanceur Analyseur d'Espace Disque
' Execute le script PowerShell sans fenetre
' ============================================
'
' INSTRUCTIONS:
' 1. Placer ce fichier dans le meme dossier que DiskSpaceAnalyzer.ps1
' 2. Double-cliquer sur ce fichier pour lancer l'analyseur
' 3. L'interface graphique s'ouvrira sans fenetre PowerShell visible
'
' ============================================

Option Explicit

Dim objShell, objFSO
Dim strScriptPath, strPowerShell, strCommand, strScriptFolder

Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")

' Obtenir le dossier du script VBS
strScriptFolder = objFSO.GetParentFolderName(WScript.ScriptFullName)

' Chemin du script PowerShell (dans le meme dossier que ce VBS)
strScriptPath = strScriptFolder & "\DiskSpaceAnalyzer.ps1"

' Verifier si le script existe
If Not objFSO.FileExists(strScriptPath) Then
    MsgBox "Le script PowerShell n'a pas ete trouve." & vbCrLf & vbCrLf & _
           "Chemin attendu:" & vbCrLf & strScriptPath & vbCrLf & vbCrLf & _
           "Assurez-vous que le fichier DiskSpaceAnalyzer.ps1 " & _
           "est dans le meme dossier que ce lanceur.", _
           vbCritical, "Erreur - Analyseur Espace Disque"
    WScript.Quit 1
End If

' Construire la commande PowerShell
' -NoProfile       : Ne pas charger le profil utilisateur (plus rapide)
' -ExecutionPolicy : Autoriser l'execution du script
' -WindowStyle     : Hidden = pas de fenetre PowerShell visible
' -File            : Executer le script specifie
strPowerShell = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & strScriptPath & """ -SkipLauncherDeploy"

' Executer le script PowerShell
' Premier parametre: commande a executer
' Deuxieme parametre: 0 = fenetre cachee, 1 = normale, 2 = minimisee
' Troisieme parametre: False = ne pas attendre la fin de l'execution
objShell.Run strPowerShell, 0, False

' Nettoyage
Set objFSO = Nothing
Set objShell = Nothing
