#pragma compile(Console, true)
#include <File.au3>
#include <Array.au3>
#include <String.au3>
#include <Math.au3>

; =================================================================================================
; GLOBALS & CORE ARCHITECTURE
; =================================================================================================
Global $g_sPDFPath = ""
Global $g_sPDFVersion = "1.4"
Global $g_aObjects = []     ; Stores full raw binary blocks (e.g., "1 0 obj...endobj")
Global $g_aObjectIDs = []
Global $g_iObjectCount = 0
Global $g_iMaxObjID = 0

; === ROOT & PAGES LOCATOR ===
Global $g_iInfoObj = -1
Global $g_iRootObj   = -1
Global $g_iPagesObj  = -1
Global $g_aPageObjs  = [] 
Global $g_iPageCount = 0
Global $g_sTrailerID = ""   ; Preserves the unique document ID

; === ZLIB ===
Global $g_bZlibAvailable = False
Global $sZlibPath = @ScriptDir & "\zlib1.dll"
Global $bZlibLoaded = False
Global $hZlib = DllOpen($sZlibPath)
If $hZlib <> -1 Then $bZlibLoaded = True
$g_bZlibAvailable = $bZlibLoaded
	
; =================================================================================================
; RUNTIME OVERRIDE
; =================================================================================================
; Global $sSimulatedCmdLine = '"input.pdf" -d1-2'
 Global $sSimulatedCmdLine = '"input.pdf" -title"Final Report" -author"John Doe" -o"updated.pdf"'
;Global $sSimulatedCmdLine = '"input.pdf" -version"1.7" -pagesize"0 0 595 842" -o"out.pdf"'
;Global $sSimulatedCmdLine = '"input.pdf" -importpdf -o"outputfile.pdf"'
;Global $sSimulatedCmdLine = '"input.pdf" -e2-5 -o"f2.pdf"'
;Global $sSimulatedCmdLine = '"input.pdf" -decompress -o"filename.pdf"'
;Global $sSimulatedCmdLine = '"f2.pdf" -compress -o"compressed.pdf"'
; Global $sSimulatedCmdLine = '"input.pdf" -d1-2'
; Global $sSimulatedCmdLine = '"input.pdf" -importpdf -o"outputfile.pdf"'
; Global $sSimulatedCmdLine = '"input.pdf" -version"1.7" -pagesize"0 0 595 842" -o"out.pdf"'
Global $sSimulatedCmdLine = '"input.pdf" -title"Final Report" -author"Jane Doe" -subject"Q1 Financials" -o"updated.pdf"'
Global $sSimulatedCmdLine = '"t2_de_decoded_decoded.pdf" -extract"'
Global $sSimulatedCmdLine = '"t2_de_decoded_decoded.pdf" -decompress -o"filename.pdf"'
Global $sSimulatedCmdLine = '"t2_de_decoded_decoded.pdf" -compress -o"compressed.pdf"'
Global $sSimulatedCmdLine = '"t2_de_decoded_decoded.pdf" -d1-2 -o"deletedpage.pdf"' ;dont
Global $sSimulatedCmdLine = '"t2_de_decoded_decoded.pdf" -e2-5 -o"extractedpage.pdf"'
Global $sSimulatedCmdLine = ' -importimage""1.jpg,2.jpg,3.jpg"" -o"extractedpage.pdf"'

_Main($sSimulatedCmdLine)

; Cleanup
If $bZlibLoaded Then DllClose($hZlib)
Exit

