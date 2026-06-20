#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <GuiListBox.au3>
#include <MsgBoxConstants.au3>

Global $g_sCurrentPDF = ""
Global $g_iPageCount = 0

; GUI
$hGUI = GUICreate("PDF Page Counter", 700, 600, -1, -1, _
        BitOR($WS_SIZEBOX, $WS_MAXIMIZEBOX, $WS_MINIMIZEBOX))

; Menu
$mFile   = GUICtrlCreateMenu("&File")
$mOpen   = GUICtrlCreateMenuItem("Open", $mFile)
$mSave   = GUICtrlCreateMenuItem("Save", $mFile)
$mSaveAs = GUICtrlCreateMenuItem("Save As", $mFile)
GUICtrlCreateMenuItem("", $mFile)
$mExit   = GUICtrlCreateMenuItem("Exit", $mFile)

$mHelp   = GUICtrlCreateMenu("&Help")
$mManual = GUICtrlCreateMenuItem("User Manual", $mHelp)
$mAbout  = GUICtrlCreateMenuItem("About", $mHelp)

; Listbox (multi-select, fills window)
$lbPages = GUICtrlCreateList("", 10, 10, 680, 540, _
        BitOR($WS_BORDER, $LBS_EXTENDEDSEL))

GUISetState(@SW_SHOW)

; Resize handler
GUIRegisterMsg($WM_SIZE, "WM_SIZE")
Func WM_SIZE($hWnd, $iMsg, $wParam, $lParam)
    Local $iW = BitAND($lParam, 0xFFFF)
    Local $iH = BitShift($lParam, 16)
    GUICtrlSetPos($lbPages, 10, 10, $iW - 20, $iH - 20)
EndFunc

; --- Better native PDF page counter ---
Func _PDF_GetPageCount($sFile)
    Local $hFile = FileOpen($sFile, 16) ; binary read
    If $hFile = -1 Then Return 0

    Local $data = FileRead($hFile)
    FileClose($hFile)

    If @error Or $data = "" Then Return 0

    ; Convert binary to string for regex scanning
    $data = BinaryToString($data)

    ; Find ALL /Count <num> occurrences
    Local $aMatches = StringRegExp($data, "/Count\s+(\d+)", 3)
    If Not IsArray($aMatches) Then Return 1

    ; Determine the highest count (true page count)
    Local $max = 0
    For $i = 0 To UBound($aMatches) - 1
        Local $n = Number($aMatches[$i])
        If $n > $max Then $max = $n
    Next

    If $max < 1 Then $max = 1
    Return $max
EndFunc


; Load PDF and populate listbox
Func LoadPDF($sFile)
    $g_sCurrentPDF = $sFile
    $g_iPageCount = _PDF_GetPageCount($sFile)

    GUICtrlSetData($lbPages, "")

    If $g_iPageCount <= 0 Then
        GUICtrlSetData($lbPages, "Unable to detect page count.")
        Return
    EndIf

    For $i = 1 To $g_iPageCount
        GUICtrlSetData($lbPages, "Page " & $i)
    Next
EndFunc

; Main loop
While True
    Switch GUIGetMsg()
        Case $GUI_EVENT_CLOSE, $mExit
            Exit

        Case $mOpen
            Local $sFile = FileOpenDialog("Open PDF", @ScriptDir, "PDF Files (*.pdf)", 1)
            If Not @error Then LoadPDF($sFile)

        Case $mSave
            MsgBox($MB_ICONINFORMATION, "Save", "Save functionality not implemented.")

        Case $mSaveAs
            Local $sOut = FileSaveDialog("Save PDF As", @ScriptDir, "PDF Files (*.pdf)", 2)
            If Not @error And $g_sCurrentPDF <> "" Then
                FileCopy($g_sCurrentPDF, $sOut, 1)
            EndIf

        Case $mManual
            MsgBox($MB_ICONINFORMATION, "User Manual", "User manual goes here.")

        Case $mAbout
            MsgBox($MB_ICONINFORMATION, "About", "AutoIt PDF Page Counter Example.")
    EndSwitch
WEnd
