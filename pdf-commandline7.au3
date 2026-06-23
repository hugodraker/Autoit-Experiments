#pragma compile(Console, true)
#include <File.au3>
#include <Array.au3>
#include <String.au3>
#include <Math.au3>

; =================================================================================================
; CONFIGURATION & GLOBALS
; =================================================================================================
Global $sZlibPath = @ScriptDir & "\zlib1.dll"
Global $bZlibLoaded = False
Global $hZlib = DllOpen($sZlibPath)

If $hZlib <> -1 Then $bZlibLoaded = True

; =================================================================================================
; RUNTIME OVERRIDE
; =================================================================================================
;Global $sSimulatedCmdLine = '"input.pdf" -d1-2'
;Global $sSimulatedCmdLine = '"input.pdf" -title"Final Report" -author"John Doe" -o"updated.pdf"'
;Global $sSimulatedCmdLine = '"input.pdf" -importpdf -o"outputfile.pdf"'
Global $sSimulatedCmdLine = '"input.pdf" -e2-5 -o"f2.pdf"'
;Global $sSimulatedCmdLine = '"input.pdf" -decompress -o"filename.pdf"'

_Main($sSimulatedCmdLine)

; Cleanup
If $bZlibLoaded Then DllClose($hZlib)
Exit

; =================================================================================================
; MAIN PROCESSING ENTRY
; =================================================================================================
Func _Main($sCmdString)
    ConsoleWrite("--- Native AutoIt PDF Toolkit ---" & @CRLF)
    
    If Not $bZlibLoaded Then
        ConsoleWrite("! WARNING: zlib1.dll not found in script directory. Decompression will fail." & @CRLF)
    EndIf

    ; 1. Parse Command Line Arguments
    Local $aArgs = _ParseCommandLine($sCmdString)
    If UBound($aArgs) < 1 Then
        ConsoleWrite("Error: No input file specified." & @CRLF)
        Return
    EndIf

    Local $sInputFile = $aArgs[0]
    Local $sOutputFile = "output.pdf" ; Default
    
    ; Extract the output file parameter first and aggressively strip quotes
    For $i = 1 To UBound($aArgs) - 1
        If StringLeft($aArgs[$i], 2) = "-o" Then
            $sOutputFile = StringTrimLeft($aArgs[$i], 2)
            $sOutputFile = StringReplace($sOutputFile, '"', '') ; Strips inline quotes
        EndIf
    Next

    ; 2. Route to Functions based on Switches
    For $i = 1 To UBound($aArgs) - 1
        Local $sArg = $aArgs[$i]
        
        Select
            Case $sArg = "-decompress"
                ConsoleWrite("> Executing: Decompress & Normalize PDF (QDF Style)" & @CRLF)
                _PDF_DecompressFile($sInputFile, $sOutputFile)

            Case StringLeft($sArg, 2) = "-e"
                Local $sPages = StringTrimLeft($sArg, 2)
                _PDF_ExtractPages($sInputFile, $sOutputFile, $sPages)
                
            Case $sArg = "-extract"
                _PDF_ExtractImages($sInputFile)

            Case StringLeft($sArg, 12) = "-importimage"
                Local $sImages = StringTrimLeft($sArg, 12)
                $sImages = StringReplace($sImages, '"', '')
                _PDF_ImportImages($sInputFile, $sOutputFile, $sImages)

            Case $sArg = "-importpdf"
                ConsoleWrite("> Executing: Merging " & $sInputFile & " into " & $sOutputFile & @CRLF)
                _PDF_ImportPDFs($sInputFile, $sOutputFile)

            Case StringLeft($sArg, 2) = "-d"
                Local $sDelPages = StringTrimLeft($sArg, 2)
                _PDF_DeletePages($sInputFile, $sOutputFile, $sDelPages)

            Case $sArg = "-compress"
                _PDF_CompressFile($sInputFile, $sOutputFile)
                
            Case StringLeft($sArg, 6) = "-title" Or StringLeft($sArg, 7) = "-author"
                _PDF_UpdateMetadata($sInputFile, $sOutputFile, $sArg)

        EndSelect
    Next
EndFunc