; =================================================================================================
; MAIN ENTRY POINT & CLI ROUTING
; =================================================================================================
Func _Main($sCmdString)
    ConsoleWrite("--- Native AutoIt PDF Toolkit (V10e Enhanced) ---" & @LF)
    
    If Not $bZlibLoaded Then
        ConsoleWrite("! WARNING: zlib1.dll not found in script directory. Compression disabled." & @LF)
    EndIf

    Local $aArgs = _ParseCommandLine($sCmdString)
    If UBound($aArgs) < 1 Then Return ConsoleWrite("Error: No input file specified." & @LF)

    Local $sInputFile = $aArgs[0]
    Local $sOutputFile = "output.pdf"

    ; Extract output file parameter
    For $i = 1 To UBound($aArgs) - 1
        If StringLeft($aArgs[$i], 2) = "-o" Then
            $sOutputFile = StringReplace(StringTrimLeft($aArgs[$i], 2), '"', '')
        EndIf
    Next

    ; Collect metadata fields safely
    Local $aMeta[0]
    For $i = 1 To UBound($aArgs) - 1
        Local $sArg = $aArgs[$i]
        If StringLeft($sArg, 1) = "-" Then
            If StringRegExp($sArg, "^-(title|author|subject|keywords|producer|createddate|modifieddate|version|pagesize)") Then
                _ArrayAdd($aMeta, $sArg)
            EndIf
        EndIf
    Next

    ; Import PDF Logic
    Local $bIsImport = False
    For $i = 1 To UBound($aArgs) - 1
        If $aArgs[$i] = "-importpdf" Then $bIsImport = True
    Next

    If $bIsImport And FileExists($sOutputFile) Then
        If Not _PDF_Load($sOutputFile) Then Return ConsoleWrite("Error: Failed to load host PDF." & @LF)
        _PDF_ImportPDFs($sInputFile)
    Else
        If Not _PDF_Load($sInputFile) Then Return ConsoleWrite("Error: Failed to load PDF." & @LF)
    EndIf

    ; Route specific operational commands
    For $i = 1 To UBound($aArgs) - 1
        Local $sArg = $aArgs[$i]
        Select
            Case $sArg = "-decompress"
                ConsoleWrite("> Decompressing all streams..." & @LF)
                _PDF_DecompressAllStreams()
                
            Case $sArg = "-compress"
                ConsoleWrite("> Compressing all streams..." & @LF)
                _PDF_CompressAllStreams()
                
            Case StringLeft($sArg, 2) = "-d"
                Local $sDelPages = StringTrimLeft($sArg, 2)
                ConsoleWrite("> Deleting pages " & $sDelPages & "..." & @LF)
                _PDF_DeletePagesSimple($sDelPages)
                
            Case StringLeft($sArg, 2) = "-e"
                Local $sExtPages = StringTrimLeft($sArg, 2)
                ConsoleWrite("> Extracting pages " & $sExtPages & "..." & @LF)
                _PDF_ExtractPagesSimple($sExtPages)
                
            Case $sArg = "-extract"
                _PDF_ExtractImages($sInputFile)
                
            Case StringLeft($sArg, 12) = "-importimage"
                Local $sImages = StringReplace(StringTrimLeft($sArg, 12), '"', '')
                _PDF_ImportImages($sInputFile, $sOutputFile, $sImages)
        EndSelect
    Next

    ; Apply Metadata modifications
    If UBound($aMeta) > 0 Then _PDF_ApplyMetadataArray($aMeta)

    ; Save final build
    If _PDF_Save($sOutputFile) Then
        ConsoleWrite("> Successfully saved to " & $sOutputFile & @LF)
    Else
        ConsoleWrite("! Error: Failed to save file." & @LF)
    EndIf
EndFunc

; FIXED: Flawless command line parsing that keeps spaces inside embedded quotes intact
Func _ParseCommandLine($sCmd)
    Local $aMatch = StringRegExp($sCmd, '(?:[^\s"]|"[^"]*")+', 3)
    For $i = 0 To UBound($aMatch) - 1
        ; Strip outer quotes only if the ENTIRE argument is surrounded by them (e.g. "input.pdf")
        If StringLeft($aMatch[$i], 1) == '"' And StringRight($aMatch[$i], 1) == '"' Then
            $aMatch[$i] = StringMid($aMatch[$i], 2, StringLen($aMatch[$i]) - 2)
        EndIf
    Next
    Return $aMatch
EndFunc

; =================================================================================================
; PDF ENGINE: LOADING AND STRUCTURAL PARSING
; =================================================================================================
Func _PDF_Load($sPath)
    $g_sPDFPath = $sPath
    Local $bData = _PDF_ReadFile($sPath)
    If @error Then Return SetError(1,0,False)

    If Not _PDF_ParseObjects($bData) Then Return SetError(1,0,False)

    Local $sPDF = BinaryToString($bData, 1)
    
    ; Extract PDF Version
    Local $aVer = StringRegExp($sPDF, "%PDF-(\d\.\d)", 1)
    If Not @error Then $g_sPDFVersion = $aVer[0]
    
    $g_sTrailerID = _PDF_ExtractTrailerID($sPDF)
    
    _PDF_FindInfoObject($sPDF)
    _PDF_FindRoot()
    _PDF_FindPages()
    _PDF_BuildPageList()

    Return True
EndFunc

Func _PDF_ParseObjects($bData)
    Local $sPDF = BinaryToString($bData, 1)
    Local $aMatches = StringRegExp($sPDF, "(\d+)\s+0\s+obj", 3)
    If @error Then Return SetError(1,0,False)

    Local $iCount = UBound($aMatches)
    ReDim $g_aObjects[$iCount]
    ReDim $g_aObjectIDs[$iCount]

    Local $iPos = 1
    $g_iMaxObjID = 0

    For $i = 0 To $iCount - 1
        Local $iID = Int($aMatches[$i])
        $g_aObjectIDs[$i] = $iID
        If $iID > $g_iMaxObjID Then $g_iMaxObjID = $iID
        
        ; Extract FULL binary block exactly
        $g_aObjects[$i] = _PDF_ExtractObjectFull($bData, $sPDF, $aMatches[$i], $iPos)
    Next

    $g_iObjectCount = $iCount
    Return True
EndFunc

