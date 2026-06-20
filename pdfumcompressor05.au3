#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <FileConstants.au3>
#include <MsgBoxConstants.au3>
#include <EditConstants.au3>
#include <StringConstants.au3>

#include "zlib udf.au3"

Global $g_hGUI = 0, $g_idLog = 0

Func _Log($s)
    If $g_idLog <> 0 Then
        GUICtrlSetData($g_idLog, GUICtrlRead($g_idLog) & $s & @CRLF)
    Else
        ConsoleWrite($s & @CRLF)
    EndIf
EndFunc

Func _ASCII85Decode($s)
    Local $out = Binary("0x")
    Local $len = StringLen($s), $i = 1, $group[5], $g = 0

    While $i <= $len
        Local $ch = StringMid($s, $i, 1)
        $i += 1

        If $ch = "~" Then ExitLoop
        If $ch = "z" Then
            If $g <> 0 Then Return SetError(1, 0, Binary(""))
            $out &= Binary("0x00000000")
            ContinueLoop
        EndIf

        If $ch = " " Or $ch = @CR Or $ch = @LF Or $ch = @TAB Then ContinueLoop

        $group[$g] = Asc($ch) - 33
        $g += 1

        If $g = 5 Then
            Local $val = 0
            For $k = 0 To 4
                $val = $val * 85 + $group[$k]
            Next
            Local $chunk = Binary("0x" & _
                Hex(BitShift($val, -24) And 0xFF, 2) & _
                Hex(BitShift($val, -16) And 0xFF, 2) & _
                Hex(BitShift($val, -8)  And 0xFF, 2) & _
                Hex($val And 0xFF, 2))
            $out &= $chunk
            $g = 0
        EndIf
    WEnd

    If $g > 0 Then
        For $k = $g To 4
            $group[$k] = 84
        Next
        Local $val = 0
        For $k = 0 To 4
            $val = $val * 85 + $group[$k]
        Next
        Local $chunk = Binary("0x" & _
            Hex(BitShift($val, -24) And 0xFF, 2) & _
            Hex(BitShift($val, -16) And 0xFF, 2) & _
            Hex(BitShift($val, -8)  And 0xFF, 2) & _
            Hex($val And 0xFF, 2))
        $out &= BinaryMid($chunk, 1, $g - 1)
    EndIf

    Return $out
EndFunc

Func _Inflate_AutoGrow($bCompressed, $iStartLen)
    Local $len = $iStartLen
    If $len < 1024 Then $len = 1024
    Local $maxLen = 64 * 1024 * 1024

    While $len <= $maxLen
        Local $bDecomp = _Zlib_UncompressBinary($bCompressed, $len)
        If IsBinary($bDecomp) Then Return $bDecomp
        $len *= 2
    WEnd

    Return SetError(1, 0, 0)
EndFunc

Func _GetLengthHint($pdfText, $objText)
    Local $m = StringRegExp($objText, '(?i)/Length\s+(\d+)\s+0\s+R', 1)
    If Not @error And IsArray($m) Then
        Local $objNum = $m[0]
        Local $pat = '(?is)\b' & $objNum & '\s+0\s+obj\s+(\d+)\s+endobj'
        Local $m2 = StringRegExp($pdfText, $pat, 1)
        If Not @error And IsArray($m2) Then Return Number($m2[0])
    EndIf

    $m = StringRegExp($objText, '(?i)/Length\s+(\d+)', 1)
    If Not @error And IsArray($m) Then Return Number($m[0])

    Return 0
EndFunc

Func _GetFilters($objText)
    Local $m = StringRegExp($objText, '(?is)/Filter\s*(\[[^\]]+\]|/[A-Za-z0-9]+)', 1)
    If @error Or Not IsArray($m) Then Return SetError(1, 0, 0)

    Local $f = $m[0]
    $f = StringReplace($f, "[", "")
    $f = StringReplace($f, "]", "")
    $f = StringStripWS($f, 8)

    Local $parts = StringRegExp($f, '/([A-Za-z0-9]+)', 3)
    If @error Or Not IsArray($parts) Then Return SetError(1, 0, 0)

    Return $parts
EndFunc

Func _ApplyFilters($filters, $streamData)
    Local $b = StringToBinary($streamData, $SB_ANSI)

    For $i = 0 To UBound($filters) - 1
        Switch StringLower($filters[$i])
            Case "ascii85decode"
                Local $s = BinaryToString($b, $SB_ANSI)
                $b = _ASCII85Decode($s)
                If @error Or Not IsBinary($b) Then Return SetError(1, 0, 0)

            Case "flatedecode"
                Local $hint = BinaryLen($b) * 4
                Local $bDecomp = _Inflate_AutoGrow($b, $hint)
                If @error Or Not IsBinary($bDecomp) Then Return SetError(1, 0, 0)
                $b = $bDecomp

            Case "lzwdecode", "runlengthdecode"
                ; left as-is for now (treated as already decoded)
        EndSwitch
    Next

    Return $b
EndFunc