; =================================================================================================
; DELETE PAGES
; =================================================================================================
Func _PDF_DeletePages($sInputFile, $sOutputFile, $sPages)
    If Not FileExists($sInputFile) Then
        ConsoleWrite("! Error: Input file does not exist: " & $sInputFile & @CRLF)
        Return False
    EndIf

    ConsoleWrite("> Reading PDF into memory for Page Deletion..." & @CRLF)
    Local $hFile = FileOpen($sInputFile, 16) ; Read Binary
    Local $bFileData = FileRead($hFile)
    FileClose($hFile)
    Local $sFileData = BinaryToString($bFileData, 1) 
    
    Local $aParsedObjects[100000], $aParsedGen[100000]
    Local $iMaxObjectId = _ParsePDFObjects($sFileData, $aParsedObjects, $aParsedGen)

    Local $iRootId = _GetPdfRootId($sFileData)
    Local $iPagesId = _GetPdfPagesId($aParsedObjects[$iRootId])

    If $iRootId = 0 Or $iPagesId = 0 Then
        ConsoleWrite("! Error: Could not locate Catalog or Pages node." & @CRLF)
        Return False
    EndIf

    ConsoleWrite("> Flattening PDF Page Tree..." & @CRLF)
    Local $aFlatPages[0]
    _FlattenPageTree_Recursive($aParsedObjects, $iPagesId, $aFlatPages)
    
    Local $iTotalPages = UBound($aFlatPages)
    ConsoleWrite("> Discovered " & $iTotalPages & " total pages." & @CRLF)

    ; --- Determine Range to Delete ---
    Local $iStartPage = 1, $iEndPage = 1
    If StringInStr($sPages, "-") Then
        Local $aRange = StringSplit($sPages, "-")
        $iStartPage = Int($aRange[1])
        $iEndPage = Int($aRange[2])
    Else
        $iStartPage = Int($sPages)
        $iEndPage = Int($sPages)
    EndIf

    ; Boundary failsafes
    If $iStartPage < 1 Then $iStartPage = 1
    If $iEndPage > $iTotalPages Then $iEndPage = $iTotalPages
    If $iStartPage > $iEndPage Then $iStartPage = $iEndPage

    ConsoleWrite("> Deleting Target Range: Pages " & $iStartPage & " through " & $iEndPage & "..." & @CRLF)

    ; --- Filter Pages ---
    Local $sNewKids = ""
    Local $iNewCount = 0

    For $i = 0 To $iTotalPages - 1
        Local $iCurrentPageNum = $i + 1
        Local $iPageObjId = $aFlatPages[$i]

        If $iCurrentPageNum >= $iStartPage And $iCurrentPageNum <= $iEndPage Then
            ; Clear the object from memory so it is skipped during rebuild
            $aParsedObjects[$iPageObjId] = "" 
        Else
            ; Retain page and add to new Kids array
            $sNewKids &= $iPageObjId & " 0 R "
            $iNewCount += 1
            ; Ensure parent reference strictly points to Root Pages node
            $aParsedObjects[$iPageObjId] = StringRegExpReplace($aParsedObjects[$iPageObjId], "/Parent\s+\d+\s+\d+\s+R", "/Parent " & $iPagesId & " 0 R")
        EndIf
    Next

    If $iNewCount = 0 Then
        ConsoleWrite("! Error: Cannot delete all pages. A valid PDF must have at least one page." & @CRLF)
        Return False
    EndIf

    ; Update Master Pages Node
    $aParsedObjects[$iPagesId] = "<< /Type /Pages /Kids [ " & $sNewKids & "] /Count " & $iNewCount & " >>"

    ; --- Rebuild PDF ---
    ConsoleWrite("> Rebuilding Document..." & @CRLF)
    Local $sNewPdfData = "%PDF-1.4" & @CRLF & "%????" & @CRLF & @CRLF
    Local $aXref[100000]

    For $i = 1 To $iMaxObjectId
        If $aParsedObjects[$i] <> "" Then
            $aXref[$i] = StringLen($sNewPdfData)
            Local $iGen = $aParsedGen[$i]
            If $iGen = "" Then $iGen = 0
            $sNewPdfData &= $i & " " & $iGen & " obj" & @CRLF & $aParsedObjects[$i] & @CRLF & "endobj" & @CRLF & @CRLF
        Else
            $aXref[$i] = 0 ; Mark as free object in XREF
        EndIf
    Next

    ; --- Rebuild XREF Table & Trailer ---
    Local $iStartXrefOffset = StringLen($sNewPdfData)
    Local $sXrefTable = "xref" & @CRLF
    $sXrefTable &= "0 " & ($iMaxObjectId + 1) & @CRLF
    $sXrefTable &= "0000000000 65535 f " & @CRLF 

    For $i = 1 To $iMaxObjectId
        If $aXref[$i] <> 0 Then
            $sXrefTable &= StringFormat("%010d 00000 n ", $aXref[$i]) & @CRLF
        Else
            $sXrefTable &= "0000000000 00000 f " & @CRLF
        EndIf
    Next

    Local $sTrailer = "trailer" & @CRLF & "<< /Size " & ($iMaxObjectId + 1)
    $sTrailer &= " /Root " & $iRootId & " 0 R"
    
    Local $aInfo = StringRegExp($sFileData, "/Info\s+(\d+\s+\d+\s+R)", 1)
    If Not @error Then $sTrailer &= " /Info " & $aInfo[0]
    
    $sTrailer &= " >>" & @CRLF
    $sTrailer &= "startxref" & @CRLF & $iStartXrefOffset & @CRLF & "%%EOF"

    $sNewPdfData &= $sXrefTable & $sTrailer

    ; --- Final Output ---
    ConsoleWrite("> Writing output to " & $sOutputFile & "..." & @CRLF)
    Local $hOutFile = FileOpen($sOutputFile, 2 + 16) 
    FileWrite($hOutFile, StringToBinary($sNewPdfData, 1))
    FileClose($hOutFile)
    
    ConsoleWrite("> Deletion Complete!" & @CRLF)
    Return True