Func _PDF_ExtractObjectFull($bData, ByRef $sPDF, $iObj, ByRef $iPos)
    Local $sHeader = $iObj & " 0 obj"
    Local $iStart = StringInStr($sPDF, $sHeader, 0, 1, $iPos)
    If $iStart = 0 Then Return Binary("")

    Local $iSearch = $iStart
    Local $iEndObjIdx = 0
    While 1
        $iEndObjIdx = StringInStr($sPDF, "endobj", 0, 1, $iSearch)
        If $iEndObjIdx = 0 Then Return Binary("")
        
        Local $iStream = StringInStr($sPDF, "stream", 0, 1, $iStart)
        If $iStream > 0 And $iStream < $iEndObjIdx Then
            Local $iEndStream = StringInStr($sPDF, "endstream", 0, 1, $iStream)
            If $iEndStream > 0 And $iEndStream > $iEndObjIdx Then
                $iSearch = $iEndStream + 9 
                ContinueLoop
            EndIf
        EndIf
        ExitLoop
    WEnd

    Local $iByteLen = ($iEndObjIdx + 6) - $iStart
    $iPos = $iEndObjIdx + 6
    Return BinaryMid($bData, $iStart, $iByteLen)
EndFunc

Func _PDF_ReadFile($sPath)
    If Not FileExists($sPath) Then Return SetError(1,0,"")
    Local $h = FileOpen($sPath, 16)
    Local $b = FileRead($h)
    FileClose($h)
    Return $b
EndFunc

Func _PDF_WriteFile($sPath, $bData)
    Local $h = FileOpen($sPath, 18) ; Binary overwrite
    If $h = -1 Then Return SetError(1,0,False)
    FileWrite($h, $bData)
    FileClose($h)
    Return True
EndFunc

; =================================================================================================
; OBJECT MANIPULATION WRAPPERS
; =================================================================================================
Func _PDF_AddObject($bObj)
    $g_iMaxObjID += 1
    ReDim $g_aObjects[$g_iObjectCount + 1]
    ReDim $g_aObjectIDs[$g_iObjectCount + 1]
    $g_aObjectIDs[$g_iObjectCount] = $g_iMaxObjID
    $g_aObjects[$g_iObjectCount] = $bObj
    $g_iObjectCount += 1
    Return $g_iMaxObjID
EndFunc

Func _PDF_GetObjectByID($iID)
    For $i = 0 To $g_iObjectCount - 1
        If $g_aObjectIDs[$i] == $iID Then Return $g_aObjects[$i]
    Next
    Return SetError(1,0,Binary(""))
EndFunc

Func _PDF_SetObjectByID($iID, $bNewObj)
    For $i = 0 To $g_iObjectCount - 1
        If $g_aObjectIDs[$i] == $iID Then
            $g_aObjects[$i] = $bNewObj
            Return True
        EndIf
    Next
    Return False
EndFunc

Func _PDF_ObjectIsRef($sObj)
    Return StringRegExp($sObj, "^\s*\d+\s+\d+\s+R") = 1
EndFunc

Func _PDF_GetDict($sObj)
    Local $iStream = StringInStr($sObj, "stream")
    Local $sSearch = $sObj
    If $iStream > 0 Then $sSearch = StringLeft($sObj, $iStream - 1)
    Local $a = StringRegExp($sSearch, "(?s)<<(.*?)>>", 1)
    If @error Then Return ""
    Return "<<" & $a[0] & ">>"
EndFunc

Func _PDF_DictGet($sDict, $sKey)
    Local $a = StringRegExp($sDict, "/" & $sKey & "\s+(\/?\S+)", 1)
    If @error Then Return ""
    Return $a[0]
EndFunc

Func _PDF_GetArray($sObj)
    Local $a = StringRegExp($sObj, "\[(.*?)\]", 1)
    If @error Then Return ""
    Return "[" & $a[0] & "]"
EndFunc

Func _PDF_ArrayToList($sArray)
    Local $s = StringTrimLeft(StringTrimRight($sArray, 1), 1)
    Local $a = StringRegExp($s, "(\S+)", 3)
    If @error Then Return []
    Return $a
EndFunc

; =================================================================================================
; LOCATORS & STRUCTURE TRAVERSAL
; =================================================================================================
Func _PDF_FindRoot()
    For $i = 0 To $g_iObjectCount - 1
        Local $sDict = _PDF_GetDict(BinaryToString($g_aObjects[$i], 1))
        If StringRegExp($sDict, "/Type\s*/Catalog") Then
            $g_iRootObj = $g_aObjectIDs[$i]
            Return $g_iRootObj
        EndIf
    Next
    Return SetError(1,0,-1)
EndFunc

Func _PDF_FindPages()
    If $g_iRootObj = -1 Then Return SetError(1,0,-1)
    Local $sRootDict = _PDF_GetDict(BinaryToString(_PDF_GetObjectByID($g_iRootObj), 1))
    Local $sPagesRef = _PDF_DictGet($sRootDict, "Pages")
    
    Local $a = StringRegExp($sPagesRef, "(\d+)\s+0\s+R", 1)
    If Not @error Then
        $g_iPagesObj = Int($a[0])
        Return $g_iPagesObj
    EndIf
    Return SetError(1,0,-1)
EndFunc

Func _PDF_IsPageObj($bObj)
    Return StringRegExp(_PDF_GetDict(BinaryToString($bObj, 1)), "/Type\s*/Page\b") > 0
EndFunc

