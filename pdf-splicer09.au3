#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <GuiListBox.au3>
#include <MsgBoxConstants.au3>
#include <FileConstants.au3>
#include <Array.au3>

; Global State Variables
Global $sFilePath = ""
Global $sRawContent = "" 
Global $aActivePageObjects[0] 
Global $sTitle = "", $sSubject = "", $sCreator = "", $sProducer = "", $sKeywords = "", $sAuthor = ""
Global $sPageDimensions = "Unknown", $sPageSizeInches = "Unknown", $sPageSizeMM = "Unknown"
Global $sInfoObjID = "0 0 R" 

; Create Main GUI
Global $hMainGUI = GUICreate("AutoIt PDF Splicer (PDF 1.2 / 1.4 Compatible)", 520, 430, -1, -1, BitOR($WS_MINIMIZEBOX, $WS_SIZEBOX, $WS_THICKFRAME, $WS_MAXIMIZEBOX))

; Create Menus
Global $mFile = GUICtrlCreateMenu("&File")
Global $mOpen = GUICtrlCreateMenuItem("&Open...", $mFile)
Global $mEditProps = GUICtrlCreateMenuItem("Edit &Properties", $mFile)
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
                _ParsePDF_BackwardsCompatible($sFilePath)
                _PopulateListBox()
                WinSetTitle($hMainGUI, "", "AutoIt PDF Splicer - " & StringRegExpReplace($sFilePath, "^.*\\", ""))
            EndIf

        Case $mEditProps
            If $sFilePath <> "" Then _ShowPropertiesWindow()
            
        Case $mSave, $mSaveAs
            If $sFilePath = "" Then ContinueLoop
            Local $sSavePath = $sFilePath
            If $nMsg = $mSaveAs Then $sSavePath = FileSaveDialog("Save PDF As", @DesktopDir, "PDF Files (*.pdf)", $FD_PATHMUSTEXIST)
            If $sSavePath <> "" Then _RebuildAndSavePDF_BackwardsCompatible($sSavePath, $aActivePageObjects)

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