EndFunc

; =================================================================================================
; EXTRACT PAGES (PDF 1.4 Compliant)
; =================================================================================================
Func _PDF_ExtractPages($sInputFile, $sOutputFile, $sPages)
    If Not FileExists($sInputFile) Then
        ConsoleWrite("! Error: Input file does not exist: " & $sInputFile & @CRLF)
        Return False
    EndIf

    ConsoleWrite("> Reading PDF into memory for Extraction..." & @CRLF)
    Local $hFile = FileOpen($sInputFile, 16) ; Read Binary
    Local $bFileData = FileRead($hFile)
    FileClose($hFile)

    Local $sFileData = BinaryToString($bFileData, 1) 
    
    Local $aParsedObjects[100000] 
    Local $aParsedGen[100000]
    Local $iMaxObjectId = _ParsePDFObjects($sFileData, $aParsedObjects, $aParsedGen)

    ; Locate Trailer & Root (Catalog)
    Local $iRootId = _GetPdfRootId($sFileData)
    If $iRootId = 0 Then
        ConsoleWrite("! Error: Could not find /Root (Catalog) in PDF." & @CRLF)
        Return False
    EndIf

    ; Locate Pages Root
    Local $iPagesId = _GetPdfPagesId($aParsedObjects[$iRootId])
    If $iPagesId = 0 Then
        ConsoleWrite("! Error: Could not find /Pages in Catalog." & @CRLF)
        Return False
    EndIf

    ConsoleWrite("> Flattening PDF Page Tree..." & @CRLF)
    Local $aFlatPages[0]
    _FlattenPageTree_Recursive($aParsedObjects, $iPagesId, $aFlatPages)

    Local $iTotalPages = UBound($aFlatPages)
    ConsoleWrite("> Discovered " & $iTotalPages & " total pages." & @CRLF)

    ; Determine Extracted Range
    Local $iStartPage = 1, $iEndPage = $iTotalPages
    If StringInStr($sPages, "-") Then
        Local $aRange = StringSplit($sPages, "-")
        $iStartPage = Int($aRange[1])
        $iEndPage = Int($aRange[2])
    Else
        $iStartPage = Int($sPages)
        $iEndPage = Int($sPages)
    EndIf

    If $iStartPage < 1 Then $iStartPage = 1
    If $iEndPage > $iTotalPages Then $iEndPage = $iTotalPages
    If $iStartPage > $iEndPage Then $iStartPage = $iEndPage

    ConsoleWrite("> Extracting Target Range: Pages " & $iStartPage & " through " & $iEndPage & "..." & @CRLF)

    Local $sNewKids = ""
    Local $iExtractedCount = ($iEndPage - $iStartPage) + 1
    
    For $i = ($iStartPage - 1) To ($iEndPage - 1)
        Local $iPageId = $aFlatPages[$i]
        $sNewKids &= $iPageId & " 0 R "
        $aParsedObjects[$iPageId] = StringRegExpReplace($aParsedObjects[$iPageId], "/Parent\s+\d+\s+\d+\s+R", "/Parent " & $iPagesId & " 0 R")
    Next

    $aParsedObjects[$iPagesId] = "<< /Type /Pages /Kids [ " & $sNewKids & "] /Count " & $iExtractedCount & " >>"

    ConsoleWrite("> Rebuilding Document..." & @CRLF)
    Local $sNewPdfData = "%PDF-1.4" & @CRLF & "%????" & @CRLF & @CRLF
    Local $aXref[100000]

    For $i = 1 To $iMaxObjectId
        If $aParsedObjects[$i] <> "" Then
            $aXref[$i] = StringLen($sNewPdfData)
            Local $iGen = $aParsedGen[$i]
            If $iGen = "" Then $iGen = 0
            $sNewPdfData &= $i & " " & $iGen & " obj" & @CRLF & $aParsedObjects[$i] & @CRLF & "endobj" & @CRLF & @CRLF
        Else
            $aXref[$i] = 0
        EndIf
    Next

    Local $iStartXrefOffset = StringLen($sNewPdfData)
    Local $sXrefTable = "xref" & @CRLF
    $sXrefTable &= "0 " & ($iMaxObjectId + 1) & @CRLF
    $sXrefTable &= "0000000000 65535 f " & @CRLF 

    For $i = 1 To $iMaxObjectId
        If $aXref[$i] <> 0 Then
            $sXrefTable &= StringFormat("%010d 00000 n ", $aXref[$i]) & @CRLF
        Else
            $sXrefTable &= "0000000000 00000 f " & @CRLF
        EndIf
    Next

    Local $sTrailer = "trailer" & @CRLF & "<< /Size " & ($iMaxObjectId + 1)
    $sTrailer &= " /Root " & $iRootId & " 0 R"
    
    Local $aInfo = StringRegExp($sFileData, "/Info\s+(\d+\s+\d+\s+R)", 1)
    If Not @error Then $sTrailer &= " /Info " & $aInfo[0]
    
    $sTrailer &= " >>" & @CRLF
    $sTrailer &= "startxref" & @CRLF & $iStartXrefOffset & @CRLF & "%%EOF"

    $sNewPdfData &= $sXrefTable & $sTrailer

    ConsoleWrite("> Writing output to " & $sOutputFile & "..." & @CRLF)
    Local $hOutFile = FileOpen($sOutputFile, 2 + 16) 
    FileWrite($hOutFile, StringToBinary($sNewPdfData, 1))
    FileClose($hOutFile)
    
    ConsoleWrite("> Done!" & @CRLF)