Func _PDF_GetKidsRefs($bPagesObj)
    Local $sKidsArray = _PDF_GetArray(_PDF_GetDict(BinaryToString($bPagesObj, 1)))
    If $sKidsArray = "" Then Return []
    Local $aTokens = _PDF_ArrayToList($sKidsArray)
    Local $aRefs[0]
    For $i = 0 To UBound($aTokens) - 1
        If _PDF_ObjectIsRef($aTokens[$i]) Then
            ReDim $aRefs[UBound($aRefs) + 1]
            $aRefs[UBound($aRefs) - 1] = $aTokens[$i]
        EndIf
    Next
    Return $aRefs
EndFunc

Func _PDF_BuildPageList()
    If $g_iPagesObj = -1 Then Return SetError(1,0,False)
    Dim $g_aPageObjs[0]
    $g_iPageCount = 0
    _PDF_WalkPagesNode($g_iPagesObj)
    Return True
EndFunc

Func _PDF_WalkPagesNode($iPagesObjID)
    Local $aKids = _PDF_GetKidsRefs(_PDF_GetObjectByID($iPagesObjID))
    For $i = 0 To UBound($aKids) - 1
        Local $aMatch = StringRegExp($aKids[$i], "(\d+)\s+0\s+R", 1)
        If @error Then ContinueLoop
        Local $iChildID = Int($aMatch[0])
        Local $bChild = _PDF_GetObjectByID($iChildID)
        If BinaryLen($bChild) = 0 Then ContinueLoop

        If _PDF_IsPageObj($bChild) Then
            ReDim $g_aPageObjs[$g_iPageCount + 1]
            $g_aPageObjs[$g_iPageCount] = $iChildID
            $g_iPageCount += 1
        Else
            _PDF_WalkPagesNode($iChildID)
        EndIf
    Next
EndFunc

; =================================================================================================
; PAGE EXTRACTION & DELETION
; =================================================================================================
Func _PDF_GetPageObjectID($iPage)
    If $iPage < 0 Or $iPage >= $g_iPageCount Then Return SetError(1,0,-1)
    Return $g_aPageObjs[$iPage]
EndFunc

Func _PDF_DeletePage($iPage)
    If $iPage < 0 Or $iPage >= $g_iPageCount Then Return SetError(1,0,False)
    ; Remove index from internal array
    For $i = $iPage To $g_iPageCount - 2
        $g_aPageObjs[$i] = $g_aPageObjs[$i + 1]
    Next
    ReDim $g_aPageObjs[$g_iPageCount - 1]
    $g_iPageCount -= 1
    _PDF_RebuildPagesTree()
    Return True
EndFunc

Func _PDF_DeletePagesSimple($sDelPages)
    Local $aPages = StringSplit($sDelPages, "-")
    Local $iStart = 1, $iEnd = 1
    
    If $aPages[0] = 1 Then
        $iStart = Int($sDelPages)
        $iEnd = Int($sDelPages)
    ElseIf $aPages[0] = 2 Then
        $iStart = Int($aPages[1])
        $iEnd = Int($aPages[2])
    EndIf
    
    ; Delete from end to start to preserve indices
    For $i = $g_iPageCount - 1 To 0 Step -1
        Local $iPageNum = $i + 1
        If $iPageNum >= $iStart And $iPageNum <= $iEnd Then
            _PDF_DeletePage($i)
        EndIf
    Next
EndFunc

Func _PDF_ExtractPagesSimple($sExtractPages)
    Local $aPages = StringSplit($sExtractPages, "-")
    Local $iStart = 1, $iEnd = 1
    
    If $aPages[0] = 1 Then
        $iStart = Int($sExtractPages)
        $iEnd = Int($sExtractPages)
    ElseIf $aPages[0] = 2 Then
        $iStart = Int($aPages[1])
        $iEnd = Int($aPages[2])
    EndIf
    
    ; Delete pages outside the target range
    For $i = $g_iPageCount - 1 To 0 Step -1
        Local $iPageNum = $i + 1
        If $iPageNum < $iStart Or $iPageNum > $iEnd Then
            _PDF_DeletePage($i)
        EndIf
    Next
EndFunc

Func _PDF_RebuildPagesTree()
    If $g_iPagesObj = -1 Then Return False
    Local $sObj = BinaryToString(_PDF_GetObjectByID($g_iPagesObj), 1)
    Local $sDict = _PDF_GetDict($sObj)
    
    Local $sKids = "[ "
    For $i = 0 To $g_iPageCount - 1
        $sKids &= _PDF_GetPageObjectID($i) & " 0 R "
    Next
    $sKids &= "]"
    
    Local $sNewDict = $sDict
    $sNewDict = StringRegExpReplace($sNewDict, "/Kids\s*\[.*?\]", "/Kids " & $sKids)
    $sNewDict = StringRegExpReplace($sNewDict, "/Count\s+\d+", "/Count " & $g_iPageCount)
    
    $sObj = StringReplace($sObj, $sDict, $sNewDict)
    _PDF_SetObjectByID($g_iPagesObj, StringToBinary($sObj, 1))
    Return True
EndFunc

