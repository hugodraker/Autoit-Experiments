#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <EditConstants.au3>
#include <ComboConstants.au3>
#include <Array.au3>
#include <FileConstants.au3>

; INI file matches THIS script’s name
Global $g_sHistoryFile = @ScriptDir & "\" & StringTrimRight(@ScriptName, 4) & ".ini"

; aHistory[0] unused for simplicity, real entries start at 1
Global $aHistory[1] = [""]

; -------------------------
; Main GUI
; -------------------------
$hGUI = GUICreate("Command Runner", 700, 650, -1, -1, BitOR($WS_SIZEBOX, $WS_SYSMENU, $WS_MINIMIZEBOX))

GUICtrlCreateLabel("Command (script + params):", 10, 15, 200, 20)
Global $txtCommand = GUICtrlCreateEdit("", 10, 40, 680, 200, BitOR($ES_AUTOVSCROLL, $WS_VSCROLL))

Global $btnBrowse        = GUICtrlCreateButton("Browse",        90, 255, 120, 35)
Global $btnRun           = GUICtrlCreateButton("Run",          260, 255, 120, 35)
Global $btnClearLast     = GUICtrlCreateButton("Clear Last",   430, 255, 120, 35)
Global $btnClearHistory  = GUICtrlCreateButton("Clear History",560, 255, 120, 35)

GUICtrlCreateLabel("History:", 10, 305, 80, 20)
Global $cmbHistory = GUICtrlCreateCombo("", 90, 300, 600, 25, $CBS_DROPDOWNLIST)

GUICtrlCreateLabel("Output:", 10, 350, 80, 20)
Global $txtOutput = GUICtrlCreateEdit("", 10, 375, 680, 250, BitOR($ES_READONLY, $ES_AUTOVSCROLL, $WS_VSCROLL))

_LoadHistory()
_UpdateHistoryDropdown()

GUISetState(@SW_SHOW)

; -------------------------
; Main Loop
; -------------------------
While True
    Switch GUIGetMsg()
        Case $GUI_EVENT_CLOSE
            _SaveHistory()
            Exit

        Case $btnBrowse
            _BrowseScript()

        Case $btnRun
            _RunCommand()

        Case $btnClearLast
            GUICtrlSetData($txtCommand, "")

        Case $btnClearHistory
            _ClearHistory()

        Case $cmbHistory
            Local $sel = GUICtrlRead($cmbHistory)
            If $sel <> "" Then GUICtrlSetData($txtCommand, $sel)
    EndSwitch
WEnd

; -------------------------
; Browse for script
; -------------------------
Func _BrowseScript()
    Local $file = FileOpenDialog("Select AutoIt Script", @ScriptDir, "AutoIt Scripts (*.au3)", $FD_FILEMUSTEXIST)
    If @error Then Return

    GUICtrlSetData($txtCommand, '"' & $file & '" ')
EndFunc

Func _RunCommand()
    Local $cmd = StringStripWS(GUICtrlRead($txtCommand), 3)
    If $cmd = "" Then
        MsgBox(48, "Error", "Please enter a script and parameters.")
        Return
    EndIf

    ; Check uniqueness manually
    If Not _IsInHistory($cmd) Then
        _AddToHistory($cmd)
        _UpdateHistoryDropdown()
    EndIf

    ; NEW: select last run command in dropdown
    GUICtrlSetData($cmbHistory, $cmd)

    GUICtrlSetData($txtOutput, "")

    Local Const $RUN_CREATE_NEW_CONSOLE = 0x00010000
    Local Const $RUN_STDOUT_CHILD      = 0x00000002

    Local $pid = Run(@AutoItExe & " " & $cmd, "", @SW_HIDE, $RUN_CREATE_NEW_CONSOLE + $RUN_STDOUT_CHILD)
    If $pid = 0 Then
        GUICtrlSetData($txtOutput, "Failed to run command.")
        Return
    EndIf

    Local $sOut = ""
    While 1
        Local $line = StdoutRead($pid)
        If @error Then ExitLoop
        $sOut &= $line
        GUICtrlSetData($txtOutput, $sOut)
    WEnd
EndFunc


; -------------------------
; Check if command is already in history
; -------------------------
Func _IsInHistory($cmd)
    Local $ub = UBound($aHistory) - 1
    For $i = 1 To $ub
        If $aHistory[$i] = $cmd Then Return True
    Next
    Return False
EndFunc

; -------------------------
; Add command to history array
; -------------------------
Func _AddToHistory($cmd)
    Local $ub = UBound($aHistory)
    ReDim $aHistory[$ub + 1]
    $aHistory[$ub] = $cmd
EndFunc

; -------------------------
; Rebuild history dropdown from array
; -------------------------
Func _UpdateHistoryDropdown()
    GUICtrlSetData($cmbHistory, "") ; clear all
    Local $ub = UBound($aHistory) - 1
    For $i = 1 To $ub
        GUICtrlSetData($cmbHistory, $aHistory[$i])
    Next
EndFunc

; -------------------------
; Load History
; -------------------------
Func _LoadHistory()
    Local $count = IniRead($g_sHistoryFile, "History", "Count", 0)

    ReDim $aHistory[$count + 1]
    $aHistory[0] = ""

    For $i = 1 To $count
        $aHistory[$i] = IniRead($g_sHistoryFile, "History", $i, "")
    Next
EndFunc

; -------------------------
; Save History
; -------------------------
Func _SaveHistory()
    Local $count = UBound($aHistory) - 1
    IniWrite($g_sHistoryFile, "History", "Count", $count)

    For $i = 1 To $count
        IniWrite($g_sHistoryFile, "History", $i, $aHistory[$i])
    Next
EndFunc

; -------------------------
; Clear History
; -------------------------
Func _ClearHistory()
    ReDim $aHistory[1]
    $aHistory[0] = ""
    _UpdateHistoryDropdown()
EndFunc
