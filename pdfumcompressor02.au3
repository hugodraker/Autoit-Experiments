#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <FileConstants.au3>
#include <MsgBoxConstants.au3>
#include <EditConstants.au3>
#include <StringConstants.au3>

#include "zlib udf.au3"

Global $g_hGUI = 0, $g_idLog = 0

; ============================================================
; LOGGING (must be defined before use)
; ============================================================
Func _Log($s)
    If $g_idLog <> 0 Then
        GUICtrlSetData($g_idLog, GUICtrlRead($g_idLog) & $s & @CRLF)
    Else
        ConsoleWrite($s & @CRLF)
    EndIf
EndFunc

; ============================================================
; ESCAPE TEXT FOR PDF LITERAL STRING
; ============================================================
Func _PDF_EscapeLiteral($s)
    $s = StringReplace($s, "\", "\\")
    $s = StringReplace($s, "(", "\(")
    $s = StringReplace($s, ")", "\)")

    Local $out = ""
    For $i = 1 To StringLen($s)
        Local $c = Asc(StringMid($s, $i, 1))
        If $c < 32 Or $c > 126 Then
            $out &= "\" & StringFormat("%03o", $c)
        Else
            $out &= Chr($c)
        EndIf
    Next

    Return "(" & $out & ")"
EndFunc

; ============================================================
; PDF STREAM DECODER → LITERAL STRING PDF
; ============================================================
Func _PDF_DecodeToLiteralStrings($in, $out)
    Local $h = FileOpen($in, $FO_BINARY)
    If $h = -1 Then
        _Log("ERROR: Cannot open input file.")
        Return 1
    EndIf

    Local $bin = FileRead($h)
    FileClose($h)

    Local $txt = BinaryToString($bin, $SB_ANSI)
    _Log("Input size: " & BinaryLen($bin) & " bytes")

    Local $objs = StringRegExp($txt, '(?is)(\d+\s+\d+\s+obj.*?endobj)', 1)
    If @error Or Not IsArray($objs) Then
        _Log("No PDF objects found.")
        Return 1
    EndIf

    _Log("Found " & UBound($objs) & " objects.")

    Local $result = $txt

    For $i = UBound($objs) - 1 To 0 Step -1
        Local $obj = $objs[$i]

        If Not StringRegExp($obj, '(?is)/Filter\s*(\[.*?\]|/FlateDecode)') Then ContinueLoop

        _Log("")
        _Log("Object #" & ($i + 1) & " contains FlateDecode")

        Local $pStream = StringInStr($obj, "stream", 2)
        If $pStream = 0 Then ContinueLoop
        $pStream += 6

        While StringMid($obj, $pStream, 1) = @CR Or StringMid($obj, $pStream, 1) = @LF
            $pStream += 1
        WEnd

        Local $pEnd = StringInStr($obj, "endstream", 2)
        If $pEnd = 0 Then ContinueLoop

        Local $streamData = StringMid($obj, $pStream, $pEnd - $pStream)
        Local $bCompressed = StringToBinary($streamData, $SB_ANSI)

        _Log("  Compressed length: " & BinaryLen($bCompressed))

        Local $lenMatch = StringRegExp($obj, '(?i)/Length\s+(\d+)', 1)
        If @error Or Not IsArray($lenMatch) Then
            _Log("  ERROR: No /Length found.")
            ContinueLoop
        EndIf

        Local $uncompressedLen = Number($lenMatch[0])
        _Log("  Expected uncompressed length: " & $uncompressedLen)

        Local $bDecomp = _Zlib_UncompressBinary($bCompressed, $uncompressedLen)
        If Not IsBinary($bDecomp) Then
            _Log("  ERROR: Decompression failed.")
            ContinueLoop
        EndIf

        Local $sDecomp = BinaryToString($bDecomp, $SB_ANSI)
        _Log("  Decompressed length: " & StringLen($sDecomp))

        Local $literal = _PDF_EscapeLiteral($sDecomp)
        Local $newLength = StringLen($literal)

        _Log("  Literal string length: " & $newLength)

        ; Build new object
        Local $before = StringLeft($obj, $pStream - 1)
        Local $after  = StringMid($obj, $pEnd)

        Local $newObj = $before & $literal & $after

        $newObj = StringRegExpReplace($newObj, '(?is)/Filter\s*(\[.*?\]|/FlateDecode)', "")
        $newObj = StringRegExpReplace($newObj, '(?i)/Length\s+\d+', "/Length " & $newLength)

        $result = StringReplace($result, $obj, $newObj, 1)
        _Log("  Object replaced.")
    Next

    FileWrite($out, StringToBinary($result, $SB_ANSI))
    _Log("")
    _Log("Output size: " & BinaryLen(StringToBinary($result, $SB_ANSI)) & " bytes")

    Return 0
EndFunc

; ============================================================
; FILE → OPEN
; ============================================================
Func _OpenPDF()
    Local $f = FileOpenDialog("Open PDF", @ScriptDir, "PDF (*.pdf)", $FD_FILEMUSTEXIST)
    If @error Or $f = "" Then Return

    GUICtrlSetData($g_idLog, "")
    _Log("Selected: " & $f)

    Local $out = StringRegExpReplace($f, "\.pdf$", "", 1) & "_decoded.pdf"
    _Log("Output:   " & $out)

    _PDF_DecodeToLiteralStrings($f, $out)
EndFunc

; ============================================================
; MAIN GUI (must be last)
; ============================================================
_Main()

Func _Main()
    $g_hGUI = GUICreate("PDF Literal-String Decoder (zlib udf.au3)", 900, 550)

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
EndFunc