; =================================================================================================
; IMPORT / MERGE PDFs
; =================================================================================================
Func _PDF_ImportPDFs($sSourcePath)
    ConsoleWrite("> Merging PDF: " & $sSourcePath & @LF)
    If Not FileExists($sSourcePath) Then Return False
    
    Local $bSrcData = _PDF_ReadFile($sSourcePath)
    If @error Then Return False
    Local $sSrcPDF = BinaryToString($bSrcData, 1)
    
    Local $aMatches = StringRegExp($sSrcPDF, "(\d+)\s+0\s+obj", 3)
    If @error Then Return False
    
    Local $iSrcCount = UBound($aMatches)
    Local $aSrcObjects[$iSrcCount]
    Local $aSrcIDs[$iSrcCount]
    
    Local $iPos = 1
    For $i = 0 To $iSrcCount - 1
        Local $iID = Int($aMatches[$i])
        $aSrcIDs[$i] = $iID
        $aSrcObjects[$i] = _PDF_ExtractObjectFull($bSrcData, $sSrcPDF, $aMatches[$i], $iPos)
    Next
    
    ; Find Source Root & Pages 
    Local $iSrcRoot = -1, $iSrcPages = -1
    For $i = 0 To $iSrcCount - 1
        Local $sDict = _PDF_GetDict(BinaryToString($aSrcObjects[$i], 1))
        If StringRegExp($sDict, "/Type\s*/Catalog") Then
            $iSrcRoot = $aSrcIDs[$i]
            Local $aP = StringRegExp(_PDF_DictGet($sDict, "Pages"), "(\d+)\s+0\s+R", 1)
            If Not @error Then $iSrcPages = Int($aP[0])
            ExitLoop
        EndIf
    Next
    If $iSrcPages = -1 Then Return False
    
    ; Extract Source Page Target IDs
    Local $aSrcPageIDs[0]
    _PDF_WalkSourcePagesNode($iSrcPages, $aSrcObjects, $aSrcIDs, $aSrcPageIDs)
    
    Local $iOffset = $g_iMaxObjID
    For $i = 0 To $iSrcCount - 1
        If BinaryLen($aSrcObjects[$i]) > 0 Then
            Local $sObj = BinaryToString($aSrcObjects[$i], 1)
            
            ; Shift internal Object References to prevent collisions
            $sObj = StringRegExpReplace($sObj, "(\b)(\d+)\s+0\s+R(\b)", 'Execute("$2 + ' & $iOffset & '") & " 0 R"')
            ; Shift header object IDs
            $sObj = StringRegExpReplace($sObj, "^(\d+)(\s+0\s+obj)", 'Execute("$1 + ' & $iOffset & '") & "$2"')
            
            ; Map the merged Pages back to the new Host Pages root node
            Local $bIsPage = False
            For $p = 0 To UBound($aSrcPageIDs) - 1
                If $aSrcIDs[$i] = $aSrcPageIDs[$p] Then
                    $bIsPage = True
                    ExitLoop
                EndIf
            Next
            If $bIsPage Then
                $sObj = StringRegExpReplace($sObj, "/Parent\s+\d+\s+0\s+R", "/Parent " & $g_iPagesObj & " 0 R")
            EndIf
            
            _PDF_AddObject(StringToBinary($sObj, 1))
        EndIf
    Next
    
    For $i = 0 To UBound($aSrcPageIDs) - 1
        ReDim $g_aPageObjs[$g_iPageCount + 1]
        $g_aPageObjs[$g_iPageCount] = $aSrcPageIDs[$i] + $iOffset
        $g_iPageCount += 1
    Next
    
    _PDF_RebuildPagesTree()
    Return True
EndFunc

Func _PDF_WalkSourcePagesNode($iNodeID, ByRef $aSrcObjects, ByRef $aSrcIDs, ByRef $aSrcPageIDs)
    Local $sObj = ""
    For $i = 0 To UBound($aSrcIDs) - 1
        If $aSrcIDs[$i] = $iNodeID Then
            $sObj = BinaryToString($aSrcObjects[$i], 1)
            ExitLoop
        EndIf
    Next
    If $sObj = "" Then Return
    
    Local $sDict = _PDF_GetDict($sObj)
    If StringRegExp($sDict, "/Type\s*/Page\b") Then
        _ArrayAdd($aSrcPageIDs, $iNodeID)
    ElseIf StringRegExp($sDict, "/Type\s*/Pages\b") Or StringInStr($sDict, "/Kids") Then
        Local $aTokens = _PDF_ArrayToList(_PDF_GetArray($sDict))
        For $i = 0 To UBound($aTokens) - 1
            If _PDF_ObjectIsRef($aTokens[$i]) Then
                Local $aMatch = StringRegExp($aTokens[$i], "(\d+)\s+0\s+R", 1)
                If Not @error Then _PDF_WalkSourcePagesNode(Int($aMatch[0]), $aSrcObjects, $aSrcIDs, $aSrcPageIDs)
            EndIf
        Next
    EndIf
EndFunc

