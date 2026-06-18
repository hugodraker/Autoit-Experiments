#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <EditConstants.au3>
#include <ListViewConstants.au3>
#include <FileConstants.au3>
#include <MsgBoxConstants.au3>

Global $g_bStop = False
Global $g_hSearchThread = 0

; -----------------------------
; GUI SETUP
; -----------------------------
$hGUI = GUICreate("Large File Search Tool", 800, 600, -1, -1, BitOR($WS_SIZEBOX, $WS_MAXIMIZEBOX, $WS_MINIMIZEBOX))

GUICtrlCreateLabel("Text File:", 10, 10, 60, 20)
$inpFile = GUICtrlCreateInput("", 70, 8, 550, 22)
$btnBrowse = GUICtrlCreateButton("Browse", 630, 8, 80, 22)

GUICtrlCreateLabel("Search Term:", 10, 40, 80, 20)
$inpSearch = GUICtrlCreateInput("", 100, 38, 300, 22)

$btnStart = GUICtrlCreateButton("Start Search", 420, 38, 120, 22)
$btnStop  = GUICtrlCreateButton("Stop", 550, 38, 80, 22)

$lvResults = GUICtrlCreateListView("Line #|Content", 10, 70, 770, 500, BitOR($LVS_REPORT, $LVS_SHOWSELALWAYS))
;_GUICtrlListView_SetColumnWidth($lvResults, 0, 80)
;_GUICtrlListView_SetColumnWidth($lvResults, 1, 650)

GUISetState(@SW_SHOW)

; -----------------------------
; MAIN LOOP
; -----------------------------
While True
    Switch GUIGetMsg()
        Case $GUI_EVENT_CLOSE
            Exit

        Case $btnBrowse
            Local $sFile = FileOpenDialog("Select Text File", @ScriptDir, "Text Files (*.txt)|All (*.*)", 1)
            If Not @error Then GUICtrlSetData($inpFile, $sFile)

        Case $btnStart
            _StartSearch()

        Case $btnStop
            $g_bStop = True
    EndSwitch
WEnd


; -----------------------------
; START SEARCH FUNCTION
; -----------------------------
Func _StartSearch()
    Local $sFile = GUICtrlRead($inpFile)
    Local $sTerm = GUICtrlRead($inpSearch)

    If Not FileExists($sFile) Then
        MsgBox($MB_ICONERROR, "Error", "File does not exist.")
        Return
    EndIf

    If $sTerm = "" Then
        MsgBox($MB_ICONERROR, "Error", "Enter a search term.")
        Return
    EndIf

    GUICtrlDelete($lvResults)
    $lvResults = GUICtrlCreateListView("Line #|Content", 10, 70, 770, 500, BitOR($LVS_REPORT, $LVS_SHOWSELALWAYS))
;    _GUICtrlListView_SetColumnWidth($lvResults, 0, 80)
 ;   _GUICtrlListView_SetColumnWidth($lvResults, 1, 650)

    $g_bStop = False

    AdlibRegister("_SearchWorker", 10)
    $g_hSearchThread = TimerInit()

    Global $g_sFile = $sFile
    Global $g_sTerm = $sTerm
    Global $g_iLine = 0
    Global $g_hFile = FileOpen($sFile, $FO_READ)
EndFunc


; -----------------------------
; SEARCH WORKER (runs repeatedly)
; -----------------------------
Func _SearchWorker()
    If $g_bStop Then
        AdlibUnRegister("_SearchWorker")
        FileClose($g_hFile)
        Return
    EndIf

    Local $sLine = FileReadLine($g_hFile)
    If @error Then
        AdlibUnRegister("_SearchWorker")
        FileClose($g_hFile)
        Return
    EndIf

    $g_iLine += 1

    If StringInStr($sLine, $g_sTerm, 0) > 0 Then
        GUICtrlCreateListViewItem($g_iLine & "|" & $sLine, $lvResults)
    EndIf
EndFunc
