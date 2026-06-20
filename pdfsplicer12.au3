#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <GuiListBox.au3>
#include <MsgBoxConstants.au3>

Global $g_sCurrentPDF = ""
Global $g_iPageCount = 0
Global $g_sQPDF = _FindQPDF()
ConsoleWrite('qpdf in: '&$g_sQPDF&@CRLF)
; ============================================================
; FIND QPDF INSTALL LOCATION
; ============================================================

Func _FindQPDF()
    Local $paths[4] = [ _
        "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", _
        "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall", _
        "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", _
        "HKEY_CURRENT_USER\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" _
    ]

    For $i = 0 To UBound($paths) - 1
        Local $idx = 1
        Local $sub = RegEnumKey($paths[$i], $idx)

        While Not @error
            Local $key = $paths[$i] & "\" & $sub
            Local $name = RegRead($key, "DisplayName")

            If StringInStr($name, "qpdf", 2) Then
                ; Try InstallLocation
                Local $loc = RegRead($key, "InstallLocation")
                If $loc <> "" Then
					$loc=$loc&'bin\'
                    If StringRight($loc, 1) <> "\" Then $loc &= "\"
						
                    If FileExists($loc & "qpdf.exe") Then Return '"' & $loc & 'qpdf.exe"'
                EndIf

                ; Try DisplayIcon
                Local $icon = RegRead($key, "DisplayIcon")
                If $icon <> "" And FileExists($icon) Then
                    Return '"' & $icon &'bin\qpdf.exe'& '"'
                EndIf
            EndIf

            $idx += 1
            $sub = RegEnumKey($paths[$i], $idx)
        WEnd
    Next

    ; Fallback: assume it's in PATH
    Return "qpdf"
EndFunc

; ============================================================
; BASIC PDF HELPERS
; ============================================================

Func _PDF_GetPageCount($sFile)
    Local $h = FileOpen($sFile, 16)
    If $h = -1 Then Return 0
    Local $b = FileRead($h)
    FileClose($h)

    Local $d = BinaryToString($b)
    Local $a = StringRegExp($d, "/Count\s+(\d+)", 3)
    If Not IsArray($a) Then Return 1

    Local $max = 1
    For $i = 0 To UBound($a) - 1
        Local $n = Number($a[$i])
        If $n > $max Then $max = $n
    Next
    Return $max
EndFunc

Func _PDF_DecodeUTF16BE($hex)
    $hex = StringTrimLeft($hex, 1)
    $hex = StringTrimRight($hex, 1)
    Local $bin = Binary("0x" & $hex)
    If BinaryMid($bin, 1, 2) = Binary("0xFEFF") Then
        $bin = BinaryMid($bin, 3)
    EndIf
    Return BinaryToString($bin, 2)
EndFunc

Func _PDF_FindField($data, $field)
    Local $aHex = StringRegExp($data, "/" & $field & "\s*<([0-9A-Fa-f]+)>", 3)
    If IsArray($aHex) Then Return _PDF_DecodeUTF16BE("<" & $aHex[0] & ">")

    Local $aAsc = StringRegExp($data, "/" & $field & "\s*\((.*?)\)", 3)
    If IsArray($aAsc) Then Return $aAsc[0]

    Return ""
EndFunc

Func _PDF_GetMetadata($sFile, ByRef $t, ByRef $s, ByRef $c, ByRef $p, ByRef $k)
    Local $h = FileOpen($sFile, 16)
    If $h = -1 Then
        $t = ""; $s = ""; $c = ""; $p = ""; $k = ""
        Return
    EndIf
    Local $b = FileRead($h)
    FileClose($h)

    Local $d = BinaryToString($b)
    $t = _PDF_FindField($d, "Title")
    $s = _PDF_FindField($d, "Subject")
    $c = _PDF_FindField($d, "Creator")
    $p = _PDF_FindField($d, "Producer")
    $k = _PDF_FindField($d, "Keywords")