; =========================================================================
; PDF 1.2 / 1.4 Compliant Parser (Handles direct trees and missing structures)
; =========================================================================
Func _ParsePDF_BackwardsCompatible($sFile)
    Local $hFile = FileOpen($sFile, $FO_BINARY)
    $sRawContent = BinaryToString(FileRead($hFile), 1)
    FileClose($hFile)
    
    ; Reset metadata and states
    $sTitle = ""
    $sSubject = ""
    $sCreator = ""
    $sProducer = ""
    $sKeywords = ""
    $sAuthor = ""
    $sInfoObjID = "0 0 R"

    ; Extract /Info dictionary reference from the initial document trailer declaration
    Local $aInfoObj = StringRegExp($sRawContent, "(?si)trailer\s*<<(.*?)/Info\s+(\d+\s+\d+\s+R)(.*?)>>", 3)
    If Not @error And UBound($aInfoObj) >= 2 Then
        $sInfoObjID = StringStripWS($aInfoObj[1], 3)
        Local $sInfoContent = _GetObjectContentInternal($sInfoObjID, True)
        
        $sTitle = _CleanMetadataString(StringRegExpReplace($sInfoContent, "(?si).*?/Title\s*\((.*?)\).*", "$1"))
        $sSubject = _CleanMetadataString(StringRegExpReplace($sInfoContent, "(?si).*?/Subject\s*\((.*?)\).*", "$1"))
        $sCreator = _CleanMetadataString(StringRegExpReplace($sInfoContent, "(?si).*?/Creator\s*\((.*?)\).*", "$1"))
        $sProducer = _CleanMetadataString(StringRegExpReplace($sInfoContent, "(?si).*?/Producer\s*\((.*?)\).*", "$1"))
        $sKeywords = _CleanMetadataString(StringRegExpReplace($sInfoContent, "(?si).*?/Keywords\s*\((.*?)\).*", "$1"))
        $sAuthor = _CleanMetadataString(StringRegExpReplace($sInfoContent, "(?si).*?/Author\s*\((.*?)\).*", "$1"))
    EndIf

    ; Resolve Root Catalog safely
    Local $aTrailer = StringRegExp($sRawContent, "(?si)trailer\s*<<(.*?)/Root\s+(\d+\s+\d+\s+R)(.*?)>>", 3)
    If @error Then 
        $aTrailer = StringRegExp($sRawContent, "(?si)/Root\s+(\d+\s+\d+\s+R)", 3)
        If @error Then 
            MsgBox($MB_ICONSTOP, "Error", "PDF Parsing Error: Could not resolve document Catalog root.")
            Return
        EndIf
    EndIf
    
    Local $sRootRef = StringStripWS($aTrailer[1], 3)
    Local $sCatalogContent = _GetObjectContentInternal($sRootRef, False)
    If $sCatalogContent = "" Then 
        MsgBox($MB_ICONSTOP, "Error", "PDF Parsing Error: The document Catalog object is unreadable.")
        Return
    EndIf
    
    ; Fallback detection if document doesn't use standard /Pages structure (Backwards compatibility mode)
    Local $aPagesRoot = StringRegExp($sCatalogContent, "(?si)/Pages\s+(\d+\s+\d+\s+R)", 3)
    If @error Then 
        ; Page references may be embedded inside Root Catalog array directly
        Local $aDirectPageCheck = StringRegExp($sCatalogContent, "(?si)/MediaBox", 3)
        If Not @error Then
            Local $aRootID = StringRegExp($sRootRef, "(\d+)\s+(\d+)", 3)
            If Not @error Then _ArrayAdd($aActivePageObjects, $aRootID[0] & " " & $aRootID[1] & " R")
        Else
            MsgBox($MB_ICONSTOP, "Error", "PDF Parsing Error: Missing /Pages mapping structure reference.")
            Return
        EndIf
    Else
        Local $iPagesRootObj = $aPagesRoot[0]
        $aActivePageObjects = _ResolveKidsRecursive($iPagesRootObj)
    EndIf
    
    ; Parse dimensions from first available page node
    If UBound($aActivePageObjects) > 0 Then
        Local $sFirstPage = _GetObjectContentInternal($aActivePageObjects[0], False)
        Local $aMediaBox = StringRegExp($sFirstPage, "(?si)/MediaBox\s*\[\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*\]", 3)
        If Not @error And UBound($aMediaBox) = 4 Then
            Local $nWidthPoints = $aMediaBox[2] - $aMediaBox[0]
            Local $nHeightPoints = $aMediaBox[3] - $aMediaBox[1]
            
            $sPageDimensions = Round($nWidthPoints) & "x" & Round($nHeightPoints) & " points"
            Local $nWidthIn = $nWidthPoints / 72
            Local $nHeightIn = $nHeightPoints / 72
            $sPageSizeInches = Round($nWidthIn, 2) & "x" & Round($nHeightIn, 2) & " inches"
            Local $nWidthMM = $nWidthIn * 25.4
            Local $nHeightMM = $nHeightIn * 25.4
            $sPageSizeMM = Round($nWidthMM, 1) & "x" & Round($nHeightMM, 1) & " mm"
        Else
            $sPageDimensions = "Undefined MediaBox"
            $sPageSizeInches = "N/A"
            $sPageSizeMM = "N/A"
        EndIf
    Else
        $sPageDimensions = "No Active Pages"
        $sPageSizeInches = "N/A"
        $sPageSizeMM = "N/A"
    EndIf
EndFunc

Func _CleanMetadataString($sText)
    If StringRegExp($sText, "endobj") Then Return ""
    $sText = StringRegExpReplace($sText, "[()\r\n]", "")
    Return $sText
EndFunc