; =================================================================================================
; ZLIB COMPRESSION / DECOMPRESSION MODULE
; =================================================================================================
Func _PDF_DecompressAllStreams()
    If Not $g_bZlibAvailable Then Return False
    
    For $i = 0 To $g_iObjectCount - 1
        Local $bObj = $g_aObjects[$i]
        Local $sObjASCII = BinaryToString($bObj, 1)
        
        Local $iStream = StringInStr($sObjASCII, "stream")
        Local $iEndStream = StringInStr($sObjASCII, "endstream", 0, -1)
        If $iStream > 0 And $iEndStream > 0 Then
            Local $sDict = _PDF_GetDict($sObjASCII)
            If StringInStr($sDict, "/FlateDecode") = 0 And StringInStr($sDict, "/Fl") = 0 Then ContinueLoop

            Local $iDataStart = $iStream + 6
            If StringMid($sObjASCII, $iDataStart, 2) == @CRLF Then
                $iDataStart += 2
            ElseIf StringMid($sObjASCII, $iDataStart, 1) == @LF Or StringMid($sObjASCII, $iDataStart, 1) == @CR Then
                $iDataStart += 1
            EndIf
            
            Local $iDataLen = $iEndStream - $iDataStart
            Local $bData = BinaryMid($bObj, $iDataStart, $iDataLen)
            
            Local $bUncompressed = _Zlib_Uncompress($bData)
            If BinaryLen($bUncompressed) > 0 Then
                Local $sNewDict = StringRegExpReplace($sDict, "/Filter\s*/[A-Za-z0-9_]+", "")
                $sNewDict = StringRegExpReplace($sNewDict, "/Filter\s*\[.*?\]", "")
                $sNewDict = StringRegExpReplace($sNewDict, "/Length\s+\d+", "")
                $sNewDict = StringRegExpReplace($sNewDict, "/Length\s+\d+\s+0\s+R", "")
                $sNewDict = StringTrimRight($sNewDict, 2) & " /Length " & BinaryLen($bUncompressed) & " >>"
                
                Local $sHeader = StringLeft($sObjASCII, StringInStr($sObjASCII, "obj") + 2)
                Local $bNewObj = StringToBinary($sHeader & @LF & $sNewDict & @LF & "stream" & @LF, 1)
                $bNewObj &= $bUncompressed
                $bNewObj &= StringToBinary(@LF & "endstream" & @LF & "endobj", 1)
                
                _PDF_SetObjectByID($g_aObjectIDs[$i], $bNewObj)
            EndIf
        EndIf
    Next
EndFunc

Func _PDF_CompressAllStreams()
    If Not $g_bZlibAvailable Then Return False
    
    For $i = 0 To $g_iObjectCount - 1
        Local $bObj = $g_aObjects[$i]
        Local $sObjASCII = BinaryToString($bObj, 1)
        
        Local $iStream = StringInStr($sObjASCII, "stream")
        Local $iEndStream = StringInStr($sObjASCII, "endstream", 0, -1)
        If $iStream > 0 And $iEndStream > 0 Then
            Local $sDict = _PDF_GetDict($sObjASCII)
            If StringInStr($sDict, "/Filter") > 0 Then ContinueLoop

            Local $iDataStart = $iStream + 6
            If StringMid($sObjASCII, $iDataStart, 2) == @CRLF Then
                $iDataStart += 2
            ElseIf StringMid($sObjASCII, $iDataStart, 1) == @LF Or StringMid($sObjASCII, $iDataStart, 1) == @CR Then
                $iDataStart += 1
            EndIf
            
            Local $iDataLen = $iEndStream - $iDataStart
            Local $bData = BinaryMid($bObj, $iDataStart, $iDataLen)
            
            Local $bCompressed = _Zlib_Compress($bData)
            If BinaryLen($bCompressed) > 0 Then
                Local $sNewDict = StringRegExpReplace($sDict, "/Length\s+\d+", "")
                $sNewDict = StringRegExpReplace($sNewDict, "/Length\s+\d+\s+0\s+R", "")
                $sNewDict = StringTrimRight($sNewDict, 2) & " /Filter /FlateDecode /Length " & BinaryLen($bCompressed) & " >>"
                
                Local $sHeader = StringLeft($sObjASCII, StringInStr($sObjASCII, "obj") + 2)
                Local $bNewObj = StringToBinary($sHeader & @LF & $sNewDict & @LF & "stream" & @LF, 1)
                $bNewObj &= $bCompressed
                $bNewObj &= StringToBinary(@LF & "endstream" & @LF & "endobj", 1)
                
                _PDF_SetObjectByID($g_aObjectIDs[$i], $bNewObj)
            EndIf
        EndIf
    Next
EndFunc

Func _Zlib_Uncompress($bData)
    If Not $g_bZlibAvailable Then Return Binary("")
    Local $iMultiplier = 10, $iResult = -5
    Local $aCall, $tDest, $tDestLen, $tSrc
    $tSrc = DllStructCreate("byte[" & BinaryLen($bData) & "]")
    DllStructSetData($tSrc, 1, $bData)

    While $iResult = -5 And $iMultiplier <= 50
        Local $iSize = BinaryLen($bData) * $iMultiplier
        $tDest = DllStructCreate("byte[" & $iSize & "]")
        $tDestLen = DllStructCreate("ulong")
        DllStructSetData($tDestLen, 1, $iSize)

        $aCall = DllCall($hZlib, "int:cdecl", "uncompress", _
            "ptr", DllStructGetPtr($tDest), "ptr", DllStructGetPtr($tDestLen), _
            "ptr", DllStructGetPtr($tSrc), "ulong", BinaryLen($bData))

        If @error Then Return Binary("")
        $iResult = $aCall[0]
        $iMultiplier += 10
    WEnd

    If $iResult <> 0 Then Return Binary("")
    Local $iFinalSize = DllStructGetData($tDestLen, 1)
    Return BinaryMid(DllStructGetData($tDest, 1), 1, $iFinalSize)