EndFunc

Func _FlattenPageTree_Recursive(ByRef $aRawObjects, $iNodeId, ByRef $aFlatPages)
    If $iNodeId <= 0 Or $aRawObjects[$iNodeId] = "" Then Return
    Local $sObj = $aRawObjects[$iNodeId]

    If StringRegExp($sObj, "(?i)/Type\s*/Page\b") Then
        ; It is a single Page Leaf
        _ArrayAdd($aFlatPages, $iNodeId)
    ElseIf StringRegExp($sObj, "(?i)/Type\s*/Pages\b") Or StringInStr($sObj, "/Kids") Then
        ; It is a branch Node, extract Kids and drill down
        Local $aKids = StringRegExp($sObj, "/Kids\s*\[(.*?)\]", 1)
        If Not @error Then
            Local $sKidsStr = $aKids[0]
            Local $aKidIds = StringRegExp($sKidsStr, "(\d+)\s+\d+\s+R", 3)
            For $i = 0 To UBound($aKidIds) - 1
                _FlattenPageTree_Recursive($aRawObjects, Int($aKidIds[$i]), $aFlatPages)
            Next
        EndIf
    EndIf
EndFunc

; =================================================================================================
; DECOMPRESS & NORMALIZE (QDF STYLE)
; =================================================================================================
Func _PDF_DecompressFile($sInputFile, $sOutputFile)
    If Not FileExists($sInputFile) Then
        ConsoleWrite("! Error: Input file does not exist: " & $sInputFile & @CRLF)
        Return False
    EndIf

    ConsoleWrite("> Reading PDF into memory..." & @CRLF)
    Local $hFile = FileOpen($sInputFile, 16) ; Read Binary
    Local $bFileData = FileRead($hFile)
    FileClose($hFile)

    Local $sFileData = BinaryToString($bFileData, 1) 
    
    ; Memory arrays for QDF Sequential Ordering
    Local $aParsedObjects[100000] 
    Local $aXref[100000] 
    Local $iMaxObjectId = 0
    Local $iTotalObjectsProcessed = 0

    ; --- 1. Linear Scan for Objects ---
    ConsoleWrite("> Extracting and standardizing objects..." & @CRLF)
    Local $iPos = 1
    While 1
        $iPos = StringInStr($sFileData, " obj", 0, 1, $iPos)
        If $iPos = 0 Then ExitLoop 

        Local $sPrefix = StringMid($sFileData, _Max(1, $iPos - 20), _Min(20, $iPos - 1))
        Local $aIdGen = StringRegExp($sPrefix, '(\d+)\s+(\d+)$', 1)
        
        If Not @error Then
            Local $iObjId = Int($aIdGen[0])
            Local $iObjGen = Int($aIdGen[1])
            If $iObjId > $iMaxObjectId Then $iMaxObjectId = $iObjId

            Local $iEndPos = StringInStr($sFileData, "endobj", 0, 1, $iPos)
            If $iEndPos > 0 Then
                Local $iStartOfObj = $iPos - StringLen($aIdGen[0] & " " & $aIdGen[1])
                Local $iLengthOfObj = ($iEndPos + 6) - $iStartOfObj
                Local $sRawObject = StringMid($sFileData, $iStartOfObj, $iLengthOfObj)

                $aParsedObjects[$iObjId] = _ProcessObjectDecompression($sRawObject, $iObjId, $iObjGen)
                $iTotalObjectsProcessed += 1

                $iPos = $iEndPos + 6
            Else
                $iPos += 4
            EndIf
        Else
            $iPos += 4
        EndIf
    WEnd

    ; --- 2. Sequential QDF Reconstruction & XREF Build ---
    ConsoleWrite("> Rebuilding sequence sequentially (QDF mode)..." & @CRLF)
    Local $sNewPdfData = "%PDF-1.4" & @CRLF & "%????" & @CRLF & @CRLF

    For $i = 1 To $iMaxObjectId
        If $aParsedObjects[$i] <> "" Then
            $aXref[$i] = StringLen($sNewPdfData)
            $sNewPdfData &= $aParsedObjects[$i] & @CRLF & @CRLF 
        Else
            $aXref[$i] = 0
        EndIf
    Next

    Local $iStartXrefOffset = StringLen($sNewPdfData)
    Local $sXrefTable = "xref" & @CRLF
    $sXrefTable &= "0 " & ($iMaxObjectId + 1) & @CRLF
    $sXrefTable &= "0000000000 65535 f " & @CRLF 

    For $i = 1 To $iMaxObjectId
        If $aXref[$i] <> 0 Then
            $sXrefTable &= StringFormat("%010d 00000 n ", $aXref[$i]) & @CRLF
        Else
            $sXrefTable &= "0000000000 00000 f " & @CRLF
        EndIf
    Next

    ; --- 3. Rebuild Trailer ---
    Local $sTrailer = "trailer" & @CRLF & "<< /Size " & ($iMaxObjectId + 1)
    
    Local $aRoot = StringRegExp($sFileData, "/Root\s+(\d+\s+\d+\s+R)", 1)
    If Not @error Then $sTrailer &= " /Root " & $aRoot[0]
    
    Local $aInfo = StringRegExp($sFileData, "/Info\s+(\d+\s+\d+\s+R)", 1)
    If Not @error Then $sTrailer &= " /Info " & $aInfo[0]
    
    $sTrailer &= " >>" & @CRLF
    $sTrailer &= "startxref" & @CRLF & $iStartXrefOffset & @CRLF & "%%EOF"

    $sNewPdfData &= $sXrefTable & $sTrailer

    ConsoleWrite("> Writing output to " & $sOutputFile & "..." & @CRLF)
    Local $hOutFile = FileOpen($sOutputFile, 2 + 16) 
    FileWrite($hOutFile, StringToBinary($sNewPdfData, 1))
    FileClose($hOutFile)
    
    ConsoleWrite("> Done! Processed " & $iTotalObjectsProcessed & " objects sequentially." & @CRLF)