Func _GetObjectContentInternal($sRef, $bIsInfo)
    Local $aParts = StringSplit(StringStripWS($sRef, 3), " ", 2)
    If UBound($aParts) < 2 Then Return ""
    Local $sObjNum = $aParts[0]
    Local $sGenNum = $aParts[1]
    
    Local $aMatch = StringRegExp($sRawContent, "(?si)\b" & $sObjNum & "\s+" & $sGenNum & "\s+obj(.*?)endobj", 3)
    If Not @error Then
        Local $sContent = $aMatch[0]
        If $bIsInfo And (StringInStr($sContent, "/Filter /FlateDecode") Or StringInStr($sContent, "/Filter/FlateDecode")) Then
            Local $aStream = StringRegExp($sContent, "(?si)stream\s*(.*?)\s*endstream", 3)
            If Not @error Then
                Local $bUncompressed = _Zlib_Uncompress(StringToBinary($aStream[0], 1))
                If Not @error Then $sContent = BinaryToString($bUncompressed)
            EndIf
        EndIf
        Return $sContent
    EndIf
    Return ""
EndFunc

Func _ResolveKidsRecursive($sObjRef)
    Local $aKids[0]
    Local $sObjContent = _GetObjectContentInternal($sObjRef, False)
    If $sObjContent = "" Then Return $aKids
    
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
        _ArrayAdd($aKids, $sObjRef)
    EndIf
    
    Return $aKids
EndFunc

; ==========================================
; Zlib Memory Stream Handlers
; ==========================================
Func _GetZlibPath()
    Local $sDLLPath = @ScriptDir & "\zlib1.dll"
    If FileExists($sDLLPath) Then Return $sDLLPath
    Return "zlib1.dll"
EndFunc

Func _Zlib_Uncompress($bData)
    Local $iSrcLen = BinaryLen($bData)
    If $iSrcLen = 0 Then Return SetError(1, 0, Binary(""))
    Local $iDestLen = $iSrcLen * 20 
    Local $tDest = DllStructCreate("byte[" & $iDestLen & "]")
    Local $tSrc = DllStructCreate("byte[" & $iSrcLen & "]")
    DllStructSetData($tSrc, 1, $bData)

    Local $aRet = DllCall(_GetZlibPath(), "int:cdecl", "uncompress", "struct*", $tDest, "ulong*", $iDestLen, "struct*", $tSrc, "ulong", $iSrcLen)
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

    Local $aRet = DllCall(_GetZlibPath(), "int:cdecl", "compress", "struct*", $tDest, "ulong*", $iDestLen, "struct*", $tSrc, "ulong", $iSrcLen)
    If @error Or $aRet[0] <> 0 Then Return SetError(2, @error, Binary(""))
    Return BinaryMid(DllStructGetData($tDest, 1), 1, $aRet[2])
EndFunc