Func _PDF_DecodeRawStreams($in, $out)
    Local $h = FileOpen($in, $FO_BINARY)
    If $h = -1 Then
        _Log("ERROR: Cannot open input file.")
        Return 1
    EndIf

    Local $bin = FileRead($h)
    FileClose($h)

    Local $txt = BinaryToString($bin, $SB_ANSI)
    _Log("Input size: " & BinaryLen($bin) & " bytes")

    ; header / basic guards
    If Not StringRegExp($txt, '^%PDF-1\.[0-9]') Then
        _Log("Not a PDF 1.x header, skipping.")
        Return 1
    EndIf
    If StringRegExp($txt, '(?i)/Encrypt') Then
        _Log("Encrypted PDF, unsupported.")
        Return 1
    EndIf
    If StringRegExp($txt, '(?i)/ObjStm') Then
        _Log("Object streams detected, PDF >=1.5, unsupported.")
        Return 1
    EndIf
    If StringRegExp($txt, '(?is)xref\s+.*?stream') Then
        _Log("Xref streams detected, PDF >=1.5, unsupported.")
        Return 1
    EndIf

    Local $objs = StringRegExp($txt, '(?is)(\d+\s+\d+\s+obj.*?endobj)', 1)
    If @error Or Not IsArray($objs) Then
        _Log("No PDF objects found.")
        Return 1
    EndIf

    _Log("Found " & UBound($objs) & " objects.")

    Local $result = $txt

    For $i = UBound($objs) - 1 To 0 Step -1
        Local $obj = $objs[$i]

        If Not StringRegExp($obj, '(?is)/Filter') Then ContinueLoop

        Local $filters = _GetFilters($obj)
        If @error Or Not IsArray($filters) Then ContinueLoop

        _Log("")
        _Log("Object #" & ($i + 1) & " filters: " & StringJoin($filters, ", "))

        Local $pStream = StringInStr($obj, "stream", 2)
        If $pStream = 0 Then ContinueLoop
        $pStream += 6

        While StringMid($obj, $pStream, 1) = @CR Or StringMid($obj, $pStream, 1) = @LF
            $pStream += 1
        WEnd

        Local $pEnd = StringInStr($obj, "endstream", 2)
        If $pEnd = 0 Then ContinueLoop

        Local $streamData = StringMid($obj, $pStream, $pEnd - $pStream)

        Local $lenHint = _GetLengthHint($txt, $obj)
        If $lenHint > 0 Then
            _Log("  /Length hint: " & $lenHint)
        Else
            _Log("  No /Length hint.")
        EndIf

        Local $bDecomp = _ApplyFilters($filters, $streamData)
        If @error Or Not IsBinary($bDecomp) Then
            _Log("  Filter chain failed, skipping object.")
            ContinueLoop
        EndIf

        Local $newLen = BinaryLen($bDecomp)
        _Log("  Decompressed length: " & $newLen)

        Local $sDecomp = BinaryToString($bDecomp, $SB_ANSI)

        Local $before = StringLeft($obj, $pStream - 1)
        Local $after  = StringMid($obj, $pEnd)
        Local $newObj = $before & $sDecomp & $after

        $newObj = StringRegExpReplace($newObj, '(?is)/Filter\s*(\[.*?\]|/[A-Za-z0-9]+)', "")
        If StringRegExp($newObj, '(?i)/Length\s+\d+') Then
            $newObj = StringRegExpReplace($newObj, '(?i)/Length\s+\d+', "/Length " & $newLen)
        EndIf

        $result = StringReplace($result, $obj, $newObj, 1)
        _Log("  Object replaced.")
    Next

    FileWrite($out, StringToBinary($result, $SB_ANSI))
    _Log("")
    _Log("Output size: " & BinaryLen(StringToBinary($result, $SB_ANSI)) & " bytes")

    Return 0
EndFunc

Func _OpenPDF()
    Local $f = FileOpenDialog("Open PDF", @ScriptDir, "PDF (*.pdf)", $FD_FILEMUSTEXIST)
    If @error Or $f = "" Then Return

    GUICtrlSetData($g_idLog, "")
    _Log("Selected: " & $f)

    Local $out = StringRegExpReplace($f, "\.pdf$", "", 1) & "_decoded.pdf"
    _Log("Output:   " & $out)

    _PDF_DecodeRawStreams($f, $out)
    MsgBox($MB_ICONINFORMATION, "Done", "Decoded PDF saved as:" & @CRLF & $out)
EndFunc

_Main()

Func _Main()
    _Zlib_Startup("zlib1.dll")

    $g_hGUI = GUICreate("PDF 1.4-style Raw Stream Decoder", 900, 550)

    Local $mFile = GUICtrlCreateMenu("&File")
    Local $mOpen = GUICtrlCreateMenuItem("&Open PDF...", $mFile)
    GUICtrlCreateMenuItem("", $mFile)
    Local $mExit = GUICtrlCreateMenuItem("E&xit", $mFile)

    $g_idLog = GUICtrlCreateEdit("", 5, 5, 890, 510, BitOR($ES_READONLY, $ES_MULTILINE, $ES_AUTOVSCROLL))
    GUICtrlSetFont($g_idLog, 9, 400, 0, "Consolas")

    GUISetState(@SW_SHOW)

    Local $accel[1][2] = [["^o", $mOpen]]
    GUISetAccelerators($accel)

    While True
        Switch GUIGetMsg()
            Case $GUI_EVENT_CLOSE, $mExit
                ExitLoop
            Case $mOpen
                _OpenPDF()
        EndSwitch
    WEnd

    _Zlib_Shutdown()
EndFunc
