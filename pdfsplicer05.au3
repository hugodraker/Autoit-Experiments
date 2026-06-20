#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <GuiListBox.au3>
#include <MsgBoxConstants.au3>

Global $g_sCurrentPDF = ""
Global $g_iPageCount = 0

; Main GUI
$hGUI = GUICreate("PDF Page Counter", 700, 600, -1, -1, BitOR($WS_SIZEBOX, $WS_MAXIMIZEBOX, $WS_MINIMIZEBOX))

$mFile       = GUICtrlCreateMenu("&File")
$mOpen       = GUICtrlCreateMenuItem("Open", $mFile)
$mSave       = GUICtrlCreateMenuItem("Save", $mFile)
$mSaveAs     = GUICtrlCreateMenuItem("Save As", $mFile)
$mEditProps  = GUICtrlCreateMenuItem("Edit Properties", $mFile)
GUICtrlCreateMenuItem("", $mFile)
$mExit       = GUICtrlCreateMenuItem("Exit", $mFile)

$mHelp       = GUICtrlCreateMenu("&Help")
$mManual     = GUICtrlCreateMenuItem("User Manual", $mHelp)
$mAbout      = GUICtrlCreateMenuItem("About", $mHelp)

$lbPages = GUICtrlCreateList("", 10, 10, 680, 540, BitOR($WS_BORDER, $LBS_EXTENDEDSEL))

GUISetState(@SW_SHOW)

GUIRegisterMsg($WM_SIZE, "WM_SIZE")
Func WM_SIZE($hWnd, $iMsg, $wParam, $lParam)
    Local $iW = BitAND($lParam, 0xFFFF)
    Local $iH = BitShift($lParam, 16)
    GUICtrlSetPos($lbPages, 10, 10, $iW - 20, $iH - 20)
EndFunc

Func _PDF_GetPageCount($sFile)
    Local $hFile = FileOpen($sFile, 16)
    If $hFile = -1 Then Return 0
    Local $bData = FileRead($hFile)
    FileClose($hFile)
    If @error Or $bData = "" Then Return 0
    Local $data = BinaryToString($bData)
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
    Local $bData = FileRead($hFile)
    FileClose($hFile)
    Local $data = BinaryToString($bData)
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
    Local $bData = FileRead($hFile)
    FileClose($hFile)
    Local $data = BinaryToString($bData)
    Local $a = StringRegExp($data, "/MediaBox\s*\[\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*\]", 3)
    If IsArray($a) Then
        $aSize[0] = Number($a[2]) - Number($a[0])
        $aSize[1] = Number($a[3]) - Number($a[1])
    EndIf
    Return $aSize
EndFunc