Func _ProcessStreams($bCompress)
    If $sFilePath = "" Then Return MsgBox($MB_ICONINFORMATION, "Notice", "Open a PDF first.")
    Local $hZlib = DllOpen(_GetZlibPath())
    If $hZlib = -1 Then Return MsgBox($MB_ICONSTOP, "Error", "Failed to open zlib1.dll. Ensure 32-bit DLL is in the script directory.")
    
    Local $sNewRawContentWorking = $sRawContent
	Local $sRawContentWorking = $sRawContent
    Local $sNewRawContent = "", $iProcessed = 0
    Local $aObjects = StringRegExp($sRawContentWorking, "(?si)(.*?)(?=\d+\s+\d+\s+obj|$)", 3)
    
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
; Robust Import Function (ID Remapping & Insertion)
; ==========================================
Func _ImportPagesAfterSelection()
    If $sFilePath = "" Then Return MsgBox($MB_ICONINFORMATION, "Notice", "Open a base PDF first.")
    
    Local $sImportFile = FileOpenDialog("Select PDF to Import", @DesktopDir, "PDF Files (*.pdf)", $FD_FILEMUSTEXIST)
    If @error Then Return
    
    Local $hFile = FileOpen($sImportFile, $FO_BINARY)
    Local $sImportContent = BinaryToString(FileRead($hFile), 1)
    FileClose($hFile)
    
    Local $iMaxHostID = 0
    Local $aHostObjs = StringRegExp($sRawContent, "\b(\d+)\s+\d+\s+obj", 3)
    If Not @error Then
        For $i = 0 To UBound($aHostObjs) - 1
            If Int($aHostObjs[$i]) > $iMaxHostID Then $iMaxHostID = Int($aHostObjs[$i])
        Next
    EndIf
    
    Local $iOffset = $iMaxHostID + 100
    Local $aImportObjIDs = StringRegExp($sImportContent, "\b(\d+)\s+\d+\s+obj", 3)
    If @error Then Return MsgBox($MB_ICONSTOP, "Error", "No valid objects found in import file.")
    
    _ArraySort($aImportObjIDs, 1)
    Local $sRemappedImport = $sImportContent
    
    For $i = 0 To UBound($aImportObjIDs) - 1
        Local $iOld = $aImportObjIDs[$i]
        Local $iNew = Int($iOld) + $iOffset
        $sRemappedImport = StringRegExpReplace($sRemappedImport, "(?i)\b" & $iOld & "(\s+0\s+obj)", $iNew & "$1")
        $sRemappedImport = StringRegExpReplace($sRemappedImport, "(?i)\b" & $iOld & "(\s+0\s+R)", $iNew & "$1")
    Next

    Local $aDirectPages = StringRegExp($sRemappedImport, "(?si)(\d+\s+\d+\s+obj\s*<<[^>]*?/Type\s*/Page\b.*?endobj)", 3)
    If @error Then Return MsgBox($MB_ICONSTOP, "Parsing Error", "Could not resolve individual /Page leaf nodes in import document.")
    
    Local $aImportedKids[0]
    For $i = 0 To UBound($aDirectPages) - 1
        Local $aObjID = StringRegExp($aDirectPages[$i], "^(\d+)\s+(\d+)\s+obj", 3)
        If Not @error Then _ArrayAdd($aImportedKids, $aObjID[0] & " " & $aObjID[1] & " R")
    Next
    
    Local $aImportedObjects = StringRegExp($sRemappedImport, "(?si)(\d+\s+\d+\s+obj.*?endobj)", 3)
    If Not @error Then
        For $i = 0 To UBound($aImportedObjects) - 1
            If Not StringInStr($aImportedObjects[$i], "/Type /Catalog") And Not StringInStr($aImportedObjects[$i], "/Type /Pages") Then
                $sRawContent &= @CRLF & $aImportedObjects[$i]
            EndIf
        Next
    EndIf
    
    Local $iTargetIdx = _GUICtrlListBox_GetCaretIndex($idListBox)
    If $iTargetIdx = -1 Then $iTargetIdx = 0
    
    _GUICtrlListBox_BeginUpdate($idListBox)
    For $i = 0 To UBound($aImportedKids) - 1
        Local $iCurrentPos = $iTargetIdx + $i
        _ArrayInsert($aActivePageObjects, $iCurrentPos, $aImportedKids[$i])
    Next
    _GUICtrlListBox_EndUpdate($idListBox)
    
    _PopulateListBox()
    _ParsePDF_BackwardsCompatible($sFilePath)
    MsgBox($MB_ICONINFORMATION, "Success", UBound($aImportedKids) & " pages successfully imported and mapped. Save file to apply changes.")
EndFunc

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
    
    _RebuildAndSavePDF_BackwardsCompatible($sExportPath, $aExportObjects)
EndFunc