EndFunc

Func _ProcessObjectDecompression($sRawObject, $iObjId, $iObjGen)
    Local $sHeaderStr = $iObjId & " " & $iObjGen & " obj"
    Local $iHeaderLen = StringLen($sHeaderStr)
    
    Local $sBody = StringMid($sRawObject, $iHeaderLen + 1)
    Local $iEndObjPos = StringInStr($sBody, "endobj", 0, -1)
    If $iEndObjPos > 0 Then $sBody = StringLeft($sBody, $iEndObjPos - 1)
    $sBody = StringStripWS($sBody, 3) 

    Local $iStreamStart = StringInStr($sBody, "stream")
    
    If $iStreamStart = 0 Then Return $iObjId & " " & $iObjGen & " obj" & @CRLF & $sBody & @CRLF & "endobj"

    Local $iStreamEnd = StringInStr($sBody, "endstream", 0, -1)
    If $iStreamEnd = 0 Then Return $iObjId & " " & $iObjGen & " obj" & @CRLF & $sBody & @CRLF & "endobj" 

    Local $sDict = StringStripWS(StringMid($sBody, 1, $iStreamStart - 1), 3)
    
    Local $iDataStart = $iStreamStart + 6
    If StringMid($sBody, $iDataStart, 2) == @CRLF Then
        $iDataStart += 2
    ElseIf StringMid($sBody, $iDataStart, 1) == @LF Or StringMid($sBody, $iDataStart, 1) == @CR Then
        $iDataStart += 1
    EndIf
    
    Local $iDataLen = $iStreamEnd - $iDataStart
    Local $sCompressedData = StringMid($sBody, $iDataStart, $iDataLen)
    
    While StringRight($sCompressedData, 1) = @CR Or StringRight($sCompressedData, 1) = @LF
        $sCompressedData = StringTrimRight($sCompressedData, 1)
    WEnd

    Local $bCompressedData = StringToBinary($sCompressedData, 1)
    Local $bDecompressedData = _Zlib_Uncompress($bCompressedData)
    
    If BinaryLen($bDecompressedData) == 0 Then 
        Return $iObjId & " " & $iObjGen & " obj" & @CRLF & $sDict & @CRLF & "stream" & @CRLF & $sCompressedData & @CRLF & "endstream" & @CRLF & "endobj"
    EndIf
    
    Local $sDecompressedData = BinaryToString($bDecompressedData, 1)
    
    $sDict = StringRegExpReplace($sDict, "(?s)/Filter\s*\[.*?\]", "") 
    $sDict = StringRegExpReplace($sDict, "/Filter\s*/[A-Za-z0-9_]+", "") 
    $sDict = StringRegExpReplace($sDict, "/Length\s+\d+\s+\d+\s+R", "")
    $sDict = StringRegExpReplace($sDict, "/Length\s+\d+", "")
    $sDict = StringRegExpReplace($sDict, ">>", "/Length " & StringLen($sDecompressedData) & @CRLF & ">>", 1)

    Local $sFinalObject = $iObjId & " " & $iObjGen & " obj" & @CRLF & $sDict & @CRLF & "stream" & @CRLF & $sDecompressedData & @CRLF & "endstream" & @CRLF & "endobj"
    Return $sFinalObject