EndFunc

Func _Zlib_Compress($bData)
    If Not $g_bZlibAvailable Then Return Binary("")
    Local $aBound = DllCall($hZlib, "int:cdecl", "compressBound", "ulong", BinaryLen($bData))
    If @error Then Return Binary("")
    
    Local $iMaxSize = $aBound[0]
    Local $tSrc = DllStructCreate("byte[" & BinaryLen($bData) & "]")
    DllStructSetData($tSrc, 1, $bData)
    
    Local $tDest = DllStructCreate("byte[" & $iMaxSize & "]")
    Local $tDestLen = DllStructCreate("ulong")
    DllStructSetData($tDestLen, 1, $iMaxSize)
    
    Local $aComp = DllCall($hZlib, "int:cdecl", "compress", _
        "ptr", DllStructGetPtr($tDest), "ptr", DllStructGetPtr($tDestLen), _
        "ptr", DllStructGetPtr($tSrc), "ulong", BinaryLen($bData))

    If @error Or $aComp[0] <> 0 Then Return Binary("")
    Local $iFinalSize = DllStructGetData($tDestLen, 1)
    Return BinaryMid(DllStructGetData($tDest, 1), 1, $iFinalSize)
EndFunc

; =================================================================================================
; METADATA HANDLERS (FULLY FIXED)
; =================================================================================================
Func _PDF_ApplyMetadataArray(ByRef $aMeta)
    If $g_iInfoObj = -1 Then _PDF_CreateInfoObject()

    For $i = 0 To UBound($aMeta) - 1
        Local $sArg = $aMeta[$i]
        
        ; Extract the Key Name (e.g. from -title"Hello" -> Title)
        Local $aKey = StringRegExp($sArg, "^-([a-zA-Z]+)", 1)
        If @error Then ContinueLoop
        Local $sKey = StringUpper(StringLeft($aKey[0], 1)) & StringMid($aKey[0], 2)
        
        ; Extract the Value safely
        Local $sValue = StringRegExpReplace($sArg, "^-[a-zA-Z]+", "")
        ; Clean up surrounding quotes from the command line argument if they exist
        If StringLeft($sValue, 1) == '"' And StringRight($sValue, 1) == '"' Then
            $sValue = StringMid($sValue, 2, StringLen($sValue) - 2)
        EndIf

        ; Version Header Hook
        If $sKey = "Version" Then
            $g_sPDFVersion = $sValue
            ContinueLoop
        EndIf
        
        ; Page Size Hook
        If $sKey = "Pagesize" Then
            _PDF_SetGlobalPageSize($sValue)
            ContinueLoop
        EndIf
        
        ; Standard Dictionary Properties
        If $sKey = "Createddate" Then
            _PDF_SetInfoField("CreationDate", "D:" & $sValue)
        ElseIf $sKey = "Modifieddate" Then
            _PDF_SetInfoField("ModDate", "D:" & $sValue)
        Else
            _PDF_SetInfoField($sKey, $sValue)
        EndIf
    Next
EndFunc

; FIXED: Safely inserts page size exactly inside the first bracket to avoid nested dictionary truncation
Func _PDF_SetGlobalPageSize($sSizeStr)
    For $i = 0 To $g_iPageCount - 1
        Local $iPageID = $g_aPageObjs[$i]
        Local $sObjASCII = BinaryToString(_PDF_GetObjectByID($iPageID), 1)
        
        If StringInStr($sObjASCII, "/MediaBox") Then
            ; Cleanly replace existing array
            $sObjASCII = StringRegExpReplace($sObjASCII, "/MediaBox\s*\[[^\]]*\]", "/MediaBox [" & $sSizeStr & "]")
        Else
            ; Surgically insert right after the opening dictionary bracket
            Local $iFirstBracket = StringInStr($sObjASCII, "<<")
            If $iFirstBracket > 0 Then
                Local $sLeft = StringLeft($sObjASCII, $iFirstBracket + 1)
                Local $sRight = StringMid($sObjASCII, $iFirstBracket + 2)
                $sObjASCII = $sLeft & " /MediaBox [" & $sSizeStr & "] " & $sRight
            EndIf
        EndIf
        
        _PDF_SetObjectByID($iPageID, StringToBinary($sObjASCII, 1))
    Next
EndFunc

Func _PDF_ExtractTrailerID($sPDF)
    Local $a = StringRegExp($sPDF, "/ID\s*(\[.*?\])", 1)
    If @error Then Return ""
    Return "/ID " & $a[0]
EndFunc

Func _PDF_FindInfoObject($sPDF)
    Local $a = StringRegExp($sPDF, "/Info\s+(\d+)\s+0\s+R", 1)
    If @error Then Return -1
    $g_iInfoObj = Int($a[0])
    Return $g_iInfoObj
EndFunc