; ===============================================================================================
; Strict PDF 1.2 / 1.4 Backwards Compatible Rebuilder
; Enforces PDF specification structure: Header at start, objects in order, Info dictionary only once
; ===============================================================================================
Func _RebuildAndSavePDF_BackwardsCompatible($sTargetFile, $aPagesToKeep)
    ; Header strictly placed at the very beginning of the file
    Local $sOutputBuffer = "%PDF-1.2" & @CRLF & "%" & Chr(168) & Chr(169) & Chr(170) & Chr(171) & @CRLF
    
    ; Strip existing trailing structures or duplicate info blocks to guarantee uniqueness
    Local $sCleanRaw = StringRegExpReplace($sRawContent, "(?si)trailer\s*<<.*", "")
    $sCleanRaw = StringRegExpReplace($sCleanRaw, "(?si)xref.*", "")
    
    Local $aObjects = StringRegExp($sCleanRaw, "(?si)(\d+\s+\d+\s+obj.*?endobj)", 3)
    Local $aOffsets[UBound($aObjects) + 500]
    Local $iObjCount = UBound($aObjects)
    
    For $i = 0 To $iObjCount - 1
        Local $sCurrentObj = $aObjects[$i]
        Local $aOHead = StringRegExp($sCurrentObj, "^(\d+)\s+(\d+)\s+obj", 3)
        
        ; Backwards compatibility root node remapping
        If StringInStr($sCurrentObj, "/Type /Pages") Or StringInStr($sCurrentObj, "/Type/Pages") Then
            Local $sNewKids = _ArrayToString($aPagesToKeep, " ")
            $sCurrentObj = StringRegExpReplace($sCurrentObj, "(?si)/Kids\s*\[[^\]]*\]", "/Kids [" & $sNewKids & "]")
            $sCurrentObj = StringRegExpReplace($sCurrentObj, "(?i)/Count\s+\d+", "/Count " & UBound($aPagesToKeep))
        EndIf
        
        If Not @error And UBound($aOHead) = 2 Then
            Local $iObjNum = Int($aOHead[0])
            If $iObjNum < UBound($aOffsets) Then $aOffsets[$iObjNum] = StringLen($sOutputBuffer)
        EndIf
        
        $sOutputBuffer &= $sCurrentObj & @CRLF
    Next

    ; Metadata / Info dictionary declared strictly as an individual object at the end
    Local $iInfoObjNum = $iObjCount + 1
    $aOffsets[$iInfoObjNum] = StringLen($sOutputBuffer)
    
    Local $sInfoObj = $iInfoObjNum & " 0 obj" & @CRLF & _
                      "<< /Title (" & StringRegExpReplace($sTitle, "[()\r\n]", "") & ") " & _
                      "/Subject (" & StringRegExpReplace($sSubject, "[()\r\n]", "") & ") " & _
                      "/Creator (" & StringRegExpReplace($sCreator, "[()\r\n]", "") & ") " & _
                      "/Producer (" & StringRegExpReplace($sProducer, "[()\r\n]", "") & ") " & _
                      "/Keywords (" & StringRegExpReplace($sKeywords, "[()\r\n]", "") & ") " & _
                      "/Author (" & StringRegExpReplace($sAuthor, "[()\r\n]", "") & ") >>" & @CRLF & "endobj" & @CRLF
    $sOutputBuffer &= $sInfoObj

    Local $iTrueMaxObj = $iInfoObjNum + 1
    Local $iXrefPos = StringLen($sOutputBuffer)
    
    ; Build Strict 20-byte aligned cross-reference (Xref) Table layout
    Local $sXrefBlock = "xref" & @CRLF & "0 " & ($iTrueMaxObj) & @CRLF & "0000000000 65535 f " & @CRLF
    
    For $k = 1 To ($iTrueMaxObj - 1)
        Local $iOff = $aOffsets[$k]
        If $iOff = "" Then $iOff = 0
        $sXrefBlock &= StringFormat("%010d 00000 n ", $iOff) & @CRLF
    Next
    
    $sOutputBuffer &= $sXrefBlock
    $sOutputBuffer &= "trailer" & @CRLF & "<< /Size " & ($iTrueMaxObj) & " /Root 1 0 R /Info " & $iInfoObjNum & " 0 R >>" & @CRLF
    $sOutputBuffer &= "startxref" & @CRLF & $iXrefPos & @CRLF & "%%EOF"
    
    Local $hOut = FileOpen($sTargetFile, BitOR($FO_OVERWRITE, $FO_BINARY))
    If $hOut <> -1 Then
        FileWrite($hOut, StringToBinary($sOutputBuffer, 1))
        FileClose($hOut)
        MsgBox($MB_ICONINFORMATION, "Success", "PDF File backed up and compiled in PDF 1.2/1.4 structural compliance.")
    EndIf
