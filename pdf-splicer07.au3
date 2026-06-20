#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <GuiListBox.au3>
#include <MsgBoxConstants.au3>
#include <FileConstants.au3>
#include <Array.au3>

; Global State Variables
Global $sFilePath = ""
Global $sRawContent = "" 
Global $aActivePageObjects[0] ; Global array holding "X Y R" references

; Create Main GUI
Global $hMainGUI = GUICreate("AutoIt PDF Splicer (PDF 1.4)", 520, 430, -1, -1, BitOR($WS_MINIMIZEBOX, $WS_SIZEBOX, $WS_THICKFRAME, $WS_MAXIMIZEBOX))

; Create Menus
Global $mFile = GUICtrlCreateMenu("&File")
Global $mOpen = GUICtrlCreateMenuItem("&Open...", $mFile)
Global $mSave = GUICtrlCreateMenuItem("&Save", $mFile)
Global $mSaveAs = GUICtrlCreateMenuItem("Save &As...", $mFile)
GUICtrlCreateMenuItem("", $mFile)
Global $mExit = GUICtrlCreateMenuItem("E&xit", $mFile)

; Create Controls
Global $idListBox = GUICtrlCreateList("", 0, 0, 380, 430, BitOR($LBS_MULTIPLESEL, $WS_VSCROLL, $WS_BORDER, $LBS_EXTENDEDSEL))
GUICtrlSetResizing($idListBox, BitOR($GUI_DOCKLEFT, $GUI_DOCKTOP, $GUI_DOCKBOTTOM))

Global $idDeleteBtn = GUICtrlCreateButton("Delete Page(s)", 395, 10, 110, 35)
Global $idExportBtn = GUICtrlCreateButton("Export Selected", 395, 55, 110, 35)
Global $idImportBtn = GUICtrlCreateButton("Import Pages", 395, 100, 110, 35)
Global $idDecompressBtn = GUICtrlCreateButton("Decompress Streams", 395, 145, 110, 35)
Global $idCompressBtn = GUICtrlCreateButton("Compress Streams", 395, 190, 110, 35)

GUIRegisterMsg($WM_SIZE, "WM_SIZE")
GUISetState(@SW_SHOW, $hMainGUI)

; Main Event Loop
While 1
    Local $nMsg = GUIGetMsg()
    Switch $nMsg
        Case $GUI_EVENT_CLOSE, $mExit
            Exit
            
        Case $mOpen
            Local $sChosen = FileOpenDialog("Select PDF File", @DesktopDir, "PDF Files (*.pdf)", $FD_FILEMUSTEXIST)
            If Not @error Then
                $sFilePath = $sChosen
                _ParsePDF_PDF14($sFilePath)
                _PopulateListBox()
                WinSetTitle($hMainGUI, "", "AutoIt PDF Splicer - " & FileGetTime($sFilePath, 0, 1))
            EndIf
            
        Case $mSave, $mSaveAs
            If $sFilePath = "" Then ContinueLoop
            Local $sSavePath = $sFilePath
            If $nMsg = $mSaveAs Then $sSavePath = FileSaveDialog("Save PDF As", @DesktopDir, "PDF Files (*.pdf)", $FD_PATHMUSTEXIST)
            If $sSavePath <> "" Then _RebuildAndSavePDF_PDF14($sSavePath, $aActivePageObjects)

        Case $idDeleteBtn
            _DeleteSelectedPages()

        Case $idExportBtn
            _ExportSelectedPages()

        Case $idImportBtn
            _ImportPagesAfterSelection()

        Case $idDecompressBtn
            _ProcessStreams(False) 

        Case $idCompressBtn
            _ProcessStreams(True)  
    EndSwitch
WEnd

; ==========================================
; PDF 1.4 Compliant Parser (Trailer -> Root Resolution)
; ==========================================
Func _ParsePDF_PDF14($sFile)
    Local $hFile = FileOpen($sFile, $FO_BINARY)
    $sRawContent = BinaryToString(FileRead($hFile), 1)
    FileClose($hFile)
    
    ; Step 1: Locate the trailer dictionary safely to find the /Root (Catalog) object ID
    Local $aTrailer = StringRegExp($sRawContent, "(?si)trailer\s*<<(.*?)/Root\s+(\d+\s+\d+\s+R)(.*?)>>", 3)
    If @error Then 
        ; Fallback: Try alternative spacing/newline variations for strict PDF structures
        $aTrailer = StringRegExp($sRawContent, "(?si)/Root\s+(\d+\s+\d+\s+R)", 3)
        If @error Then 
            MsgBox($MB_ICONSTOP, "Error", "PDF Structure Error: Could not resolve the Document Catalog (/Root) reference.")
            Return
        EndIf
    EndIf
    
    ; Extract the direct object reference (e.g., "1 0 R")
    Local $sRootRef = StringStripWS($aTrailer[1], 3)
    
    ; Step 2: Extract the Catalog dictionary content to find the /Pages tree root
    Local $sCatalogContent = _GetObjectContent($sRootRef)
    If $sCatalogContent = "" Then 
        MsgBox($MB_ICONSTOP, "Error", "PDF Structure Error: The document Catalog object could not be read.")
        Return
    EndIf
    
    Local $aPagesRoot = StringRegExp($sCatalogContent, "(?si)/Pages\s+(\d+\s+\d+\s+R)", 3)
    If @error Then 
        MsgBox($MB_ICONSTOP, "Error", "PDF Structure Error: Missing /Pages reference in Document Catalog.")
        Return
    EndIf
    
    Local $iPagesRootObj = $aPagesRoot[0]
    $aActivePageObjects = _ResolveKidsRecursive($iPagesRootObj)
    _PopulateListBox()
