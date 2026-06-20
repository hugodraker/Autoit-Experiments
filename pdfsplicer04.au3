#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <GuiListBox.au3>
#include <MsgBoxConstants.au3>

Global $g_sCurrentPDF = ""
Global $g_iPageCount = 0

; GUI
$hGUI = GUICreate("PDF Page Counter", 700, 600, -1, -1, BitOR($WS_SIZEBOX, $WS_MAXIMIZEBOX, $WS_MINIMIZEBOX))

; Menu
$mFile   = GUICtrlCreateMenu("&File")
$mOpen   = GUICtrlCreateMenuItem("Open", $mFile)
$mSave   = GUICtrlCreateMenuItem("Save", $mFile)
$mSaveAs = GUICtrlCreateMenuItem("Save As", $mFile)
$mEditProps = GUICtrlCreateMenuItem("Edit Properties", $mFile)
GUICtrlCreateMenuItem("", $mFile)
$mExit   = GUICtrlCreateMenuItem("Exit", $mFile)

$mHelp   = GUICtrlCreateMenu("&Help")
$mManual = GUICtrlCreateMenuItem("User Manual", $mHelp)
$mAbout  = GUICtrlCreateMenuItem("About", $mHelp)

; Listbox
$lbPages = GUICtrlCreateList("", 10, 10, 680, 540, BitOR($WS_BORDER, $LBS_EXTENDEDSEL))

GUISetState(@SW_SHOW)

; Resize handler
GUIRegisterMsg($WM_SIZE, "WM_SIZE")
Func WM_SIZE($hWnd, $iMsg, $wParam, $lParam)
    Local $iW = BitAND($lParam, 0xFFFF)
    Local $iH = BitShift($lParam, 16)
    GUICtrlSetPos($lbPages, 10, 10, $iW - 20, $iH - 20)
EndFunc

Func _PDF_GetPageCount($sFile)
    Local $hFile = FileOpen($sFile, 16)
    If $hFile = -1 Then Return 0
    Local $data = FileRead($hFile)
    FileClose($hFile)
    If @error Or $data = "" Then Return 0
    $data = BinaryToString($data)
    Local $aMatches = StringRegExp($data, "/Count\s+(\d+)", 3)
    If Not IsArray($aMatches) Then Return 1
    Local $max = 1
    For $i = 0 To UBound($aMatches) - 1
        Local $n = Number($aMatches[$i])
        If $n > $max Then $max = $n
    Next
    Return $max
EndFunc

Func _PDF_FindField($data, $field)
    Local $a = StringRegExp($data, "/" & $field & "\s*\((.*?)\)", 3)
    If IsArray($a) Then Return $a[0]
    Return ""
EndFunc

Func _PDF_GetMetadata($sFile, ByRef $sTitle, ByRef $sSubject, ByRef $sCreator, ByRef $sProducer, ByRef $sKeywords)
    Local $hFile = FileOpen($sFile, 16)
    If $hFile = -1 Then
        $sTitle = ""
        $sSubject = ""
        $sCreator = ""
        $sProducer = ""
        $sKeywords = ""
        Return
    EndIf
    Local $data = FileRead($hFile)
    FileClose($hFile)
    $data = BinaryToString($data)
    $sTitle    = _PDF_FindField($data, "Title")
    $sSubject  = _PDF_FindField($data, "Subject")
    $sCreator  = _PDF_FindField($data, "Creator")
    $sProducer = _PDF_FindField($data, "Producer")
    $sKeywords = _PDF_FindField($data, "Keywords")
EndFunc

Func _PDF_GetPageSize($sFile)
    Local $aSize[2] = [0, 0]
    Local $hFile = FileOpen($sFile, 16)
    If $hFile = -1 Then Return $aSize
    Local $data = FileRead($hFile)
    FileClose($hFile)
    $data = BinaryToString($data)
    Local $a = StringRegExp($data, "/MediaBox\s*\[\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*\]", 3)
    If IsArray($a) Then
        $aSize[0] = Number($a[2]) - Number($a[0])
        $aSize[1] = Number($a[3]) - Number($a[1])
    EndIf
    Return $aSize
EndFunc

Func _ShowPDFProperties($sFile)
    Local $sTitle = "", $sSubject = "", $sCreator = "", $sProducer = "", $sKeywords = ""
    _PDF_GetMetadata($sFile, $sTitle, $sSubject, $sCreator, $sProducer, $sKeywords)
    Local $aSize = _PDF_GetPageSize($sFile)
    Local $pages = _PDF_GetPageCount($sFile)

    Local $hProp = GUICreate("PDF Properties", 400, 320, -1, -1, $WS_CAPTION + $WS_SYSMENU)

    GUICtrlCreateLabel("Title:", 10, 10, 80, 20)
    GUICtrlCreateInput($sTitle, 100, 10, 280, 20)

    GUICtrlCreateLabel("Subject:", 10, 40, 80, 20)
    GUICtrlCreateInput($sSubject, 100, 40, 280, 20)

    GUICtrlCreateLabel("Creator:", 10, 70, 80, 20)
    GUICtrlCreateInput($sCreator, 100, 70, 280, 20)

    GUICtrlCreateLabel("Producer:", 10, 100, 80, 20)
    GUICtrlCreateInput($sProducer, 100, 100, 280, 20)

    GUICtrlCreateLabel("Keywords:", 10, 130, 80, 20)
    GUICtrlCreateInput($sKeywords, 100, 130, 280, 20)

    GUICtrlCreateLabel("Page Size:", 10, 170, 80, 20)
    GUICtrlCreateInput($aSize[0] & " × " & $aSize[1] & " pts", 100, 170, 280, 20)

    GUICtrlCreateLabel("Pages:", 10, 200, 80, 20)
    GUICtrlCreateInput($pages, 100, 200, 80, 20)

    Local $btnClose = GUICtrlCreateButton("Close", 150, 250, 100, 30)

    GUISetState(@SW_SHOW, $hProp)

    While 1
        Switch GUIGetMsg()
            Case $GUI_EVENT_CLOSE, $btnClose
                ExitLoop
        EndSwitch
    WEnd

    GUIDelete($hProp)
EndFunc

Func LoadPDF($sFile)
    $g_sCurrentPDF = $sFile
    $g_iPageCount = _PDF_GetPageCount($sFile)
    GUICtrlSetData($lbPages, "")
    For $i = 1 To $g_iPageCount
        GUICtrlSetData($lbPages, "Page " & $i)
    Next
EndFunc

While True
    Switch GUIGetMsg()
        Case $GUI_EVENT_CLOSE, $mExit
            Exit

        Case $mOpen
            Local $sFile = FileOpenDialog("Open PDF", @ScriptDir, "PDF Files (*.pdf)", 1)
            If Not @error Then LoadPDF($sFile)

        Case $mEditProps
            If $g_sCurrentPDF <> "" Then _ShowPDFProperties($g_sCurrentPDF)

        Case $mSave
            MsgBox($MB_ICONINFORMATION, "Save", "Save functionality not implemented.")

        Case $mSaveAs
            Local $sOut = FileSaveDialog("Save PDF As", @ScriptDir, "PDF Files (*.pdf)", 2)
            If Not @error And $g_sCurrentPDF <> "" Then FileCopy($g_sCurrentPDF, $sOut, 1)

        Case $mManual
            MsgBox($MB_ICONINFORMATION, "User Manual", "User manual goes here.")

        Case $mAbout
            MsgBox($MB_ICONINFORMATION, "About", "AutoIt PDF Page Counter Example.")
    EndSwitch
WEnd