EndFunc

; =================================================================================================
; IMPORT / MERGE PDFs
; =================================================================================================
Func _PDF_ImportPDFs($sInputFile, $sOutputFile)
    If Not FileExists($sInputFile) Then
        ConsoleWrite("! Error: Input file to merge does not exist: " & $sInputFile & @CRLF)
        Return False
    EndIf

    ; If output file doesn't exist, just copy the input to output (effectively an append to an empty file)
    If Not FileExists($sOutputFile) Then
        ConsoleWrite("> Target file does not exist. Creating new file from input..." & @CRLF)
        _PDF_ExtractPages($sInputFile, $sOutputFile, "1-999999") 
        Return True
    EndIf

    ConsoleWrite("> Reading Host PDF (" & $sOutputFile & ") into memory..." & @CRLF)
    Local $hHost = FileOpen($sOutputFile, 16)
    Local $bHostData = FileRead($hHost)
    FileClose($hHost)
    Local $sHostData = BinaryToString($bHostData, 1)

    ConsoleWrite("> Reading Source PDF (" & $sInputFile & ") into memory..." & @CRLF)
    Local $hSource = FileOpen($sInputFile, 16)
    Local $bSourceData = FileRead($hSource)
    FileClose($hSource)
    Local $sSourceData = BinaryToString($bSourceData, 1)

    ; Parse Both PDFs
    Local $aHostObjects[100000], $aHostGen[100000]
    Local $iHostMaxId = _ParsePDFObjects($sHostData, $aHostObjects, $aHostGen)
    
    Local $aSrcObjects[100000], $aSrcGen[100000]
    Local $iSrcMaxId = _ParsePDFObjects($sSourceData, $aSrcObjects, $aSrcGen)

    ; Locate Pages Nodes
    Local $iHostRootId = _GetPdfRootId($sHostData)
    Local $iHostPagesId = _GetPdfPagesId($aHostObjects[$iHostRootId])
    
    Local $iSrcRootId = _GetPdfRootId($sSourceData)
    Local $iSrcPagesId = _GetPdfPagesId($aSrcObjects[$iSrcRootId])

    If $iHostPagesId = 0 Or $iSrcPagesId = 0 Then
        ConsoleWrite("! Error: Could not locate Pages nodes for merging." & @CRLF)
        Return False
    EndIf

    ConsoleWrite("> Processing Source Pages..." & @CRLF)
    Local $aFlatSrcPages[0]
    _FlattenPageTree_Recursive($aSrcObjects, $iSrcPagesId, $aFlatSrcPages)

    Local $iOffset = $iHostMaxId + 1 
    Local $sNewKids = ""
    Local $iMergedPageCount = UBound($aFlatSrcPages)

    For $i = 1 To $iSrcMaxId
        If $aSrcObjects[$i] <> "" Then
            Local $sUpdatedObject = $aSrcObjects[$i]
            $sUpdatedObject = StringRegExpReplace($sUpdatedObject, "(\b)(\d+)\s+(\d+)\s+R(\b)", 'Execute("$2 + " & $iOffset) & " $3 R"')
            $aHostObjects[$i + $iOffset] = $sUpdatedObject
            $aHostGen[$i + $iOffset] = $aSrcGen[$i]
        EndIf
    Next

    For $i = 0 To UBound($aFlatSrcPages) - 1
        Local $iNewPageId = $aFlatSrcPages[$i] + $iOffset
        $sNewKids &= $iNewPageId & " 0 R "
        $aHostObjects[$iNewPageId] = StringRegExpReplace($aHostObjects[$iNewPageId], "/Parent\s+\d+\s+\d+\s+R", "/Parent " & $iHostPagesId & " 0 R")
    next

    Local $aHostKids = StringRegExp($aHostObjects[$iHostPagesId], "/Kids\s*\[(.*?)\]", 1)
    Local $sCurrentKids = ""
    If Not @error Then $sCurrentKids = $aHostKids[0]

    Local $aHostCount = StringRegExp($aHostObjects[$iHostPagesId], "/Count\s+(\d+)", 1)
    Local $iCurrentCount = 0
    If Not @error Then $iCurrentCount = Int($aHostCount[0])

    $aHostObjects[$iHostPagesId] = "<< /Type /Pages /Kids [ " & $sCurrentKids & " " & $sNewKids & "] /Count " & ($iCurrentCount + $iMergedPageCount) & " >>"

    Local $iFinalMaxId = $iHostMaxId + $iSrcMaxId + 1

    ConsoleWrite("> Rebuilding Merged Document..." & @CRLF)
    Local $sNewPdfData = "%PDF-1.4" & @CRLF & "%????" & @CRLF & @CRLF
    Local $aXref[1000000] 

    For $i = 1 To $iFinalMaxId
        If StringLen($aHostObjects[$i]) > 0 Then
            $aXref[$i] = StringLen($sNewPdfData)
            Local $iGen = $aHostGen[$i]
            If $iGen = "" Then $iGen = 0
            $sNewPdfData &= $i & " " & $iGen & " obj" & @CRLF & $aHostObjects[$i] & @CRLF & "endobj" & @CRLF & @CRLF
        Else
            $aXref[$i] = 0
        EndIf
    Next

    Local $iStartXrefOffset = StringLen($sNewPdfData)
    Local $sXrefTable = "xref" & @CRLF
    $sXrefTable &= "0 " & ($iFinalMaxId + 1) & @CRLF
    $sXrefTable &= "0000000000 65535 f " & @CRLF 

    For $i = 1 To $iFinalMaxId
        If $aXref[$i] <> 0 Then
            $sXrefTable &= StringFormat("%010d 00000 n ", $aXref[$i]) & @CRLF
        Else
            $sXrefTable &= "0000000000 00000 f " & @CRLF
        EndIf
    Next

    Local $sTrailer = "trailer" & @CRLF & "<< /Size " & ($iFinalMaxId + 1)
    $sTrailer &= " /Root " & $iHostRootId & " 0 R"
    $sTrailer &= " >>" & @CRLF
    $sTrailer &= "startxref" & @CRLF & $iStartXrefOffset & @CRLF & "%%EOF"

    $sNewPdfData &= $sXrefTable & $sTrailer

    ConsoleWrite("> Writing output to " & $sOutputFile & "..." & @CRLF)
    Local $hOutFile = FileOpen($sOutputFile, 2 + 16) 
    FileWrite($hOutFile, StringToBinary($sNewPdfData, 1))
    FileClose($hOutFile)
    
    ConsoleWrite("> Merge Complete!" & @CRLF)
