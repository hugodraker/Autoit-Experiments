#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <ListViewConstants.au3>
#include <FileConstants.au3>
#include <GuiListView.au3>
#include <MsgBoxConstants.au3>

Global $g_bStop = False
Global $g_hFile = -1
Global $g_iLine = 0
Global $g_sTerm = ""
Global $g_sFile = ""
Global $g_sCurrentDir = ""
Global $g_aResults[0][2] ; [filename][directory]

; -----------------------------
; GUI SETUP
; -----------------------------
$hGUI = GUICreate("DIR Search Tool", 900, 650, -1, -1, _
    BitOR($WS_SIZEBOX, $WS_MAXIMIZEBOX, $WS_MINIMIZEBOX))

GUICtrlCreateLabel("DIR Output File:", 10, 10, 120, 20)
$inpFile = GUICtrlCreateInput("", 130, 8, 600, 22)
$btnBrowse = GUICtrlCreateButton("Browse", 740, 8, 80, 22)

GUICtrlCreateLabel("Search Term:", 10, 40, 100, 20)
$inpSearch = GUICtrlCreateInput("", 110, 38, 300, 22)

$btnStart = GUICtrlCreateButton("Start Search", 420, 38, 120, 22)
$btnStop  = GUICtrlCreateButton("Stop", 550, 38, 120, 22)
GUICtrlSetBkColor($btnStop, 0x00AA00) ; green

$lblStatus = GUICtrlCreateLabel("Status: Idle", 10, 70, 400, 20)

$lvResults = GUICtrlCreateListView("File Name|Directory", 10, 100, 870, 530, _
    BitOR($LVS_REPORT, $LVS_SHOWSELALWAYS))
_GUICtrlListView_SetColumnWidth($lvResults, 0, 200)
_GUICtrlListView_SetColumnWidth($lvResults, 1, 650)

GUISetState(@SW_SHOW)

; -----------------------------
; MAIN LOOP
; -----------------------------
While True
    Local $msg = GUIGetMsg()

    Switch $msg
        Case $GUI_EVENT_CLOSE
            Exit

        Case $btnBrowse
            Local $sFile = FileOpenDialog("Select DIR Output File", @ScriptDir, _
                "Text Files (*.txt)|All (*.*)", 1)
            If Not @error Then GUICtrlSetData($inpFile, $sFile)

        Case $btnStart
            _StartSearch()

        Case $btnStop
            $g_bStop = True

        Case $lvResults
            _ShowClickedItem()
    EndSwitch
WEnd


; -----------------------------
; START SEARCH
; -----------------------------
Func _StartSearch()
    $g_sFile = GUICtrlRead($inpFile)
    $g_sTerm = GUICtrlRead($inpSearch)

    If Not FileExists($g_sFile) Then
        MsgBox(16, "Error", "File does not exist.")
        Return
    EndIf

    If $g_sTerm = "" Then
        MsgBox(16, "Error", "Enter a search term.")
        Return
    EndIf

    ; Reset UI
    GUICtrlSetData($lblStatus, "Status: Searching...")
    GUICtrlSetBkColor($btnStop, 0xAA0000) ; red
    GUICtrlDelete($lvResults)
    $lvResults = GUICtrlCreateListView("File Name|Directory", 10, 100, 870, 530, _
        BitOR($LVS_REPORT, $LVS_SHOWSELALWAYS))
    _GUICtrlListView_SetColumnWidth($lvResults, 0, 200)
    _GUICtrlListView_SetColumnWidth($lvResults, 1, 650)

    ReDim $g_aResults[0][2]
    $g_bStop = False
    $g_iLine = 0
    $g_sCurrentDir = ""

    $g_hFile = FileOpen($g_sFile, $FO_READ)
    If $g_hFile = -1 Then
        MsgBox(16, "Error", "Unable to open file.")
        Return
    EndIf

    AdlibRegister("_SearchWorker", 5)
EndFunc


; -----------------------------
; SEARCH WORKER
; -----------------------------
Func _SearchWorker()
    If $g_bStop Then
        _EndSearch("Stopped.")
        Return
    EndIf

    For $i = 1 To 4000

        If $g_bStop Then
            _EndSearch("Stopped.")
            Return
        EndIf

        Local $sLine = FileReadLine($g_hFile)
        If @error Then
            _EndSearch("Completed.")
            Return
        EndIf

        $g_iLine += 1

        ; Update status every 100 lines
        If Mod($g_iLine, 100) = 0 Then
            GUICtrlSetData($lblStatus, "Scanning line: " & $g_iLine)
        EndIf

        ; Detect directory header
        If StringInStr($sLine, " Directory of ") Then
            $g_sCurrentDir = StringTrimLeft($sLine, StringInStr($sLine, "Directory of ") + 12)
            ContinueLoop
        EndIf

        ; Detect file line (starts with date)
        If StringRegExp($sLine, "^\d{2}/\d{2}/\d{4}") Then
            Local $aParts = StringSplit(StringStripWS($sLine, 3), " ")
            Local $sFileName = $aParts[$aParts[0]]

            If StringInStr($sFileName, $g_sTerm, 0) > 0 Then
                Local $idx = UBound($g_aResults)
                ReDim $g_aResults[$idx + 1][2]
                $g_aResults[$idx][0] = $sFileName
                $g_aResults[$idx][1] = $g_sCurrentDir

                GUICtrlCreateListViewItem($sFileName & "|" & $g_sCurrentDir, $lvResults)
            EndIf
        EndIf

    Next
EndFunc


; -----------------------------
; SHOW CLICKED ITEM
; -----------------------------
Func _ShowClickedItem()
    Local $iIndex = _GUICtrlListView_GetNextItem($lvResults)
    If $iIndex < 0 Then Return

    Local $sFile = $g_aResults[$iIndex][0]
    Local $sDir  = $g_aResults[$iIndex][1]

    MsgBox(64, "File Info", _
        "File: " & $sFile & @CRLF & _
        "Directory: " & $sDir)
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
