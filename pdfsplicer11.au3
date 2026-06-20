#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <GuiListBox.au3>
#include <MsgBoxConstants.au3>

; ============================
; ZLIB INFLATE VIA zlib1.dll
; ============================

; Expects raw zlib stream (as Binary)
; Returns Binary() with decompressed data, or sets @error on failure.

Func _ZLIB_Inflate($bData)
    If Not IsBinary($bData) Then $bData = Binary($bData)

    Local $cbIn = BinaryLen($bData)
    If $cbIn = 0 Then Return SetError(1, 0, Binary(""))

    Local $tIn = DllStructCreate("byte[" & $cbIn & "]")
    DllStructSetData($tIn, 1, $bData)

    ; heuristic output size (zlib doesn't give it up front)
    Local $cbOut = $cbIn * 8
    Local $tOut = DllStructCreate("byte[" & $cbOut & "]")

    Local $ret = DllCall("zlib1.dll", "int:cdecl", "uncompress", _
        "ptr", DllStructGetPtr($tOut), _
        "long*", $cbOut, _
        "ptr", DllStructGetPtr($tIn), _
        "long", $cbIn)

    If @error Or Not IsArray($ret) Or $ret[0] <> 0 Then
        Return SetError(2, 0, Binary(""))
    EndIf

    Local $bOut = DllStructGetData($tOut, 1)
    Return BinaryMid($bOut, 1, $cbOut)
EndFunc

Func _PDF_FlateDecode($bStream, $sFilter)
    If $sFilter = "" Then Return $bStream
    Local $s = StringStripWS($sFilter, 3)
    If StringInStr($s, "/FlateDecode") = 0 Then Return $bStream

    Local $bOut = _ZLIB_Inflate($bStream)
    If @error Then Return $bStream
    Return $bOut
EndFunc

; ============================
; XREF STREAM PARSER (not wired into main parser yet)
; ============================

Func _PDF_GetFilter($dict)
    Local $a = StringRegExp($dict, "/Filter\s*(\[?.*?\]?)\s*(/|>>)", 3)
    If IsArray($a) Then Return $a[0]
    Return ""
EndFunc

Func _PDF_GetNumber($dict, $key)
    Local $a = StringRegExp($dict, $key & "\s+(\d+)", 3)
    If IsArray($a) Then Return Number($a[0])
    Return ""
EndFunc

Func _PDF_GetArray($dict, $key)
    Local $a = StringRegExp($dict, $key & "\s*\[(.*?)\]", 3)
    If Not IsArray($a) Then Return SetError(1,0,0)
    Local $parts = StringSplit(StringStripWS($a[0], 3), " ", 2)
    If Not IsArray($parts) Then Return SetError(1,0,0)
    Local $arr[UBound($parts)]
    For $i = 0 To UBound($parts) - 1
        $arr[$i] = Number($parts[$i])
    Next
    Return $arr
EndFunc

Func _PDF_ReadInt(ByRef $bin, ByRef $pos, $len)
    If $len = 0 Then Return 0
    Local $val = 0
    For $i = 0 To $len - 1
        $val = BitShift($val, -8) + Asc(BinaryMid($bin, $pos + $i, 1))
    Next
    Return $val
EndFunc

Func _PDF_ParseXRefStream($objID, $dict, $streamData)
    Local $W = _PDF_GetArray($dict, "/W")
    If Not IsArray($W) Or UBound($W) <> 4 Then Return SetError(1,0,0)

    Local $Index = _PDF_GetArray($dict, "/Index")
    If Not IsArray($Index) Then
        Local $Size = _PDF_GetNumber($dict, "/Size")
        If $Size = "" Then Return SetError(1,0,0)
        Local $tmp[3] = [0, 0, $Size]
        $Index = $tmp
    EndIf

    Local $bDecoded = _PDF_FlateDecode($streamData, _PDF_GetFilter($dict))
    If @error Then Return SetError(1,0,0)

    Local $pos = 1
    Local $xref[1][4]
    Local $count = 0

    For $i = 1 To UBound($Index) - 1 Step 2
        Local $startObj = Number($Index[$i])
        Local $numObj   = Number($Index[$i+1])

        For $n = 0 To $numObj - 1
            Local $type = _PDF_ReadInt($bDecoded, $pos, $W[1])
            $pos += $W[1]

            Local $field2 = _PDF_ReadInt($bDecoded, $pos, $W[2])
            $pos += $W[2]

            Local $field3 = _PDF_ReadInt($bDecoded, $pos, $W[3])
            $pos += $W[3]

            $count += 1
            ReDim $xref[$count + 1][4]

            $xref[$count][0] = $startObj + $n
            $xref[$count][1] = $field2
            $xref[$count][2] = $field3
            $xref[$count][3] = $type
        Next
    Next

    Return $xref
EndFunc

; ============================
; CORE SCRIPT / GUI
; ============================

Global $g_sCurrentPDF = ""
Global $g_iPageCount = 0

Global Const $PDF_OBJ_DICT = 1
Global Const $PDF_OBJ_OTHER = 2

Global $g_aPDFObjects = 0
Global $g_iRootObj = 0
Global $g_iPagesRoot = 0

$hGUI = GUICreate("PDF Page Counter", 750, 600, -1, -1, BitOR($WS_SIZEBOX, $WS_MAXIMIZEBOX, $WS_MINIMIZEBOX))

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

Func _PDF_GetPageCount($sFile)
    Local $h = FileOpen($sFile, 16)
    If $h = -1 Then Return 0
    Local $b = FileRead($h)
    FileClose($h)
    Local $t = BinaryToString($b)
    Local $a = StringRegExp($t, "/Count\s+(\d+)", 3)
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

Func _PDF_ParseFile($sFile)
    $g_aPDFObjects = 0
    $g_iRootObj = 0
    $g_iPagesRoot = 0

    Local $h = FileOpen($sFile, 16)
    If $h = -1 Then Return 0
    Local $b = FileRead($h)
    FileClose($h)
    Local $d = BinaryToString($b)

    Local $posStart = StringInStr($d, "startxref", 0, -1)
    If $posStart = 0 Then Return 0
    Local $after = StringMid($d, $posStart + 9)
    Local $xrefLine = StringStripWS(StringLeft($after, StringInStr($after, @LF) - 1), 3)
    Local $xrefOfs = Number($xrefLine)

    Local $xrefBlock = StringMid($d, $xrefOfs + 1)
    If StringLeft($xrefBlock, 4) <> "xref" Then Return 0
    $xrefBlock = StringMid($xrefBlock, 5)
    Local $aLines = StringSplit($xrefBlock, @LF, 1)
    If $aLines[0] < 3 Then Return 0

    Local $aObjs[1][10]
    Local $iObjCount = 0
    Local $i = 1
    While $i <= $aLines[0]
        Local $line = StringStripWS($aLines[$i], 3)
        If $line = "" Then ExitLoop
        If StringInStr($line, "trailer") Then ExitLoop
        Local $aHdr = StringSplit($line, " ", 2)
        If UBound($aHdr) = 2 Then
            Local $startObj = Number($aHdr[0])
            Local $countObj = Number($aHdr[1])
            $i += 1
            For $j = 0 To $countObj - 1
                If $i > $aLines[0] Then ExitLoop
                Local $entry = StringStripWS($aLines[$i], 3)
                $i += 1
                If StringLen($entry) < 17 Then ContinueLoop
                Local $ofs = Number(StringLeft($entry, 10))
                Local $inUse = StringMid($entry, 18, 1)
                If $inUse = "n" Then
                    $iObjCount += 1
                    ReDim $aObjs[$iObjCount + 1][10]
                    $aObjs[$iObjCount][0] = $startObj + $j
                    $aObjs[$iObjCount][1] = $ofs
                EndIf
            Next
        Else
            $i += 1
        EndIf
    WEnd
    If $iObjCount = 0 Then Return 0

    For $k = 1 To $iObjCount
        Local $ofs = $aObjs[$k][1]
        Local $chunk = StringMid($d, $ofs + 1)
        Local $posEnd = StringInStr($chunk, "endobj", 0, 1)
        If $posEnd = 0 Then ContinueLoop
        Local $raw = StringLeft($chunk, $posEnd + 5)
        $aObjs[$k][2] = $raw
        Local $aHead = StringRegExp($raw, "(\d+)\s+(\d+)\s+obj", 3)
        If IsArray($aHead) Then
            $aObjs[$k][0] = Number($aHead[0])
            $aObjs[$k][3] = Number($aHead[1])
        EndIf
        Local $dict = ""
        Local $type = $PDF_OBJ_OTHER
        Local $isPage = False
        Local $kids = ""
        Local $parent = ""
        Local $count = ""
        Local $posDictStart = StringInStr($raw, "<<")
        Local $posDictEnd = StringInStr($raw, ">>", 0, -1)
        If $posDictStart > 0 And $posDictEnd > $posDictStart Then
            $dict = StringMid($raw, $posDictStart, $posDictEnd - $posDictStart + 2)
            $type = $PDF_OBJ_DICT
            If StringInStr($dict, "/Type /Page") Then $isPage = True
            Local $aKids = StringRegExp($dict, "/Kids\s*\[(.*?)\]", 3)
            If IsArray($aKids) Then $kids = $aKids[0]
            Local $aPar = StringRegExp($dict, "/Parent\s+(\d+)\s+(\d+)\s+R", 3)
            If IsArray($aPar) Then $parent = $aPar[0]
            Local $aCnt = StringRegExp($dict, "/Count\s+(\d+)", 3)
            If IsArray($aCnt) Then $count = $aCnt[0]
        EndIf
        $aObjs[$k][4] = $type
        $aObjs[$k][5] = $dict
        $aObjs[$k][6] = $isPage
        $aObjs[$k][7] = $kids
        $aObjs[$k][8] = $parent
        $aObjs[$k][9] = $count
    Next

    $g_aPDFObjects = $aObjs

    Local $posTrailer2 = StringInStr($d, "trailer", 0, -1)
    If $posTrailer2 > 0 Then
        Local $tail2 = StringMid($d, $posTrailer2)
        Local $aRoot = StringRegExp($tail2, "/Root\s+(\d+)\s+(\d+)\s+R", 3)
        If IsArray($aRoot) Then $g_iRootObj = Number($aRoot[0])
    EndIf

    For $k = 1 To $iObjCount
        If $g_aPDFObjects[$k][4] = $PDF_OBJ_DICT Then
            If StringInStr($g_aPDFObjects[$k][5], "/Type /Pages") Then
                $g_iPagesRoot = $g_aPDFObjects[$k][0]
                ExitLoop
            EndIf
        EndIf
    Next

    Return 1
EndFunc

Func _PDF_GetPageObjectIndices()
    If Not IsArray($g_aPDFObjects) Then Return SetError(1, 0, 0)
    Local $aTmp[1]
    Local $cnt = 0
    For $i = 1 To UBound($g_aPDFObjects) - 1
        If $g_aPDFObjects[$i][6] Then
            $cnt += 1
            ReDim $aTmp[$cnt + 1]
            $aTmp[$cnt] = $i
        EndIf
    Next
    If $cnt = 0 Then Return SetError(1, 0, 0)
    Return $aTmp
EndFunc

Func _PDF_RewriteWithoutDeletedPages()
    If Not IsArray($g_aPDFObjects) Then Return 0
    Local $aPages[1]
    Local $cntPages = 0
    For $i = 1 To UBound($g_aPDFObjects) - 1
        If $g_aPDFObjects[$i][6] Then
            $cntPages += 1
            ReDim $aPages[$cntPages + 1]
            $aPages[$cntPages] = $i
        EndIf
    Next
    If $cntPages = 0 Then Return 0
    Local $pagesIdx = -1
    For $i = 1 To UBound($g_aPDFObjects) - 1
        If $g_aPDFObjects[$i][0] = $g_iPagesRoot Then
            $pagesIdx = $i
            ExitLoop
        EndIf
    Next
    If $pagesIdx = -1 Then Return 0
    Local $kidsStr = ""
    For $i = 1 To $cntPages
        Local $idx = $aPages[$i]
        Local $objId = $g_aPDFObjects[$idx][0]
        If $kidsStr <> "" Then $kidsStr &= " "
        $kidsStr &= $objId & " 0 R"
    Next
    Local $dict = $g_aPDFObjects[$pagesIdx][5]
    $dict = StringRegExpReplace($dict, "/Kids\s*\[.*?\]", "/Kids [" & $kidsStr & "]")
    $dict = StringRegExpReplace($dict, "/Count\s+\d+", "/Count " & $cntPages)
    $g_aPDFObjects[$pagesIdx][5] = $dict
    For $i = 1 To $cntPages
        Local $idx = $aPages[$i]
        Local $raw = $g_aPDFObjects[$idx][2]
        Local $dict2 = $g_aPDFObjects[$idx][5]
        If $dict2 <> "" Then
            Local $posDictStart = StringInStr($raw, "<<")
            Local $posDictEnd = StringInStr($raw, ">>", 0, -1)
            If $posDictStart > 0 And $posDictEnd > $posDictStart Then
                Local $before = StringLeft($raw, $posDictStart - 1)
                Local $after = StringMid($raw, $posDictEnd + 2)
                $raw = $before & $dict2 & $after
            EndIf
        EndIf
        $g_aPDFObjects[$idx][2] = $raw
    Next
    Local $sOut = "%PDF-1.4" & @CRLF
    Local $aOffsets[UBound($g_aPDFObjects)]
    For $i = 1 To UBound($g_aPDFObjects) - 1
        If $g_aPDFObjects[$i][4] = 0 Then ContinueLoop
        If $g_aPDFObjects[$i][6] = False And $g_aPDFObjects[$i][0] <> $g_iPagesRoot And StringInStr($g_aPDFObjects[$i][5], "/Type /Page") Then
            ContinueLoop
        EndIf
        $aOffsets[$i] = StringLen($sOut)
        $sOut &= $g_aPDFObjects[$i][2] & @CRLF
    Next
    Local $xrefPos = StringLen($sOut)
    $sOut &= "xref" & @CRLF
    $sOut &= "0 " & (UBound($g_aPDFObjects)) & @CRLF
    $sOut &= StringFormat("%010d 65535 f ", 0) & @CRLF
    For $i = 1 To UBound($g_aPDFObjects) - 1
        Local $ofs = $aOffsets[$i]
        If $ofs = 0 Then
            $sOut &= StringFormat("%010d 00000 f ", 0) & @CRLF
        Else
            $sOut &= StringFormat("%010d 00000 n ", $ofs) & @CRLF
        EndIf
    Next
    Local $trailer = "trailer" & @CRLF & "<<" & @CRLF & _
        "/Size " & UBound($g_aPDFObjects) & @CRLF & _
        "/Root " & $g_iRootObj & " 0 R" & @CRLF & _
        ">>" & @CRLF
    $sOut &= $trailer
    $sOut &= "startxref" & @CRLF & $xrefPos & @CRLF & "%%EOF" & @CRLF
    Local $h = FileOpen($g_sCurrentPDF, 2 + 8)
    If $h = -1 Then Return 0
    FileWrite($h, $sOut)
    FileClose($h)
    Return 1
EndFunc

Func _PDF_DeletePagesByIndices(ByRef $aSelLB)
    If _PDF_ParseFile($g_sCurrentPDF) = 0 Then Return 0
    Local $aPageIdx = _PDF_GetPageObjectIndices()
    If @error Then Return 0
    Local $totalPages = UBound($aPageIdx) - 1
    If $totalPages <= 0 Then Return 0
    Local $aDel[$totalPages + 1]
    For $i = 0 To UBound($aSelLB) - 1
        Local $p = $aSelLB[$i] + 1
        If $p >= 1 And $p <= $totalPages Then $aDel[$p] = 1
    Next
    Local $keepCount = 0
    For $p = 1 To $totalPages
        If $aDel[$p] = 0 Then $keepCount += 1
    Next
    If $keepCount = 0 Then
        MsgBox($MB_ICONWARNING, "Delete Pages", "You cannot delete all pages.")
        Return 0
    EndIf
    For $p = 1 To $totalPages
        If $aDel[$p] = 1 Then
            Local $idx = $aPageIdx[$p]
            $g_aPDFObjects[$idx][6] = False
        EndIf
    Next
    Return _PDF_RewriteWithoutDeletedPages()
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

Func _DeleteSelectedPages()
    Local $aSel = _GUICtrlListBox_GetSelItems($lbPages)
    If Not IsArray($aSel) Or UBound($aSel) = 0 Then Return
    If MsgBox($MB_YESNO + $MB_ICONWARNING, "Confirm Delete", "Are you sure you want to delete the selected pages from the PDF file?") = $IDNO Then Return
    If _PDF_DeletePagesByIndices($aSel) Then
        LoadPDF($g_sCurrentPDF)
        MsgBox($MB_ICONINFORMATION, "Delete Pages", "Selected pages have been removed and the PDF has been saved.")
    Else
        MsgBox($MB_ICONERROR, "Delete Pages", "Failed to delete pages. PDF may be too complex or compression not supported.")
    EndIf
EndFunc

Func LoadPDF($sFile)
    $g_sCurrentPDF = $sFile
    WinSetTitle($hGUI, "", "PDF Page Counter - " & $sFile)
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
            Local $f = FileOpenDialog("Open PDF", @ScriptDir, "PDF Files (*.pdf)", 1)
            If Not @error Then LoadPDF($f)
        Case $btnDelete
            _DeleteSelectedPages()
        Case $mEditProps
            If $g_sCurrentPDF <> "" Then _ShowPDFProperties($g_sCurrentPDF)
        Case $mSave
            MsgBox($MB_ICONINFORMATION, "Save", "Save functionality not implemented.")
        Case $mSaveAs
            Local $o = FileSaveDialog("Save PDF As", @ScriptDir, "PDF Files (*.pdf)", 2)
            If Not @error And $g_sCurrentPDF <> "" Then FileCopy($g_sCurrentPDF, $o, 1)
        Case $mManual
            MsgBox($MB_ICONINFORMATION, "User Manual", "User manual goes here.")
        Case $mAbout
            MsgBox($MB_ICONINFORMATION, "About", "AutoIt PDF Page Counter Example.")
    EndSwitch
WEnd
