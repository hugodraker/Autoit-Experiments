#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <FileConstants.au3>

Global $hGUI = GUICreate("Large Text File Search", 800, 600)

GUICtrlCreateLabel("Text File:", 10, 15, 60, 20)
Global $idFile = GUICtrlCreateInput("", 70, 10, 580, 25)

Global $idBrowse = GUICtrlCreateButton("Browse...", 660, 10, 100, 25)

GUICtrlCreateLabel("Search Text:", 10, 50, 80, 20)
Global $idSearch = GUICtrlCreateInput("", 90, 45, 250, 25)

Global $idStart = GUICtrlCreateButton("Search", 360, 45, 100, 25)

Global $idStatus = GUICtrlCreateLabel("Ready", 10, 80, 500, 20)

Global $idResults = GUICtrlCreateList("", 10, 110, 770, 430)

GUISetState(@SW_SHOW)

While 1
    Switch GUIGetMsg()

        Case $GUI_EVENT_CLOSE
            Exit

        Case $idBrowse
            Local $sFile = FileOpenDialog( _
                    "Select Text File", _
                    @ScriptDir, _
                    "Text Files (*.txt)|All Files (*.*)")

            If Not @error Then
                GUICtrlSetData($idFile, $sFile)
            EndIf

        Case $idStart

            Local $sFile = GUICtrlRead($idFile)
            Local $sSearch = GUICtrlRead($idSearch)

            If $sFile = "" Then
                MsgBox(16, "Error", "Please select a file.")
                ContinueLoop
            EndIf

            If $sSearch = "" Then
                MsgBox(16, "Error", "Please enter search text.")
                ContinueLoop
            EndIf

            _SearchFile($sFile, $sSearch)

    EndSwitch
WEnd

Func _SearchFile($sFile, $sSearch)

    GUICtrlSetData($idResults, "")
    GUICtrlSetData($idStatus, "Searching...")

    Local $hFile = FileOpen($sFile, $FO_READ)

    If $hFile = -1 Then
        MsgBox(16, "Error", "Unable to open file.")
        Return
    EndIf

    Local $iLine = 0
    Local $iMatches = 0

    While 1

        Local $sLine = FileReadLine($hFile)

        If @error Then ExitLoop

        $iLine += 1

        ; Keep GUI responsive
        If Mod($iLine, 1000) = 0 Then
            GUICtrlSetData($idStatus, _
                "Searching... Line " & $iLine & _
                " | Matches: " & $iMatches)
            Sleep(1)
        EndIf

        If StringInStr($sLine, $sSearch, 2) Then

            $iMatches += 1

            GUICtrlSetData( _
                $idResults, _
                "Line " & $iLine & "|" , _
                1)
        EndIf

    WEnd

    FileClose($hFile)

    GUICtrlSetData( _
        $idStatus, _
        "Finished. " & $iMatches & _
        " matches found in " & $iLine & _
        " lines.")

EndFunc