EndFunc

Func _PDF_GetPageSize($sFile)
    Local $aSize[2] = [0, 0]
    Local $h = FileOpen($sFile, 16)
    If $h = -1 Then Return $aSize
    Local $b = FileRead($h)
    FileClose($h)

    Local $d = BinaryToString($b)
    Local $a = StringRegExp($d, "/MediaBox\s*\[\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*\]", 3)
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

Func _PDF_SaveMetadata($sFile, $t, $s, $c, $p, $k)
    Local $h = FileOpen($sFile, 16)
    If $h = -1 Then Return 0
    Local $b = FileRead($h)
    FileClose($h)

    Local $d = BinaryToString($b)
    Local $posStart = StringInStr($d, "startxref", 0, -1)
    If $posStart = 0 Then Return 0

    Local $after = StringMid($d, $posStart + 9)
    Local $xrefLine = StringStripWS(StringLeft($after, StringInStr($after, @LF) - 1), 3)
    Local $oldXref = Number($xrefLine)

    Local $posTrailer = StringInStr($d, "trailer", 0, -1)
    If $posTrailer = 0 Then Return 0

    Local $tail = StringMid($d, $posTrailer)
    Local $aRoot = StringRegExp($tail, "/Root\s+(\d+)\s+(\d+)\s+R", 3)
    Local $aSize = StringRegExp($tail, "/Size\s+(\d+)", 3)
    If Not IsArray($aRoot) Or Not IsArray($aSize) Then Return 0

    Local $rootObj = Number($aRoot[0])
    Local $rootGen = Number($aRoot[1])
    Local $oldSize = Number($aSize[0])

    Local $newObj = $oldSize
    Local $newSize = $oldSize + 1

    Local $info = $newObj & " 0 obj" & @CRLF & "<<" & @CRLF & _
        "/Title (" & _PDF_Escape($t) & ")" & @CRLF & _
        "/Subject (" & _PDF_Escape($s) & ")" & @CRLF & _
        "/Creator (" & _PDF_Escape($c) & ")" & @CRLF & _
        "/Producer (" & _PDF_Escape($p) & ")" & @CRLF & _
        "/Keywords (" & _PDF_Escape($k) & ")" & @CRLF & _
        ">>" & @CRLF & "endobj" & @CRLF

    Local $infoOffset = BinaryLen($b)
    Local $xrefOffset = $infoOffset + StringLen($info)

    Local $xref = "xref" & @CRLF & $newObj & " 1" & @CRLF & _
        StringFormat("%010d 00000 n ", $infoOffset) & @CRLF

    Local $trailer = "trailer" & @CRLF & "<<" & @CRLF & _
        "/Size " & $newSize & @CRLF & _
        "/Root " & $rootObj & " " & $rootGen & " R" & @CRLF & _
        "/Info " & $newObj & " 0 R" & @CRLF & _
        "/Prev " & $oldXref & @CRLF & _
        ">>" & @CRLF

    Local $start = "startxref" & @CRLF & $xrefOffset & @CRLF & "%%EOF" & @CRLF

    Local $append = Binary($info & $xref & $trailer & $start)
    $b &= $append

    $h = FileOpen($sFile, 18)
    FileWrite($h, $b)
    FileClose($h)

    Return 1
EndFunc

; ============================================================
; QPDF INTEGRATION
; ============================================================

Func _QPDF_KeepPages($inFile, $outFile, $keepList)
    Local $cmd = $g_sQPDF & ' "' & $inFile & '" --pages "' & $inFile & '" ' & $keepList & ' -- "' & $outFile & '"'
    Local $pid = Run(@ComSpec & " /c " & $cmd, "", @SW_HIDE, $RUN_CREATE_NEW_CONSOLE)
    If $pid = 0 Then Return SetError(1, 0, 0)
ConsoleWrite($cmd&@CRLF)

    ProcessWaitClose($pid)
    Return FileExists($outFile)
EndFunc

