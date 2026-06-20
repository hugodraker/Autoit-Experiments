#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <FileConstants.au3>
#include <MsgBoxConstants.au3>
#include <EditConstants.au3>
#include <StringConstants.au3>

#include "zlib udf.au3"

Global $g_hGUI = 0, $g_idLog = 0
_Zlib_Startup("zlib1.dll")

; ============================================================
; LOGGING
; ============================================================
Func _Log($s)
    If $g_idLog <> 0 Then
        GUICtrlSetData($g_idLog, GUICtrlRead($g_idLog) & $s & @CRLF)
    Else
        ConsoleWrite($s & @CRLF)
    EndIf
EndFunc

; ============================================================
; AUTO-EXPAND DECOMPRESS (DOUBLE BUFFER GROWTH)
; ============================================================
Func _Inflate_AutoGrow($bCompressed, $iStartLen)
    Local $len = $iStartLen
    If $len < 1024 Then $len = 1024
    Local $maxLen = 64 * 1024 * 1024 ; 64 MB safety

    While $len <= $maxLen
        Local $bDecomp = _Zlib_UncompressBinary($bCompressed, $len)
        If IsBinary($bDecomp) Then Return $bDecomp
        $len *= 2
    WEnd

    Return SetError(1, 0, 0)
EndFunc

; ============================================================
; PDF STREAM DECODER → RAW BINARY STREAMS (qpdf-style)
; ============================================================
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

    Local $objs = StringRegExp($txt, '(?is)(\d+\s+\d+\s+obj.*?endobj)', 1)
    If @error Or Not IsArray($objs) Then
        _Log("No PDF objects found.")
        Return 1
    EndIf

    _Log("Found " & UBound($objs) & " objects.")

    Local $result = $txt

    For $i = UBound($objs) - 1 To 0 Step -1
        Local $obj = $objs[$i]

        ; Only objects with FlateDecode
        If Not StringRegExp($obj, '(?is)/Filter\s*(\[.*?\]|/FlateDecode)') Then ContinueLoop

        _Log("")
        _Log("Object #" & ($i + 1) & " contains FlateDecode")

        ; Find stream start
        Local $pStream = StringInStr($obj, "stream", 2)
        If $pStream = 0 Then
            _Log("  No 'stream' keyword.")
            ContinueLoop
        EndIf
        $pStream += 6

        ; Skip CR/LF
        While StringMid($obj, $pStream, 1) = @CR Or StringMid($obj, $pStream, 1) = @LF
            $pStream += 1
        WEnd

        ; Find endstream
        Local $pEnd = StringInStr($obj, "endstream", 2)
        If $pEnd = 0 Then
            _Log("  No 'endstream' keyword.")
            ContinueLoop
        EndIf

        Local $streamData = StringMid($obj, $pStream, $pEnd - $pStream)
        Local $bCompressed = StringToBinary($streamData, $SB_ANSI)

        _Log("  Compressed length: " & BinaryLen($bCompressed))

        ; Try to get /Length N (if present)
        Local $lenMatch = StringRegExp($obj, '(?i)/Length\s+(\d+)', 1)
        Local $startLen = 0
        If Not @error And IsArray($lenMatch) Then
            $startLen = Number($lenMatch[0])
            _Log("  /Length hint: " & $startLen)
        Else
            _Log("  No /Length hint, starting with 1024.")
            $startLen = 1024
        EndIf

        ; Auto-expand buffer until zlib succeeds
        Local $bDecomp = _Inflate_AutoGrow($bCompressed, $startLen)
        If @error Or Not IsBinary($bDecomp) Then
            _Log("  ERROR: Decompression failed after auto-grow.")
            ContinueLoop
        EndIf

        Local $newLen = BinaryLen($bDecomp)
        _Log("  Decompressed length: " & $newLen)

        ; Convert decompressed binary to string (1:1 mapping via SB_ANSI)
        Local $sDecomp = BinaryToString($bDecomp, $SB_ANSI)

        ; Rebuild object: replace stream content
        Local $before = StringLeft($obj, $pStream - 1)
        Local $after  = StringMid($obj, $pEnd)
        Local $newObj = $before & $sDecomp & $after

        ; Remove /Filter /FlateDecode
        $newObj = StringRegExpReplace($newObj, '(?is)/Filter\s*(\[.*?\]|/FlateDecode)', "")

        ; Update /Length to newLen
        If StringRegExp($newObj, '(?i)/Length\s+\d+') Then
            $newObj = StringRegExpReplace($newObj, '(?i)/Length\s+\d+', "/Length " & $newLen)
        Else
            ; If no direct /Length, we leave it (indirect lengths would need extra handling)
            _Log("  WARNING: /Length is indirect or missing; not updated.")
        EndIf

        ; Replace object in full PDF text
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

    _PDF_DecodeRawStreams($f, $out)
    MsgBox($MB_ICONINFORMATION, "Done", "Decoded PDF saved as:" & @CRLF & $out)
EndFunc

; ============================================================
; MAIN GUI
; ============================================================
_Main()

Func _Main()
    $g_hGUI = GUICreate("PDF Raw Stream Decoder (qpdf-style, zlib udf.au3)", 900, 550)

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
			_Zlib_Shutdown()
                ExitLoop
            Case $mOpen
                _OpenPDF()
        EndSwitch
    WEnd
EndFunc