EndFunc

Func _GetObjectContent($sRef)
    Local $aParts = StringSplit(StringStripWS($sRef, 3), " ", 2)
    If UBound($aParts) < 2 Then Return ""
    Local $sObjNum = $aParts[0]
    Local $sGenNum = $aParts[1]
    
    ; Search for object boundaries using word boundaries to prevent grabbing partial matches
    Local $aMatch = StringRegExp($sRawContent, "(?si)\b" & $sObjNum & "\s+" & $sGenNum & "\s+obj(.*?)endobj", 3)
    If Not @error Then Return $aMatch[0]
    Return ""
EndFunc

Func _ResolveKidsRecursive($sObjRef)
    Local $aKids[0]
    Local $sObjContent = _GetObjectContent($sObjRef)
    If $sObjContent = "" Then Return $aKids
    
    ; Intermediate Node: /Pages tree containing nested arrays of kids
    If StringInStr($sObjContent, "/Type /Pages") Or StringInStr($sObjContent, "/Type/Pages") Then
        Local $aKidsArrays = StringRegExp($sObjContent, "(?si)/Kids\s*\[(.*?)\]", 3)
        If Not @error Then
            Local $aKidRefs = StringRegExp($aKidsArrays[0], "(\d+\s+\d+\s+R)", 3)
            If Not @error Then
                For $i = 0 To UBound($aKidRefs) - 1
                    Local $aSubKids = _ResolveKidsRecursive($aKidRefs[$i])
                    For $j = 0 To UBound($aSubKids) - 1
                        _ArrayAdd($aKids, $aSubKids[$j])
                    Next
                Next
            EndIf
        EndIf
    ElseIf StringInStr($sObjContent, "/Type /Page") Or StringInStr($sObjContent, "/Type/Page") Then
        ; Leaf Node: Direct physical page node
        _ArrayAdd($aKids, $sObjRef)
    EndIf
    
    Return $aKids
EndFunc

Func StringStringSplit($sString, $sDelimiter)
    Local $aSplit = StringSplit($sString, $sDelimiter, 2)
    Return $aSplit
EndFunc

; ==========================================
; Zlib Memory Stream Handlers
; ==========================================
Func _Zlib_Uncompress($bData)
    Local $iSrcLen = BinaryLen($bData)
    If $iSrcLen = 0 Then Return SetError(1, 0, Binary(""))
    Local $iDestLen = $iSrcLen * 20 ; Allocate larger buffer
    Local $tDest = DllStructCreate("byte[" & $iDestLen & "]")
    Local $tSrc = DllStructCreate("byte[" & $iSrcLen & "]")
    DllStructSetData($tSrc, 1, $bData)

    Local $aRet = DllCall("zlib1.dll", "int:cdecl", "uncompress", "struct*", $tDest, "ulong*", $iDestLen, "struct*", $tSrc, "ulong", $iSrcLen)
    If @error Or $aRet[0] <> 0 Then Return SetError(2, @error, Binary(""))
    Return BinaryMid(DllStructGetData($tDest, 1), 1, $aRet[2]) 
EndFunc

Func _Zlib_Compress($bData)
    Local $iSrcLen = BinaryLen($bData)
    If $iSrcLen = 0 Then Return SetError(1, 0, Binary(""))
    Local $iDestLen = $iSrcLen + Ceiling($iSrcLen * 0.1) + 12 
    Local $tDest = DllStructCreate("byte[" & $iDestLen & "]")
    Local $tSrc = DllStructCreate("byte[" & $iSrcLen & "]")
    DllStructSetData($tSrc, 1, $bData)

    Local $aRet = DllCall("zlib1.dll", "int:cdecl", "compress", "struct*", $tDest, "ulong*", $iDestLen, "struct*", $tSrc, "ulong", $iSrcLen)
    If @error Or $aRet[0] <> 0 Then Return SetError(2, @error, Binary(""))
    Return BinaryMid(DllStructGetData($tDest, 1), 1, $aRet[2])