; ============================================================
; GUI CREATION
; ============================================================

$hGUI = GUICreate("PDF Page Counter (qpdf)", 750, 600, -1, -1, BitOR($WS_SIZEBOX, $WS_MAXIMIZEBOX, $WS_MINIMIZEBOX))

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

$lbPages   = GUICtrlCreateList("", 10, 10, 650, 540, BitOR($WS_BORDER, $LBS_EXTENDEDSEL))
$btnDelete = GUICtrlCreateButton("Delete Selected", 670, 10, 70, 40)

GUISetState(@SW_SHOW)

GUIRegisterMsg($WM_SIZE, "WM_SIZE")
Func WM_SIZE($hWnd, $iMsg, $wParam, $lParam)
    Local $iW = BitAND($lParam, 0xFFFF)
    Local $iH = BitShift($lParam, 16)
    GUICtrlSetPos($lbPages, 10, 10, $iW - 100, $iH - 20)
    GUICtrlSetPos($btnDelete, $iW - 80, 10, 70, 40)
EndFunc

; ============================================================
; GUI HELPERS
; ============================================================

Func LoadPDF($sFile)
    $g_sCurrentPDF = $sFile
    WinSetTitle($hGUI, "", "PDF Page Counter (qpdf) - " & $sFile)

    $g_iPageCount = _PDF_GetPageCount($sFile)
    GUICtrlSetData($lbPages, "")

    For $i = 1 To $g_iPageCount
        GUICtrlSetData($lbPages, "Page " & $i)
    Next
EndFunc

Func _ShowPDFProperties($sFile)
    Local $t = "", $s = "", $c = "", $p = "", $k = ""
    _PDF_GetMetadata($sFile, $t, $s, $c, $p, $k)

    Local $sz = _PDF_GetPageSize($sFile)
    Local $wPts = $sz[0], $hPts = $sz[1]
    Local $wIn = $wPts / 72, $hIn = $hPts / 72
    Local $wMm = $wIn * 25.4, $hMm = $hIn * 25.4
    Local $pages = _PDF_GetPageCount($sFile)

    Local $hProp = GUICreate("PDF Properties", 420, 380)
    GUICtrlCreateLabel("Title:", 10, 10, 80, 20)
    Local $idT = GUICtrlCreateInput($t, 100, 10, 300, 20)

    GUICtrlCreateLabel("Subject:", 10, 40, 80, 20)
    Local $idS = GUICtrlCreateInput($s, 100, 40, 300, 20)

    GUICtrlCreateLabel("Creator:", 10, 70, 80, 20)
    Local $idC = GUICtrlCreateInput($c, 100, 70, 300, 20)

    GUICtrlCreateLabel("Producer:", 10, 100, 80, 20)
    Local $idP = GUICtrlCreateInput($p, 100, 100, 300, 20)

    GUICtrlCreateLabel("Keywords:", 10, 130, 80, 20)
    Local $idK = GUICtrlCreateInput($k, 100, 130, 300, 20)

    GUICtrlCreateLabel("Page Size (pts):", 10, 170, 110, 20)
    GUICtrlCreateInput(Round($wPts, 2) & " × " & Round($hPts, 2), 130, 170, 270, 20)

    GUICtrlCreateLabel("Page Size (in):", 10, 200, 110, 20)
    GUICtrlCreateInput(Round($wIn, 3) & " × " & Round($hIn, 3), 130, 200, 270, 20)

    GUICtrlCreateLabel("Page Size (mm):", 10, 230, 110, 20)
    GUICtrlCreateInput(Round($wMm, 1) & " × " & Round($hMm, 1), 130, 230, 270, 20)

    GUICtrlCreateLabel("Pages:", 10, 260, 80, 20)
    GUICtrlCreateInput($pages, 130, 260, 80, 20)

    Local $btnSave  = GUICtrlCreateButton("Save", 110, 310, 80, 30)
    Local $btnClose = GUICtrlCreateButton("Close", 220, 310, 80, 30)

    GUISetState(@SW_SHOW, $hProp)

    While 1
        Local $msg = GUIGetMsg()
        Switch $msg
            Case $GUI_EVENT_CLOSE, $btnClose
                ExitLoop

            Case $btnSave
                _PDF_SaveMetadata($sFile, _
                    GUICtrlRead($idT), _
                    GUICtrlRead($idS), _
                    GUICtrlRead($idC), _
                    GUICtrlRead($idP), _
                    GUICtrlRead($idK))
                MsgBox($MB_ICONINFORMATION, "Saved", "PDF metadata updated safely.")
        EndSwitch
    WEnd

    GUIDelete($hProp)
