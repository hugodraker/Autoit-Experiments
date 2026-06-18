#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <GuiListView.au3>
#include <ListViewConstants.au3>
#include <FileConstants.au3>

Global $g_bCancel = False

; ==================================================
; GUI
; ==================================================

Global $hGUI = GUICreate("Large File Search", 1000, 700)

GUICtrlCreateLabel("File:", 10, 15, 40, 20)
Global $idFile = GUICtrlCreateInput("", 50, 10, 760, 24)

Global $idBrowse = GUICtrlCreateButton("Browse", 820, 10, 80, 24)

GUICtrlCreateLabel("Search:", 10, 45, 50, 20)
Global $idSearch = GUICtrlCreateInput("", 70, 40, 250, 24)

Global $idStart = GUICtrlCreateButton("Start Search", 340, 40, 110, 28)
Global $idStop = GUICtrlCreateButton("Stop", 460, 40, 80, 28)

Global $idStatus = GUICtrlCreateLabel("Ready", 10, 75, 800, 20)

Global $idLV = GUICtrlCreateListView( _
    "Line Number|Line Contents", _
    10, 100, 975, 580, _
    BitOR($LVS_REPORT, $LVS_SHOWSELALWAYS))

_GUICtrlListView_SetExtendedListViewStyle( _
    GUICtrlGetHandle($idLV), _
    BitOR($LVS_EX_FULLROWSELECT, _
          $LVS_EX_GRIDLINES, _
          $LVS_EX_DOUBLEBUFFER))

_GUICtrlListView_SetColumnWidth( _
    GUICtrlGetHandle($idLV), 0, 100)

_GUICtrlListView_SetColumnWidth( _
    GUICtrlGetHandle($idLV), 1, 840)

GUISetState()

; ==================================================
; MAIN LOOP
; ==================================================

While 1

    Switch GUIGetMsg()

        Case $GUI_EVENT_CLOSE
            Exit

        Case $idBrowse

            Local $sFile = FileOpenDialog( _
                "Select File", _
                @ScriptDir, _
                "Text Files (*.txt)|All Files (*.*)")

            If Not @error Then
                GUICtrlSetData($idFile, $sFile)
            EndIf

        Case $idStart

            Local $sFile = GUICtrlRead($idFile)
            Local $sSearch = GUICtrlRead($idSearch)

            If $sFile = "" Then
                MsgBox(16, "Error", "Select a file.")
                ContinueLoop
            EndIf

            If $sSearch = "" Then
                MsgBox(16, "Error", "Enter search text.")
                ContinueLoop
            EndIf

            $g_bCancel = False

            _SearchFile($sFile, $sSearch)

    EndSwitch

WEnd

; ==================================================
; SEARCH
; ==================================================

Func _SearchFile($sFile, $sSearch)

    _GUICtrlListView_DeleteAllItems( _
        GUICtrlGetHandle($idLV))

    GUICtrlSetData($idStatus, "Searching...")

    Local $hFile = FileOpen($sFile, $FO_READ)

    If $hFile = -1 Then
        MsgBox(16, "Error", "Cannot open file.")
        Return
    EndIf

    Local $iLine = 0
    Local $iMatches = 0

    While 1

        ; Check GUI events during search
        Switch GUIGetMsg()

            Case $GUI_EVENT_CLOSE
                FileClose($hFile)
                Exit

            Case $idStop
                $g_bCancel = True

        EndSwitch

        If $g_bCancel Then ExitLoop

        Local $sLine = FileReadLine($hFile)

        If @error Then ExitLoop

        $iLine += 1

        If StringInStr($sLine, $sSearch, 2) Then

            $iMatches += 1

            Local $idx = GUICtrlCreateListViewItem( _
                $iLine & "|" & $sLine, _
                $idLV)

        EndIf

        If Mod($iLine, 1000) = 0 Then

            GUICtrlSetData( _
                $idStatus, _
                "Searching... Lines: " & _
                $iLine & _
                "  Matches: " & _
                $iMatches)

        EndIf

    WEnd

    FileClose($hFile)

    If $g_bCancel Then

        GUICtrlSetData( _
            $idStatus, _
            "Stopped. Lines scanned: " & _
            $iLine & _
            "  Matches: " & _
            $iMatches)

    Else

        GUICtrlSetData( _
            $idStatus, _
            "Finished. Lines scanned: " & _
            $iLine & _
            "  Matches: " & _
            $iMatches)

    EndIf

EndFunc