#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <ListViewConstants.au3>
#include <FileConstants.au3>
#include <GuiListView.au3>
#include <MsgBoxConstants.au3>
#include <Array.au3>
#include <File.au3>

Global $g_bSearching = False
Global $g_hFile = -1
Global $g_iLine = 0
Global $g_sTerm = ""
Global $g_sFile = ""
Global $g_sCurrentDir = ""
Global $g_sBaseFolder = ""
Global $g_aResults[0][3] ; [filename][directory][line number]

; -----------------------------
; GUI SETUP
; -----------------------------
$hGUI = GUICreate("DIR Search Tool", 950, 650, -1, -1, _
    BitOR($WS_SIZEBOX, $WS_MAXIMIZEBOX, $WS_MINIMIZEBOX))

GUICtrlCreateLabel("DIR Output File:", 10, 10, 120, 20)
$inpFile = GUICtrlCreateInput("", 130, 8, 600, 22)
$btnBrowse = GUICtrlCreateButton("Browse", 740, 8, 80, 22)
$btnIndex = GUICtrlCreateButton("Index Folder", 830, 8, 100, 22)

GUICtrlCreateLabel("Search Term:", 10, 40, 100, 20)
$inpSearch = GUICtrlCreateInput("", 110, 38, 300, 22)

$btnSearch = GUICtrlCreateButton("Search", 420, 38, 120, 22)
GUICtrlSetBkColor($btnSearch, 0x00AA00)

$lblStatus = GUICtrlCreateLabel("Status: Idle", 10, 70, 400, 20)

$lvResults = GUICtrlCreateListView("File Name|Directory|Line", 10, 100, 930, 530, _
    BitOR($LVS_REPORT, $LVS_SHOWSELALWAYS))
_GUICtrlListView_SetColumnWidth($lvResults, 0, 200)
_GUICtrlListView_SetColumnWidth($lvResults, 1, 600)
_GUICtrlListView_SetColumnWidth($lvResults, 2, 80)

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

        Case $btnIndex
            _IndexFolder()

        Case $btnSearch
            If Not $g_bSearching Then
                _StartSearch()
            Else
                $g_bSearching = False
            EndIf

        Case $lvResults
            _HandleListClick()
    EndSwitch
WEnd


; -----------------------------
; INDEX FOLDER (NATIVE AUTOIT)
; -----------------------------
Func _IndexFolder()
    Local $folder = FileSelectFolder("Select folder to index", "")
    If @error Or $folder = "" Then Return

    $g_sBaseFolder = $folder

    Local $outfile = $folder & "\index.txt"
    Local $hOut = FileOpen($outfile, $FO_OVERWRITE)

    If $hOut = -1 Then
        MsgBox(16, "Error", "Unable to create index file.")
        Return
    EndIf

    Local $aFiles = _FileListToArrayRec($folder, "*", $FLTAR_FILES, $FLTAR_RECUR, $FLTAR_NOSORT)
    If @error Then
        MsgBox(16, "Error", "No files found.")
        FileClose($hOut)
        Return
    EndIf

    Local $currentDir = ""

    For $i = 1 To $aFiles[0]
        Local $full = $aFiles[$i]
        Local $dir = StringTrimRight($full, StringLen(StringRegExpReplace($full, "^.*\\", "")) + 1)
        Local $file = StringRegExpReplace($full, "^.*\\", "")

        If $dir <> $currentDir Then
            FileWriteLine($hOut, " Directory of " & $dir)
            $currentDir = $dir
        EndIf

        FileWriteLine($hOut, "01/01/2000  12:00 PM              0 " & $file)
    Next

    FileClose($hOut)

    GUICtrlSetData($inpFile, $outfile)
    MsgBox(64, "Index Complete", "Index file created:" & @CRLF & $outfile)