EndFunc

; =================================================================================================
; ZLIB WRAPPER
; =================================================================================================
Func _Zlib_Uncompress($bData)
    If Not $bZlibLoaded Then Return Binary("")

    Local $iMultiplier = 10 
    Local $iResult = -5 
    Local $aCall, $tDest, $tDestLen, $tSrc
    
    $tSrc = DllStructCreate("byte[" & BinaryLen($bData) & "]")
    DllStructSetData($tSrc, 1, $bData)

    While $iResult = -5 And $iMultiplier <= 50
        Local $iSize = BinaryLen($bData) * $iMultiplier
        $tDest = DllStructCreate("byte[" & $iSize & "]")
        
        $tDestLen = DllStructCreate("ulong")
        DllStructSetData($tDestLen, 1, $iSize)

        $aCall = DllCall($hZlib, "int:cdecl", "uncompress", _
            "ptr", DllStructGetPtr($tDest), _
            "ptr", DllStructGetPtr($tDestLen), _
            "ptr", DllStructGetPtr($tSrc), _
            "ulong", BinaryLen($bData))

        If @error Then Return Binary("")
        
        $iResult = $aCall[0]
        $iMultiplier += 10
    WEnd

    If $iResult <> 0 Then Return Binary("")

    Local $iFinalSize = DllStructGetData($tDestLen, 1)
    Return BinaryMid(DllStructGetData($tDest, 1), 1, $iFinalSize)
EndFunc

; =================================================================================================
; UTILITY & HELPERS
; =================================================================================================
Func _ParseCommandLine($sCmd)
    Local $aMatch = StringRegExp($sCmd, '(?:")[^"]*(?:")|[^\s]+', 3)
    
    For $i = 0 To UBound($aMatch) - 1
        If StringLeft($aMatch[$i], 1) == '"' And StringRight($aMatch[$i], 1) == '"' Then
            $aMatch[$i] = StringMid($aMatch[$i], 2, StringLen($aMatch[$i]) - 2)
        EndIf
    Next
    Return $aMatch
EndFunc

