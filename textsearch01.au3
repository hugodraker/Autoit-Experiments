#include <WindowsConstants.au3>
#include <FileConstants.au3>
#include <MsgBoxConstants.au3>
#include <WinAPIFiles.au3>
#include <Array.au3>
#include <File.au3>
#include <AutoItConstants.au3>
#include <WinAPISysWin.au3>

Global $sFile = "Xtron-8tb.txt"
Global $sSearch = "ERROR"

_SearchLargeFile($sFile, $sSearch)

Func _SearchLargeFile($sFile, $sSearch)
    Local $hFile = FileOpen($sFile, $FO_READ)

    If $hFile = -1 Then Return

    Local $sBuffer = ""
    Local $iLineNum = 0

    While 1
        Local $sChunk = FileRead($hFile, 1024 * 1024) ; 1 MB chunks

        If @error Or $sChunk = "" Then ExitLoop

        $sBuffer &= $sChunk

        Local $aLines = StringSplit(StringReplace($sBuffer, @CRLF, @LF), @LF, 1)

        For $i = 1 To $aLines[0] - 1
            $iLineNum += 1

            If StringInStr($aLines[$i], $sSearch, 2) Then
                ConsoleWrite("Match at line " & $iLineNum & @CRLF)
            EndIf
        Next

        ; Preserve incomplete last line
        $sBuffer = $aLines[$aLines[0]]
    WEnd

    ; Process remaining data
    If $sBuffer <> "" Then
        $iLineNum += 1

        If StringInStr($sBuffer, $sSearch, 2) Then
            ConsoleWrite("Match at line " & $iLineNum & @CRLF)
        EndIf
    EndIf

    FileClose($hFile)
EndFunc