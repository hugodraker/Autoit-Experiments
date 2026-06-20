; ============================================================
; SINGLE-FILE PDF REWRITER WITH BUILT-IN ZLIB
; ============================================================

Global $hZlib = DllOpen("zlib1.dll")
If $hZlib = -1 Then
    MsgBox(16, "Error", "zlib1.dll not found.")
    Exit
EndIf

; -------------------------------
; ZLIB Inflate
; -------------------------------
Func _ZLIB_Uncompress($bInput)
    Local $iInLen = BinaryLen($bInput)
    Local $iOutLen = 20 * $iInLen

    Local $tOut = DllStructCreate("byte[" & $iOutLen & "]")
    Local $tIn  = DllStructCreate("byte[" & $iInLen & "]")
    DllStructSetData($tIn, 1, $bInput)

    Local $aCall = DllCall($hZlib, "int:cdecl", "uncompress", _
        "ptr", DllStructGetPtr($tOut), _
        "int*", $iOutLen, _
        "ptr", DllStructGetPtr($tIn), _
        "int", $iInLen)

    If @error Or $aCall[0] <> 0 Then Return SetError(1, 0, Binary(""))

    Return BinaryMid(DllStructGetData($tOut, 1), 1, $iOutLen)
EndFunc


; ============================================================
; PDF REWRITER (NO REGEX VERSION)
; ============================================================

Local $inFile = "input.pdf"
Local $outFile = "output_uncompressed.pdf"

Local $bin = FileRead($inFile)
If @error Then Exit MsgBox(16, "Error", "Cannot read input PDF")

Local $out = ""
Local $pos = 1

While 1
    Local $objPos = StringInStr($bin, " obj", 0, 1, $pos)
    If $objPos = 0 Then ExitLoop

    ; Find start of object
    Local $lineStart = StringInStr($bin, @LF, 0, -1, $objPos)
    If $lineStart = 0 Then $lineStart = 1

    Local $objStart = $lineStart

    ; Find end of object
    Local $objEnd = StringInStr($bin, "endobj", 0, 1, $objPos)
    If $objEnd = 0 Then ExitLoop

    Local $fullObj = StringMid($bin, $objStart, $objEnd + 6 - $objStart)

    ; Look for stream
    Local $streamPos = StringInStr($fullObj, "stream")
    If $streamPos > 0 Then
        Local $streamStart = $streamPos + 6

        ; Skip CR/LF
        While StringMid($fullObj, $streamStart, 1) = @CR Or _
              StringMid($fullObj, $streamStart, 1) = @LF
            $streamStart += 1
        WEnd

        Local $endStreamPos = StringInStr($fullObj, "endstream", 0, 1, $streamStart)
        If $endStreamPos > 0 Then
            Local $raw = StringMid($fullObj, $streamStart, $endStreamPos - $streamStart)

            ; Convert to binary
            Local $bComp = StringToBinary($raw, 1)

            ; Inflate
            Local $bDecomp = _ZLIB_Uncompress($bComp)
            If Not @error Then
                Local $newLen = BinaryLen($bDecomp)

                ; Replace Length
                $fullObj = StringRegExpReplace($fullObj, "/Length\s+\d+", "/Length " & $newLen)

                ; Replace stream content
                $fullObj = StringLeft($fullObj, $streamStart - 1) & _
                    @CRLF & BinaryToString($bDecomp, 1) & @CRLF & _
                    "endstream" & StringMid($fullObj, $endStreamPos + 9)
            EndIf
        EndIf
    EndIf

    $out &= $fullObj & @CRLF
    $pos = $objEnd + 6
WEnd

FileDelete($outFile)
FileWrite($outFile, $out)

MsgBox(64, "Done", "PDF rewritten successfully!")