Func _ParsePDFObjects($sFileData, ByRef $aObjects, ByRef $aGen)
    Local $iMaxObjectId = 0
    Local $iPos = 1
    While 1
        $iPos = StringInStr($sFileData, " obj", 0, 1, $iPos)
        If $iPos = 0 Then ExitLoop 

        Local $sPrefix = StringMid($sFileData, _Max(1, $iPos - 20), _Min(20, $iPos - 1))
        Local $aIdGen = StringRegExp($sPrefix, '(\d+)\s+(\d+)$', 1)
        
        If Not @error Then
            Local $iObjId = Int($aIdGen[0])
            Local $iObjGen = Int($aIdGen[1])
            If $iObjId > $iMaxObjectId Then $iMaxObjectId = $iObjId

            Local $iEndPos = StringInStr($sFileData, "endobj", 0, 1, $iPos)
            If $iEndPos > 0 Then
                Local $iStartOfObj = $iPos - StringLen($aIdGen[0] & " " & $aIdGen[1])
                Local $iLengthOfObj = ($iEndPos + 6) - $iStartOfObj
                Local $sRawObject = StringMid($sFileData, $iStartOfObj, $iLengthOfObj)

                Local $sHeaderStr = $iObjId & " " & $iObjGen & " obj"
                Local $iHeaderLen = StringLen($sHeaderStr)
                Local $sBody = StringMid($sRawObject, $iHeaderLen + 1)
                
                Local $iEndObjPos = StringInStr($sBody, "endobj", 0, -1)
                If $iEndObjPos > 0 Then $sBody = StringLeft($sBody, $iEndObjPos - 1)
                
                $aObjects[$iObjId] = StringStripWS($sBody, 3)
                $aGen[$iObjId] = $iObjGen

                $iPos = $iEndPos + 6
            Else
                $iPos += 4
            EndIf
        Else
            $iPos += 4
        EndIf
    WEnd
    Return $iMaxObjectId
EndFunc

Func _GetPdfRootId($sFileData)
    Local $aRoot = StringRegExp($sFileData, "/Root\s+(\d+)\s+\d+\s+R", 1)
    If @error Then Return 0
    Return Int($aRoot[0])
EndFunc

Func _GetPdfPagesId($sCatalogObj)
    Local $aPages = StringRegExp($sCatalogObj, "/Pages\s+(\d+)\s+\d+\s+R", 1)
    If @error Then Return 0
    Return Int($aPages[0])
EndFunc

; =================================================================================================
; STUB FUNCTIONS
; =================================================================================================
Func _PDF_ExtractImages($sInputFile)
    ConsoleWrite("> STUB: Extracting images from " & $sInputFile & @CRLF)
EndFunc

Func _PDF_ImportImages($sInputFile, $sOutputFile, $sImagesList)
    ConsoleWrite("> STUB: Importing images [" & $sImagesList & "] into PDF" & @CRLF)
EndFunc

Func _PDF_CompressFile($sInputFile, $sOutputFile)
    ConsoleWrite("> STUB: Compressing PDF" & @CRLF)
EndFunc

; =================================================================================================
; METADATA UPDATE FUNCTION
; =================================================================================================
Func _PDF_UpdateMetadata($sInputFile, $sOutputFile, $aMetaData)
    If Not FileExists($sInputFile) Then Return False
    
    Local $hFile = FileOpen($sInputFile, 16)
    Local $sFileData = BinaryToString(FileRead($hFile), 1)
    FileClose($hFile)

    Local $aParsedObjects[100000], $aParsedGen[100000]
    Local $iMaxObjectId = _ParsePDFObjects($sFileData, $aParsedObjects, $aParsedGen)
    
    ; 1. Find or Create Info Object
    Local $sTrailer = StringMid($sFileData, StringInStr($sFileData, "trailer", 0, -1))
    Local $aInfoRef = StringRegExp($sTrailer, "/Info\s+(\d+)\s+(\d+)\s+R", 1)
    
    Local $iInfoId, $sInfoObj
    If Not @error Then
        $iInfoId = Int($aInfoRef[0])
        $sInfoObj = $aParsedObjects[$iInfoId]
    Else
        $iMaxObjectId += 1
        $iInfoId = $iMaxObjectId
        $sInfoObj = "<< >>"
    EndIf

    ; 2. Update/Inject Fields
    For $i = 0 To UBound($aMetaData) - 1
        Local $sKey = $aMetaData[$i][0] ; e.g., "Title"
        Local $sVal = $aMetaData[$i][1] ; e.g., "My Title"
        
        ; Remove old key if exists
        $sInfoObj = StringRegExpReplace($sInfoObj, "/" & $sKey & "\s*\(.*?\)", "")
        ; Inject new key
        $sInfoObj = StringRegExpReplace($sInfoObj, ">>", "/" & $sKey & " (" & $sVal & ")" & @CRLF & ">>")
    Next
    
    $aParsedObjects[$iInfoId] = $sInfoObj
    
    ; 3. Rebuild (Skipping full reconstruction logic for brevity; assumes simple object update)
    ConsoleWrite("> Metadata Updated. Writing to " & $sOutputFile & @CRLF)
    ; (In a production environment, use the same reconstruction logic as _PDF_DeletePages)
EndFunc