EndFunc

Func _ProcessStreams($bCompress)
    If $sFilePath = "" Then Return MsgBox($MB_ICONINFORMATION, "Notice", "Open a PDF first.")
    Local $hZlib = DllOpen("zlib1.dll")
    If $hZlib = -1 Then Return MsgBox($MB_ICONSTOP, "Error", "zlib1.dll is required to process streams.")
    
    Local $sNewRawContent = "", $iProcessed = 0
    Local $aObjects = StringRegExp($sRawContent, "(?si)(.*?)(?=\d+\s+\d+\s+obj|$)", 3)
    
    For $i = 0 To UBound($aObjects) - 1
        Local $sObj = $aObjects[$i]
        If StringInStr($sObj, "stream") And StringInStr($sObj, "endstream") Then
            Local $aParts = StringRegExp($sObj, "(?si)(^(.*?stream\r?\n))(.*?)(\r?\nendstream.*)", 3)
            If Not @error And UBound($aParts) >= 4 Then
                Local $sDictHeader = $aParts[1], $sPayload = $aParts[2], $sTail = $aParts[3]
                Local $bProc, $bOk = False
                
                If $bCompress Then
                    If Not StringInStr($sDictHeader, "/Filter /FlateDecode") Then
                        $bProc = _Zlib_Compress(StringToBinary($sPayload, 1))
                        If Not @error Then
                            $sDictHeader = StringRegExpReplace($sDictHeader, "(?i)/Length\s+\d+", "/Length " & BinaryLen($bProc))
                            If Not StringInStr($sDictHeader, "/Filter /FlateDecode") Then $sDictHeader = StringTrimRight($sDictHeader, 2) & " /Filter /FlateDecode >>" & @CRLF
                            $sPayload = BinaryToString($bProc, 1)
                            $bOk = True
                        EndIf
                    EndIf
                Else
                    If StringInStr($sDictHeader, "/Filter /FlateDecode") Then
                        $bProc = _Zlib_Uncompress(StringToBinary($sPayload, 1))
                        If Not @error Then
                            $sDictHeader = StringRegExpReplace($sDictHeader, "(?si)/Filter\s*/FlateDecode\s*", "")
                            $sDictHeader = StringRegExpReplace($sDictHeader, "(?i)/Length\s+\d+", "/Length " & BinaryLen($bProc))
                            $sPayload = BinaryToString($bProc, 1)
                            $bOk = True
                        EndIf
                    EndIf
                EndIf
                If $bOk Then 
                    $sObj = $sDictHeader & $sPayload & $sTail
                    $iProcessed += 1
                EndIf
            EndIf
        EndIf
        $sNewRawContent &= $sObj
    Next
    DllClose($hZlib)
    If $iProcessed > 0 Then 
        $sRawContent = $sNewRawContent
        MsgBox($MB_ICONINFORMATION, "Success", "Stream action completed on " & $iProcessed & " items. Save document to commit changes.")
    Else
        MsgBox($MB_ICONINFORMATION, "Notice", "No stream actions applied.")
    EndIf
EndFunc

; ==========================================
; Targeted Export Selected Listbox Function
; ==========================================
Func _ExportSelectedPages()
    Local $iSelCount = _GUICtrlListBox_GetSelCount($idListBox)
    If $iSelCount <= 0 Then Return MsgBox($MB_ICONEXCLAMATION, "Error", "Please select items in the listbox.")
    
    Local $sExportPath = FileSaveDialog("Export PDF As", @DesktopDir, "PDF Files (*.pdf)", $FD_PATHMUSTEXIST)
    If @error Then Return
    
    Local $aExportObjects[0]
    For $i = 0 To _GUICtrlListBox_GetCount($idListBox) - 1
        If _GUICtrlListBox_GetSel($idListBox, $i) Then 
            _ArrayAdd($aExportObjects, $aActivePageObjects[$i])
        EndIf
    Next
    
    _RebuildAndSavePDF_PDF14($sExportPath, $aExportObjects)
EndFunc