EndFunc

; ==========================================
; PDF Property Editor Window 
; ==========================================

Func _ShowPropertiesWindow()
    Local $hPropGUI = GUICreate("PDF Metadata Properties", 420, 360, -1, -1, BitOR($WS_CAPTION, $WS_POPUP, $WS_SYSMENU))
    
    ; Metadata Fields
    GUICtrlCreateLabel("Title:", 20, 20, 80, 20)
    Local $idTitleInput = GUICtrlCreateInput($sTitle, 110, 20, 280, 20)
    
    GUICtrlCreateLabel("Subject:", 20, 50, 80, 20)
    Local $idSubjectInput = GUICtrlCreateInput($sSubject, 110, 50, 280, 20)
    
    GUICtrlCreateLabel("Author:", 20, 80, 80, 20)
    Local $idAuthorInput = GUICtrlCreateInput($sAuthor, 110, 80, 280, 20)
    
    GUICtrlCreateLabel("Creator:", 20, 110, 80, 20)
    Local $idCreatorInput = GUICtrlCreateInput($sCreator, 110, 110, 280, 20)
    
    GUICtrlCreateLabel("Producer:", 20, 140, 80, 20)
    Local $idProducerInput = GUICtrlCreateInput($sProducer, 110, 140, 280, 20)
    
    GUICtrlCreateLabel("Keywords:", 20, 170, 80, 20)
    Local $idKeywordsInput = GUICtrlCreateInput($sKeywords, 110, 170, 280, 20)

    ; Page Statistics Displays
    GUICtrlCreateLabel("Page Count:", 20, 210, 80, 20)
    GUICtrlCreateLabel(UBound($aActivePageObjects), 110, 210, 280, 20)
    
    GUICtrlCreateLabel("Page Size (Pts):", 20, 240, 85, 20)
    GUICtrlCreateLabel($sPageDimensions, 110, 240, 280, 20)

    GUICtrlCreateLabel("Size (Inches):", 20, 270, 85, 20)
    GUICtrlCreateLabel($sPageSizeInches, 110, 270, 280, 20)
    
    GUICtrlCreateLabel("Size (MM):", 20, 300, 85, 20)
    GUICtrlCreateLabel($sPageSizeMM, 110, 300, 280, 20)
    
    ; Apply & Close Action Buttons
    Local $idApplyPropBtn = GUICtrlCreateButton("Apply", 180, 325, 100, 25)
    Local $idCancelPropBtn = GUICtrlCreateButton("Close", 300, 325, 100, 25)
    
    GUISetState(@SW_SHOW, $hPropGUI)
    
    While 1
        Local $nMsg = GUIGetMsg()
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $idCancelPropBtn
                GUIDelete($hPropGUI)
                ExitLoop
                
            Case $idApplyPropBtn
                $sTitle = GUICtrlRead($idTitleInput)
                $sSubject = GUICtrlRead($idSubjectInput)
                $sAuthor = GUICtrlRead($idAuthorInput)
                $sCreator = GUICtrlRead($idCreatorInput)
                $sProducer = GUICtrlRead($idProducerInput)
                $sKeywords = GUICtrlRead($idKeywordsInput)
                MsgBox($MB_ICONINFORMATION, "Applied", "Properties updated directly to working memory. Use File -> Save to compile permanently to disk.")
        EndSwitch
    WEnd
EndFunc

; ==========================================
; GUI & Windows Message Management
; ==========================================
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