Func _PDF_Escape($s)
    $s = StringReplace($s, "\", "\\")
    $s = StringReplace($s, "(", "\(")
    $s = StringReplace($s, ")", "\)")
    Return $s
EndFunc

Func _PDF_SaveMetadata($sFile, $sTitle, $sSubject, $sCreator, $sProducer, $sKeywords)
    Local $hFile = FileOpen($sFile, 16)
    If $hFile = -1 Then Return 0
    Local $bData = FileRead($hFile)
    FileClose($hFile)
    If @error Or $bData = "" Then Return 0

    Local $data = BinaryToString($bData)
    Local $posStartXref = StringInStr($data, "startxref", 0, -1)
    If $posStartXref = 0 Then Return 0
    Local $sAfter = StringMid($data, $posStartXref + 9)
    Local $sXrefPosLine = StringStripWS(StringLeft($sAfter, StringInStr($sAfter, @LF) - 1), 3)
    Local $iOldXrefPos = Number($sXrefPosLine)

    Local $posTrailer = StringInStr($data, "trailer", 0, -1)
    If $posTrailer = 0 Then Return 0
    Local $sTrailerBlock = StringMid($data, $posTrailer)
    Local $aRoot = StringRegExp($sTrailerBlock, "/Root\s+(\d+)\s+(\d+)\s+R", 3)
    Local $aSize = StringRegExp($sTrailerBlock, "/Size\s+(\d+)", 3)
    If Not IsArray($aRoot) Or Not IsArray($aSize) Then Return 0

    Local $iRootObj = Number($aRoot[0])
    Local $iRootGen = Number($aRoot[1])
    Local $iOldSize = Number($aSize[0])
    Local $iNewInfoObj = $iOldSize
    Local $iNewSize = $iOldSize + 1

    Local $sInfo = $iNewInfoObj & " 0 obj" & @CRLF & "<<" & @CRLF
    If $sTitle <> "" Then    $sInfo &= "/Title (" & _PDF_Escape($sTitle) & ")" & @CRLF
    If $sSubject <> "" Then  $sInfo &= "/Subject (" & _PDF_Escape($sSubject) & ")" & @CRLF
    If $sCreator <> "" Then  $sInfo &= "/Creator (" & _PDF_Escape($sCreator) & ")" & @CRLF
    If $sProducer <> "" Then $sInfo &= "/Producer (" & _PDF_Escape($sProducer) & ")" & @CRLF
    If $sKeywords <> "" Then $sInfo &= "/Keywords (" & _PDF_Escape($sKeywords) & ")" & @CRLF
    $sInfo &= ">>" & @CRLF & "endobj" & @CRLF

    Local $iInfoOffset = BinaryLen($bData)
    Local $sXref = "xref" & @CRLF & $iNewInfoObj & " 1" & @CRLF & StringFormat("%010d 00000 n ", $iInfoOffset) & @CRLF

    Local $sTrailer = "trailer" & @CRLF & "<<" & @CRLF & "/Size " & $iNewSize & @CRLF & "/Root " & $iRootObj & " " & $iRootGen & " R" & @CRLF & "/Info " & $iNewInfoObj & " 0 R" & @CRLF & "/Prev " & $iOldXrefPos & @CRLF & ">>" & @CRLF

    Local $iXrefOffset = $iInfoOffset + StringLen($sInfo)
    Local $sStart = "startxref" & @CRLF & $iXrefOffset & @CRLF & "%%EOF" & @CRLF

    Local $bAppend = Binary($sInfo & $sXref & $sTrailer & $sStart)
    $bData &= $bAppend

    $hFile = FileOpen($sFile, 18)
    If $hFile = -1 Then Return 0
    FileWrite($hFile, $bData)
    FileClose($hFile)
    Return 1
EndFunc

Func _ShowPDFProperties($sFile)
    Local $sTitle = "", $sSubject = "", $sCreator = "", $sProducer = "", $sKeywords = ""
    _PDF_GetMetadata($sFile, $sTitle, $sSubject, $sCreator, $sProducer, $sKeywords)
    Local $aSize = _PDF_GetPageSize($sFile)
    Local $wPts = $aSize[0], $hPts = $aSize[1]
    Local $wIn = ($wPts / 72), $hIn = ($hPts / 72)
    Local $wMm = ($wIn * 25.4), $hMm = ($hIn * 25.4)
    Local $pages = _PDF_GetPageCount($sFile)

    Local $hProp = GUICreate("PDF Properties", 420, 360, -1, -1, $WS_CAPTION + $WS_SYSMENU)

    GUICtrlCreateLabel("Title:", 10, 10, 80, 20)
    Local $idTitle = GUICtrlCreateInput($sTitle, 100, 10, 300, 20)

    GUICtrlCreateLabel("Subject:", 10, 40, 80, 20)
    Local $idSubject = GUICtrlCreateInput($sSubject, 100, 40, 300, 20)

    GUICtrlCreateLabel("Creator:", 10, 70, 80, 20)
    Local $idCreator = GUICtrlCreateInput($sCreator, 100, 70, 300, 20)

    GUICtrlCreateLabel("Producer:", 10, 100, 80, 20)
    Local $idProducer = GUICtrlCreateInput($sProducer, 100, 100, 300, 20)

    GUICtrlCreateLabel("Keywords:", 10, 130, 80, 20)
    Local $idKeywords = GUICtrlCreateInput($sKeywords, 100, 130, 300, 20)

    GUICtrlCreateLabel("Page Size (pts):", 10, 170, 100, 20)
    GUICtrlCreateInput(Round($wPts, 2) & " × " & Round($hPts, 2), 120, 170, 280, 20)

    GUICtrlCreateLabel("Page Size (in):", 10, 200, 100, 20)
    GUICtrlCreateInput(Round($wIn, 3) & " × " & Round($hIn, 3), 120, 200, 280, 20)

    GUICtrlCreateLabel("Page Size (mm):", 10, 230, 100, 20)
    GUICtrlCreateInput(Round($wMm, 1) & " × " & Round($hMm, 1), 120, 230, 280, 20)

    GUICtrlCreateLabel("Pages:", 10, 260, 80, 20)
    GUICtrlCreateInput($pages, 120, 260, 80, 20)

    Local $btnSave  = GUICtrlCreateButton("Save", 110, 300, 80, 30)
    Local $btnClose = GUICtrlCreateButton("Close", 220, 300, 80, 30)

    GUISetState(@SW_SHOW, $hProp)

    While 1
        Local $msg = GUIGetMsg()
        Switch $msg
            Case $GUI_EVENT_CLOSE, $btnClose
                ExitLoop
            Case $btnSave
                Local $nTitle    = GUICtrlRead($idTitle)
                Local $nSubject  = GUICtrlRead($idSubject)
                Local $nCreator  = GUICtrlRead($idCreator)
                Local $nProducer = GUICtrlRead($idProducer)
                Local $nKeywords = GUICtrlRead($idKeywords)
                _PDF_SaveMetadata($sFile, $nTitle, $nSubject, $nCreator, $nProducer, $nKeywords)
                MsgBox($MB_ICONINFORMATION, "Saved", "PDF properties updated (incremental update).")
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