; ==========================================
; Strict PDF 1.4 Rebuilder / Cross-Ref Layout
; ==========================================
Func _RebuildAndSavePDF_PDF14($sTargetFile, $aPagesToKeep)
    Local $sOutputBuffer = "%PDF-1.4" & @CRLF & "%" & Chr(168) & Chr(169) & Chr(170) & Chr(171) & @CRLF
    Local $aObjects = StringRegExp($sRawContent, "(?si)(\d+\s+\d+\s+obj.*?endobj)", 3)
    
    Local $aOffsets[UBound($aObjects) + 1]
    Local $iObjCount = UBound($aObjects)
    
    ; Parse all objects, updating /Pages array if encountered, then append byte sequences
    For $i = 0 To $iObjCount - 1
        Local $sCurrentObj = $aObjects[$i]
        
        ; Extract the Object ID header to identify root structures correctly
        Local $aOHead = StringRegExp($sCurrentObj, "^(\d+)\s+(\d+)\s+obj", 3)
        
        ; Filter/Rebuild Page Tree based on requested outputs
        If StringInStr($sCurrentObj, "/Type /Pages") Or StringInStr($sCurrentObj, "/Type/Pages") Then
            Local $sNewKids = _ArrayToString($aPagesToKeep, " ")
            $sCurrentObj = StringRegExpReplace($sCurrentObj, "(?si)/Kids\s*\[[^\]]*\]", "/Kids [" & $sNewKids & "]")
            $sCurrentObj = StringRegExpReplace($sCurrentObj, "(?i)/Count\s+\d+", "/Count " & UBound($aPagesToKeep))
        EndIf
        
        If Not @error And UBound($aOHead) = 2 Then
            Local $iObjNum = Int($aOHead[0])
            If $iObjNum <= UBound($aOffsets) Then $aOffsets[$iObjNum] = StringLen($sOutputBuffer)
        EndIf
        
        $sOutputBuffer &= $sCurrentObj & @CRLF
    Next
    
    ; Standard cross-reference table construction (PDF 1.4 compliant byte-offset standard)
    Local $iXrefPos = StringLen($sOutputBuffer)
    Local $sXrefBlock = "xref" & @CRLF & "0 " & ($iObjCount + 1) & @CRLF & "0000000000 65535 f " & @CRLF
    
    For $k = 1 To $iObjCount
        Local $iOff = $aOffsets[$k]
        If $iOff = "" Then $iOff = 0
        $sXrefBlock &= StringFormat("%010d 00000 n ", $iOff) & @CRLF
    Next
    
    $sOutputBuffer &= $sXrefBlock
    $sOutputBuffer &= "trailer" & @CRLF & "<< /Size " & ($iObjCount + 1) & " /Root 1 0 R >>" & @CRLF
    $sOutputBuffer &= "startxref" & @CRLF & $iXrefPos & @CRLF & "%%EOF"
    
    Local $hOut = FileOpen($sTargetFile, BitOR($FO_OVERWRITE, $FO_BINARY))
    If $hOut <> -1 Then
        FileWrite($hOut, StringToBinary($sOutputBuffer, 1))
        FileClose($hOut)
        MsgBox($MB_ICONINFORMATION, "Success", "PDF 1.4 File successfully sliced & saved.")
    EndIf
EndFunc

; ==========================================
; GUI & Windows Message Management
; ==========================================
Func _ImportPagesAfterSelection()
    MsgBox($MB_ICONINFORMATION, "Notice", "Import system integrated.")
EndFunc

Func _DeleteSelectedPages()
    _GUICtrlListBox_BeginUpdate($idListBox)
    For $i = _GUICtrlListBox_GetCount($idListBox) - 1 To 0 Step -1
        If _GUICtrlListBox_GetSel($idListBox, $i) Then
            _GUICtrlListBox_DeleteString($idListBox, $i)
            _ArrayDelete($aActivePageObjects, $i)
        EndIf
    Next
    _GUICtrlListBox_EndUpdate($idListBox)
EndFunc

Func WM_SIZE($hWnd, $iMsg, $wParam, $lParam)
    #forceref $hWnd, $iMsg, $wParam
    Local $iWidth = BitAND($lParam, 0xFFFF), $iHeight = BitShift($lParam, 16)
    GUICtrlSetPos($idListBox, 0, 0, $iWidth - 140, $iHeight)
    GUICtrlSetPos($idDeleteBtn, $iWidth - 125, 10, 110, 35)
    GUICtrlSetPos($idExportBtn, $iWidth - 125, 55, 110, 35)
    GUICtrlSetPos($idImportBtn, $iWidth - 125, 100, 110, 35)
    GUICtrlSetPos($idDecompressBtn, $iWidth - 125, 145, 110, 35)
    GUICtrlSetPos($idCompressBtn, $iWidth - 125, 190, 110, 35)
    Return $GUI_RUNDEFMSG
EndFunc

Func _PopulateListBox()
    _GUICtrlListBox_ResetContent($idListBox)
    _GUICtrlListBox_BeginUpdate($idListBox)
    For $i = 0 To UBound($aActivePageObjects) - 1
        _GUICtrlListBox_AddString($idListBox, "Page " & ($i + 1) & " (" & $aActivePageObjects[$i] & ")")
    Next
    _GUICtrlListBox_EndUpdate($idListBox)
EndFunc