EndFunc


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

    GUICtrlSetData($lblStatus, "Status: Searching...")
    GUICtrlSetData($btnSearch, "Stop")
    GUICtrlSetBkColor($btnSearch, 0xAA0000)

    GUICtrlDelete($lvResults)
    $lvResults = GUICtrlCreateListView("File Name|Directory|Line", 10, 100, 930, 530, _
        BitOR($LVS_REPORT, $LVS_SHOWSELALWAYS))
    _GUICtrlListView_SetColumnWidth($lvResults, 0, 200)
    _GUICtrlListView_SetColumnWidth($lvResults, 1, 600)
    _GUICtrlListView_SetColumnWidth($lvResults, 2, 80)

    ReDim $g_aResults[0][3]
    $g_bSearching = True
    $g_iLine = 0
    $g_sCurrentDir = ""

    $g_hFile = FileOpen($g_sFile, $FO_READ)
    If $g_hFile = -1 Then
        MsgBox(16, "Error", "Unable to open file.")
        Return
    EndIf

    _SearchWorker()
EndFunc


; -----------------------------
; SEARCH WORKER (with GUI event processing)
; -----------------------------
Func _SearchWorker()
    While $g_bSearching

        For $i = 1 To 4000

            ; *** NEW: Allow clicking during search ***
            Local $msg = GUIGetMsg()
            Switch $msg
                Case $lvResults
                    _HandleListClick()
                Case $btnSearch
                    $g_bSearching = False
                    ExitLoop 2
            EndSwitch

            If Not $g_bSearching Then ExitLoop 2

            Local $sLine = FileReadLine($g_hFile)
            If @error Then
                $g_bSearching = False
                ExitLoop 2
            EndIf

            $g_iLine += 1

            If Mod($g_iLine, 100) = 0 Then
                GUICtrlSetData($lblStatus, "Scanning line: " & $g_iLine)
            EndIf

            If StringInStr($sLine, " Directory of ") Then
                $g_sCurrentDir = StringTrimLeft($sLine, StringInStr($sLine, "Directory of ") + 12)
                ContinueLoop
            EndIf

            If StringRegExp($sLine, "^\d{2}/\d{2}/\d{4}") Then
                Local $aParts = StringSplit(StringStripWS($sLine, 3), " ")
                Local $sFileName = $aParts[$aParts[0]]

                If ($g_sTerm = "") Or (StringInStr($sFileName, $g_sTerm, 0) > 0) Then

                    Local $fullDir = $g_sCurrentDir
                    If StringLeft($fullDir, StringLen($g_sBaseFolder)) <> $g_sBaseFolder Then
                        $fullDir = $g_sBaseFolder & "\" & $fullDir
                    EndIf

                    Local $idx = UBound($g_aResults)
                    ReDim $g_aResults[$idx + 1][3]
                    $g_aResults[$idx][0] = $sFileName
                    $g_aResults[$idx][1] = $fullDir
                    $g_aResults[$idx][2] = $g_iLine

                    GUICtrlCreateListViewItem($sFileName & "|" & $fullDir & "|" & $g_iLine, $lvResults)
                EndIf
            EndIf

        Next

        Sleep(1)
    WEnd

    _EndSearch()
EndFunc


; -----------------------------
; HANDLE LIST CLICK
; -----------------------------
Func _HandleListClick()
    Local $iIndex = _GUICtrlListView_GetNextItem($lvResults)
    If $iIndex < 0 Then Return

    Local $sFile = $g_aResults[$iIndex][0]
    Local $sDir  = $g_aResults[$iIndex][1]

    Switch @GUI_Event
        Case $GUI_EVENT_DBLCLICK
            ShellExecute($sDir & "\" & $sFile)

        Case $GUI_EVENT_SECONDARYDOWN
            ShellExecute($sDir)
    EndSwitch
EndFunc


; -----------------------------
; END SEARCH
; -----------------------------
Func _EndSearch()
    FileClose($g_hFile)

    GUICtrlSetData($lblStatus, "Status: Done")
    GUICtrlSetData($btnSearch, "Search")
    GUICtrlSetBkColor($btnSearch, 0x00AA00)
EndFunc
