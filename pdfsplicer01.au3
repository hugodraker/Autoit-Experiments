#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <MsgBoxConstants.au3>
#include <Array.au3>
#include <GuiListBox.au3>

Global $g_sCurrentPDF = ""
Global $g_iPageCount = 0

; Create GUI
$hGUI = GUICreate("PDF Viewer", 900, 700, -1, -1, BitOR($WS_SIZEBOX, $WS_MAXIMIZEBOX, $WS_MINIMIZEBOX))

; Menu
$mFile = GUICtrlCreateMenu("&File")
$mOpen = GUICtrlCreateMenuItem("Open", $mFile)
$mSave = GUICtrlCreateMenuItem("Save", $mFile)
$mSaveAs = GUICtrlCreateMenuItem("Save As", $mFile)
GUICtrlCreateMenuItem("", $mFile)
$mExit = GUICtrlCreateMenuItem("Exit", $mFile)

$mHelp = GUICtrlCreateMenu("&Help")
$mManual = GUICtrlCreateMenuItem("User Manual", $mHelp)
$mAbout = GUICtrlCreateMenuItem("About", $mHelp)

; Listbox for page numbers
$lbPages = GUICtrlCreateList("", 10, 10, 200, 650, BitOR($WS_BORDER, $LBS_EXTENDEDSEL))

; Embed PDF ActiveX viewer
$oPDF = ObjCreate("AcroPDF.PDF")
$axPDF = GUICtrlCreateObj($oPDF, 220, 10, 660, 650)

GUISetState(@SW_SHOW)

; Resize handling
GUIRegisterMsg($WM_SIZE, "WM_SIZE")

Func WM_SIZE($hWnd, $iMsg, $wParam, $lParam)
    Local $iW = BitAND($lParam, 0xFFFF)
    Local $iH = BitShift($lParam, 16)

    GUICtrlSetPos($lbPages, 10, 10, 200, $iH - 20)
    GUICtrlSetPos($axPDF, 220, 10, $iW - 230, $iH - 20)
EndFunc

; Load PDF and populate page list
Func LoadPDF($sFile)
    If Not FileExists($sFile) Then Return

    $g_sCurrentPDF = $sFile
    $oPDF.LoadFile($sFile)

    ; Get page count
    $g_iPageCount = $oPDF.GetNumPages()

    GUICtrlSetData($lbPages, "")

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
            MsgBox($MB_ICONINFORMATION, "Save", "Saving current PDF is not implemented.")

        Case $mSaveAs
            Local $sOut = FileSaveDialog("Save PDF As", @ScriptDir, "PDF Files (*.pdf)", 2)
            If Not @error Then FileCopy($g_sCurrentPDF, $sOut, 1)

        Case $mManual
            MsgBox($MB_ICONINFORMATION, "User Manual", "User manual goes here.")

        Case $mAbout
            MsgBox($MB_ICONINFORMATION, "About", "PDF Viewer Example using AutoIt.")
    EndSwitch
WEnd
