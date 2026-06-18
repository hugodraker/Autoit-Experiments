#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <ListViewConstants.au3>
#include <EditConstants.au3>
#include <FileConstants.au3>
#include <MsgBoxConstants.au3>
#include <GuiListView.au3>

Global $g_bStop = False
Global $g_hFile = -1
Global $g_iLine = 0
Global $g_sTerm = ""
Global $g_sFile = ""

; -----------------------------
; GUI SETUP
; -----------------------------
$hGUI = GUICreate("FAST Large File Search Tool", 900, 650, -1, -1, _
    BitOR($WS_SIZEBOX, $WS_MAXIMIZEBOX, $WS_MINIMIZEBOX))

GUICtrlCreateLabel("Text File:", 10, 10, 60, 20)
$inpFile = GUICtrlCreateInput("", 70, 8, 650, 22)
$btnBrowse = GUICtrlCreateButton("Browse", 730, 8, 80, 22)

GUICtrlCreateLabel("Search Term:", 10, 40, 80, 20)
$inpSearch = GUICtrlCreateInput("", 100, 38, 300, 22)

$btnStart = GUICtrlCreateButton("Start Search", 420, 38, 120, 22)
$btnStop  = GUICtrlCreateButton("Stop", 550, 38, 120, 22)
GUICtrlSetBkColor($btnStop, 0x00AA00) ; green initially

$lblStatus = GUICtrlCreateLabel("Status: Idle", 10, 70, 400, 20)

$lvResults = GUICtrlCreateListView("Line #|Content", 10, 100, 870, 530, _
    BitOR($LVS_REPORT, $LVS_SHOWSELALWAYS))
_GUICtrlListView_SetColumnWidth($lvResults, 0, 80)
_GUICtrlListView_SetColumnWidth($lvResults, 1, 760)

GUISetState(@SW_SHOW)

; -----------------------------
; MAIN LOOP
; -----------------------------
While True
    Switch GUIGetMsg()
        Case $GUI_EVENT_CLOSE
            Exit

        Case $btnBrowse
            Local $sFile = FileOpenDialog("Select Text File", @ScriptDir, _
                "Text Files (*.txt)|All (*.*)", 1)
            If Not @error Then GUICtrlSetData($inpFile, $sFile)

        Case $btnStart
            _StartSearch()

        Case $btnStop
            $g_bStop = True
    EndSwitch
WEnd


; -----------------------------
; START SEARCH
; -----------------------------
Func _StartSearch()
    $g_sFile = GUICtrlRead($inpFile)
    $g_sTerm = GUICtrlRead($inpSearch)

    If Not FileExists($g_sFile) Then
        MsgBox($MB_ICONERROR, "Error", "File does not exist.")
        Return
    EndIf

    If $g_sTerm = "" Then
        MsgBox($MB_ICONERROR, "Error", "Enter a search term.")
        Return
    EndIf

    ; Reset UI
    GUICtrlSetData($lblStatus, "Status: Searching...")
    GUICtrlSetBkColor($btnStop, 0xAA0000) ; red
    GUICtrlDelete($lvResults)
    $lvResults = GUICtrlCreateListView("Line #|Content", 10, 100, 870, 530, _
        BitOR($LVS_REPORT, $LVS_SHOWSELALWAYS))
    _GUICtrlListView_SetColumnWidth($lvResults, 0, 80)
    _GUICtrlListView_SetColumnWidth($lvResults, 1, 760)

    $g_bStop = False
    $g_iLine = 0

    $g_hFile = FileOpen($g_sFile, $FO_READ)
    If $g_hFile = -1 Then
        MsgBox($MB_ICONERROR, "Error", "Unable to open file.")
        Return
    EndIf

    AdlibRegister("_SearchWorker", 5)
EndFunc


; -----------------------------
; SEARCH WORKER (FAST)
; -----------------------------
Func _SearchWorker()
    If $g_bStop Then
        _EndSearch("Stopped.")
        Return
    EndIf

    ; Read 4000 lines per cycle for speed
    For $i = 1 To 4000
        Local $sLine = FileReadLine($g_hFile)
        If @error Then
            _EndSearch("Completed.")
            Return
        EndIf

        $g_iLine += 1
        GUICtrlSetData($lblStatus, "Searching line: " & $g_iLine)

        If StringInStr($sLine, $g_sTerm, 0) > 0 Then
            GUICtrlCreateListViewItem($g_iLine & "|" & $sLine, $lvResults)
        EndIf

        If $g_bStop Then
            _EndSearch("Stopped.")
            Return
        EndIf
    Next
EndFunc


; -----------------------------
; END SEARCH
; -----------------------------
Func _EndSearch($sMsg)
    AdlibUnRegister("_SearchWorker")
    FileClose($g_hFile)

    GUICtrlSetData($lblStatus, "Status: " & $sMsg)
    GUICtrlSetBkColor($btnStop, 0x00AA00) ; green
EndFunc