; FIXED: Replaced unsafe dictionary replacements with clean string insertion/regex.
Func _PDF_SetInfoField($sKey, $sValue)
    If $g_iInfoObj = -1 Then Return False
    Local $sObj = BinaryToString(_PDF_GetObjectByID($g_iInfoObj), 1)
    
    ; Replace existing value (works for both standard '(text)' and hex '<text>' formats)
    If StringRegExp($sObj, "/" & $sKey & "\s*[\(<]") Then
        $sObj = StringRegExpReplace($sObj, "/" & $sKey & "\s*[\(<][^\)>]*[\)>]", "/" & $sKey & " (" & $sValue & ")")
    Else
        ; Append new Key safely inside the opening bracket
        Local $iFirstBracket = StringInStr($sObj, "<<")
        If $iFirstBracket > 0 Then
            Local $sLeft = StringLeft($sObj, $iFirstBracket + 1)
            Local $sRight = StringMid($sObj, $iFirstBracket + 2)
            $sObj = $sLeft & " /" & $sKey & " (" & $sValue & ") " & $sRight
        EndIf
    EndIf
    
    _PDF_SetObjectByID($g_iInfoObj, StringToBinary($sObj, 1))
    Return True
EndFunc

Func _PDF_CreateInfoObject()
    Local $iNewID = $g_iMaxObjID + 1
    Local $sObj = $iNewID & " 0 obj" & @LF & "<< /Producer (AutoIt PDF Engine) >>" & @LF & "endobj"
    _PDF_AddObject(StringToBinary($sObj, 1))
    $g_iInfoObj = $iNewID
    Return $iNewID
EndFunc

; =================================================================================================
; FILE ASSEMBLY (LF COMPLIANT PDF WRITER)
; =================================================================================================
Func _PDF_BuildBody()
    Local $bBody = Binary("")
    Local $aOffsets[$g_iObjectCount]

    Local $iPos = 0
    For $i = 0 To $g_iObjectCount - 1
        $aOffsets[$i] = $iPos
        Local $bBlock = $g_aObjects[$i] & StringToBinary(@LF, 1)
        
        $bBody &= $bBlock
        $iPos += BinaryLen($bBlock) 
    Next

    Local $aResult[2] = [$bBody, $aOffsets]
    Return $aResult
EndFunc

Func _PDF_BuildXref($aOffsets, $iHeaderLen)
    Local $sXref = "xref" & @LF
    $sXref &= "0 " & ($g_iMaxObjID + 1) & @LF
    
    Local $aIDOffsets[$g_iMaxObjID + 1]
    For $i = 0 To $g_iMaxObjID
        $aIDOffsets[$i] = -1
    Next

    For $i = 0 To $g_iObjectCount - 1
        $aIDOffsets[$g_aObjectIDs[$i]] = $aOffsets[$i] + $iHeaderLen
    Next

    For $i = 0 To $g_iMaxObjID
        If $i = 0 Or $aIDOffsets[$i] = -1 Then
            $sXref &= "0000000000 65535 f " & @LF 
        Else
            $sXref &= StringFormat("%010d 00000 n ", $aIDOffsets[$i]) & @LF
        EndIf
    Next
    Return $sXref
EndFunc

Func _PDF_BuildTrailer()
    Local $s = "trailer" & @LF
    $s &= "<<" & @LF
    $s &= "/Size " & ($g_iMaxObjID + 1) & @LF
    $s &= "/Root " & $g_iRootObj & " 0 R" & @LF
    If $g_iInfoObj <> -1 Then $s &= "/Info " & $g_iInfoObj & " 0 R" & @LF
    If $g_sTrailerID <> "" Then $s &= $g_sTrailerID & @LF
    $s &= ">>" & @LF
    Return $s
EndFunc

Func _PDF_Save($sOutPath)
    ; Ensures the header adheres strictly to Version metadata request
    Local $bHeader = StringToBinary("%PDF-" & $g_sPDFVersion & @LF & "%âãÏÓ" & @LF, 1)
    Local $iHeaderLen = BinaryLen($bHeader)

    Local $aResult  = _PDF_BuildBody()
    Local $bBody    = $aResult[0]
    Local $aOffsets = $aResult[1]

    Local $bXref    = StringToBinary(_PDF_BuildXref($aOffsets, $iHeaderLen), 1)
    Local $bTrailer = StringToBinary(_PDF_BuildTrailer(), 1)
    Local $iStartXref = $iHeaderLen + BinaryLen($bBody)

    Local $bFinal = $bHeader
    $bFinal &= $bBody
    $bFinal &= $bXref
    $bFinal &= $bTrailer 
    $bFinal &= StringToBinary("startxref" & @LF & $iStartXref & @LF & "%%EOF" & @LF, 1)

    Return _PDF_WriteFile($sOutPath, $bFinal)
EndFunc

; =================================================================================================
; STUB FUNCTIONS
; =================================================================================================
Func _PDF_ExtractImages($sInputFile)
    ConsoleWrite("> STUB: Extracting images from " & $sInputFile & @LF)
EndFunc

Func _PDF_ImportImages($sInputFile, $sOutputFile, $sImagesList)
    ConsoleWrite("> STUB: Importing images [" & $sImagesList & "] into PDF" & @LF)
EndFunc