EndFunc

; ============================================================
; DELETE PAGES USING QPDF
; ============================================================

Func _DeleteSelectedPages()
    If $g_sCurrentPDF = "" Then Return

    Local $aSel = _GUICtrlListBox_GetSelItems($lbPages)
    If Not IsArray($aSel) Or UBound($aSel) = 0 Then Return

    Local $total = _PDF_GetPageCount($g_sCurrentPDF)
    If $total < 1 Then Return

    If MsgBox($MB_YESNO + $MB_ICONWARNING, "Confirm Delete", _
        "Are you sure you want to delete the selected pages from the PDF file?") = $IDNO Then Return

    Local $keep = ""
    For $i = 1 To $total
        Local $delete = False
        For $j = 0 To UBound($aSel) - 1
            If $aSel[$j] + 1 = $i Then
                $delete = True
                ExitLoop
            EndIf
        Next
        If Not $delete Then
            If $keep <> "" Then $keep &= ","
            $keep &= $i
        EndIf
    Next

    If $keep = "" Then
        MsgBox(48, "Error", "You cannot delete all pages.")
        Return
    EndIf

    Local $outFile = $g_sCurrentPDF & ".tmp.pdf"

    If _QPDF_KeepPages($g_sCurrentPDF, $outFile, $keep) Then
        FileDelete($g_sCurrentPDF)
        FileMove($outFile, $g_sCurrentPDF)
        LoadPDF($g_sCurrentPDF)
        MsgBox(64, "Success", "Selected pages deleted using qpdf.")
    Else
        MsgBox(16, "Error", "qpdf failed to modify the PDF. Make sure qpdf is installed and in PATH.")
    EndIf
EndFunc

; ============================================================
; MAIN LOOP
; ============================================================

While True
    Switch GUIGetMsg()
        Case $GUI_EVENT_CLOSE, $mExit
            Exit

        Case $mOpen
            Local $f = FileOpenDialog("Open PDF", @ScriptDir, "PDF Files (*.pdf)", 1)
            If Not @error Then LoadPDF($f)

        Case $btnDelete
            _DeleteSelectedPages()

        Case $mEditProps
            If $g_sCurrentPDF <> "" Then _ShowPDFProperties($g_sCurrentPDF)

        Case $mSave
            MsgBox($MB_ICONINFORMATION, "Save", "File is modified in-place when you delete pages or edit metadata.")

        Case $mSaveAs
            If $g_sCurrentPDF = "" Then ContinueLoop
            Local $o = FileSaveDialog("Save PDF As", @ScriptDir, "PDF Files (*.pdf)", 2)
            If Not @error Then FileCopy($g_sCurrentPDF, $o, 1)

        Case $mManual
            MsgBox($MB_ICONINFORMATION, "User Manual", _
                "1. Open a PDF." & @CRLF & _
                "2. Select pages in the list." & @CRLF & _
                "3. Click 'Delete Selected' to remove them using qpdf." & @CRLF & _
                "4. Use 'Edit Properties' to adjust metadata.")

        Case $mAbout
            MsgBox($MB_ICONINFORMATION, "About", "PDF Page Counter + qpdf-based page deletion (AutoIt).")
    EndSwitch
WEnd
