#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <GuiListBox.au3>
#include <MsgBoxConstants.au3>
#include <FileConstants.au3>
#include <Array.au3>

; Global State Variables
Global $sFilePath = ""
Global $iPageCount = 0
Global $sTitle = "", $sSubject = "", $sCreator = "", $sProducer = "", $sKeywords = "", $sAuthor = ""
Global $fWidthPoints = 612.0, $fHeightPoints = 792.0
Global $sRawContent = "" 
Global $aActivePageObjects[0] ; Dynamic array

; Create Main GUI
Global $hMainGUI = GUICreate("AutoIt PDF Splicer", 520, 430, -1, -1, BitOR($WS_MINIMIZEBOX, $WS_SIZEBOX, $WS_THICKFRAME, $WS_MAXIMIZEBOX))

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
                _ParsePDF($sFilePath)
                _PopulateListBox()
                WinSetTitle($hMainGUI, "", "AutoIt PDF Splicer - " & $sFilePath)
            EndIf
            
        Case $mSave, $mSaveAs
            If $sFilePath = "" Then ContinueLoop
            Local $sSavePath = $sFilePath
            If $nMsg = $mSaveAs Then $sSavePath = FileSaveDialog("Save PDF As", @DesktopDir, "PDF Files (*.pdf)", $FD_PATHMUSTEXIST)
            If $sSavePath <> "" Then _RebuildAndSavePDF($sSavePath, $aActivePageObjects)

        Case $mEditProps
            If $sFilePath <> "" Then _ShowPropertiesWindow()
            
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
; Zlib Core Functions
; ==========================================
Func _Zlib_Uncompress($bData)
    Local $iSrcLen = BinaryLen($bData)
    If $iSrcLen = 0 Then Return SetError(1, 0, Binary(""))
    
    ; Allocate a destination buffer (guess 15x original size for text streams)
    Local $iDestLen = $iSrcLen * 15
    Local $tDest = DllStructCreate("byte[" & $iDestLen & "]")
    Local $tSrc = DllStructCreate("byte[" & $iSrcLen & "]")
    DllStructSetData($tSrc, 1, $bData)

    ; cdecl calling convention is strictly required for standard zlib1.dll
    Local $aRet = DllCall("zlib1.dll", "int:cdecl", "uncompress", _
        "struct*", $tDest, _
        "ulong*", $iDestLen, _
        "struct*", $tSrc, _
        "ulong", $iSrcLen)

    If @error Or $aRet[0] <> 0 Then Return SetError(2, $aRet[0], Binary(""))
    
    ; $aRet[2] contains the actual decompressed byte length returned by the DLL
    Return BinaryMid(DllStructGetData($tDest, 1), 1, $aRet[2]) 
EndFunc

Func _Zlib_Compress($bData)
    Local $iSrcLen = BinaryLen($bData)
    If $iSrcLen = 0 Then Return SetError(1, 0, Binary(""))
    
    ; Zlib safe buffer calculation: sourceLen + 0.1% + 12 bytes
    Local $iDestLen = $iSrcLen + Ceiling($iSrcLen * 0.1) + 12 
    Local $tDest = DllStructCreate("byte[" & $iDestLen & "]")
    Local $tSrc = DllStructCreate("byte[" & $iSrcLen & "]")
    DllStructSetData($tSrc, 1, $bData)

    Local $aRet = DllCall("zlib1.dll", "int:cdecl", "compress", _
        "struct*", $tDest, _
        "ulong*", $iDestLen, _
        "struct*", $tSrc, _
        "ulong", $iSrcLen)

    If @error Or $aRet[0] <> 0 Then Return SetError(2, $aRet[0], Binary(""))
    
    Return BinaryMid(DllStructGetData($tDest, 1), 1, $aRet[2])
EndFunc

; ==========================================
; Stream Processing (True Memory Parsing)
; ==========================================
Func _ProcessStreams($bCompress)
    If $sFilePath = "" Then Return MsgBox($MB_ICONINFORMATION, "Notice", "Open a PDF first.")
    
    Local $hZlib = DllOpen("zlib1.dll")
    If $hZlib = -1 Then Return MsgBox($MB_ICONSTOP, "Error", "zlib1.dll not found in script directory or System32.")
    
    Local $sNewRawContent = ""
    Local $iProcessedCount = 0
    
    ; Break the entire document into individual objects to prevent corrupting non-stream data
    Local $aObjects = StringRegExp($sRawContent, "(?s)(.*?)(?=\d+\s+\d+\s+obj|$)", 3)
    
    For $i = 0 To UBound($aObjects) - 1
        Local $sObj = $aObjects[$i]
        
        If StringInStr($sObj, "stream") And StringInStr($sObj, "endstream") Then
            ; Extract Dictionary, Payload, and Tail
            Local $aParts = StringRegExp($sObj, "(?s)(^(.*?stream\r?\n))(.*?)(\r?\nendstream.*)", 3)
            If Not @error And UBound($aParts) >= 4 Then
                Local $sDictHeader = $aParts[1]
                Local $sPayload = $aParts[2]
                Local $sTail = $aParts[3]
                Local $bProcessedData
                Local $bSuccess = False
                
                If $bCompress Then
                    ; Only compress if it isn't already compressed
                    If Not StringInStr($sDictHeader, "/Filter /FlateDecode") Then
                        $bProcessedData = _Zlib_Compress(StringToBinary($sPayload, 1))
                        If Not @error Then
                            ; Inject the filter flag and update the length
                            $sDictHeader = StringRegExpReplace($sDictHeader, "(?i)/Length\s+\d+", "/Length " & BinaryLen($bProcessedData) & " /Filter /FlateDecode")
                            $sPayload = BinaryToString($bProcessedData, 1)
                            $bSuccess = True
                        EndIf
                    EndIf
                Else
                    ; Only decompress if it is currently compressed
                    If StringInStr($sDictHeader, "/Filter /FlateDecode") Then
                        $bProcessedData = _Zlib_Uncompress(StringToBinary($sPayload, 1))
                        If Not @error Then
                            ; Strip the filter flag and update the length to raw byte size
                            $sDictHeader = StringRegExpReplace($sDictHeader, "(?i)/Filter\s*/FlateDecode\s*", "")
                            $sDictHeader = StringRegExpReplace($sDictHeader, "(?i)/Length\s+\d+", "/Length " & BinaryLen($bProcessedData))
                            $sPayload = BinaryToString($bProcessedData, 1)
                            $bSuccess = True
                        EndIf
                    EndIf
                EndIf
                
                If $bSuccess Then
                    $sObj = $sDictHeader & $sPayload & $sTail
                    $iProcessedCount += 1
                EndIf
            EndIf
        EndIf
        
        $sNewRawContent &= $sObj
    Next
    
    DllClose($hZlib)
    
    If $iProcessedCount > 0 Then
        $sRawContent = $sNewRawContent
        Local $sAction = $bCompress ? "compressed" : "decompressed"
        MsgBox($MB_ICONINFORMATION, "Success", "Successfully " & $sAction & " " & $iProcessedCount & " object streams in memory. Save the file to apply.")
    Else
        MsgBox($MB_ICONINFORMATION, "Result", "No eligible streams found to modify.")
    EndIf
EndFunc

; ==========================================
; Targeted Export Function
; ==========================================
Func _ExportSelectedPages()
    Local $iSelCount = _GUICtrlListBox_GetSelCount($idListBox)
    If $iSelCount <= 0 Then Return MsgBox($MB_ICONEXCLAMATION, "Selection Error", "Please highlight the pages you want to export.")
    
    Local $sExportPath = FileSaveDialog("Export Selected Pages As", @DesktopDir, "PDF Files (*.pdf)", $FD_PATHMUSTEXIST)
    If @error Then Return
    
    Local $aExportObjects[0]
    For $i = 0 To _GUICtrlListBox_GetCount($idListBox) - 1
        If _GUICtrlListBox_GetSel($idListBox, $i) Then _ArrayAdd($aExportObjects, $aActivePageObjects[$i])
    Next
    
    _RebuildAndSavePDF($sExportPath, $aExportObjects)
EndFunc

; ==========================================
; Robust Import Function
; ==========================================
Func _ImportPagesAfterSelection()
    If $sFilePath = "" Then Return MsgBox($MB_ICONINFORMATION, "Notice", "Open a base PDF first.")
    
    Local $sImportFile = FileOpenDialog("Select PDF to Import", @DesktopDir, "PDF Files (*.pdf)", $FD_FILEMUSTEXIST)
    If @error Then Return
    
    Local $hFile = FileOpen($sImportFile, $FO_BINARY)
    Local $sImportContent = BinaryToString(FileRead($hFile), 1)
    FileClose($hFile)
    
    Local $iMaxHostID = 0
    Local $aHostObjs = StringRegExp($sRawContent, "\b(\d+)\s+0\s+obj", 3)
    If Not @error Then
        For $i = 0 To UBound($aHostObjs) - 1
            If Int($aHostObjs[$i]) > $iMaxHostID Then $iMaxHostID = Int($aHostObjs[$i])
        Next
    EndIf
    
    Local $iOffset = $iMaxHostID + 50 
    Local $aImportObjIDs = StringRegExp($sImportContent, "\b(\d+)\s+0\s+obj", 3)
    If @error Then Return MsgBox($MB_ICONSTOP, "Error", "No valid objects found in import.")
    
    _ArraySort($aImportObjIDs, 1)
    Local $sRemappedImport = $sImportContent
    
    For $i = 0 To UBound($aImportObjIDs) - 1
        Local $iOld = $aImportObjIDs[$i]
        Local $iNew = Int($iOld) + $iOffset
        $sRemappedImport = StringRegExpReplace($sRemappedImport, "(?m)^" & $iOld & "\s+0\s+obj", $iNew & " 0 obj")
        $sRemappedImport = StringRegExpReplace($sRemappedImport, "\b" & $iOld & "\s+0\s+R", $iNew & " 0 R")
    Next

    Local $aDirectPages = StringRegExp($sRemappedImport, "(?s)(\d+\s+\d+\s+obj\s*<<[^>]*?/Type\s*/Page\b.*?endobj)", 3)
    If @error Then Return MsgBox($MB_ICONSTOP, "Parsing Error", "Could not resolve individual /Page leaf nodes.")
    
    Local $aIndividualImportKids[0]
    For $i = 0 To UBound($aDirectPages) - 1
        Local $aObjID = StringRegExp($aDirectPages[$i], "^(\d+)\s+0\s+obj", 3)
        If Not @error Then _ArrayAdd($aIndividualImportKids, $aObjID[0] & " 0 R")
    Next
    
    Local $aImportedObjects = StringRegExp($sRemappedImport, "(?s)(\d+\s+\d+\s+obj.*?endobj)", 3)
    If Not @error Then
        For $i = 0 To UBound($aImportedObjects) - 1
            If Not StringInStr($aImportedObjects[$i], "/Type /Catalog") And Not StringInStr($aImportedObjects[$i], "/Type /Pages") Then
                $sRawContent &= @CRLF & $aImportedObjects[$i]
            EndIf
        Next
    EndIf
    
    Local $iTargetIdx = _GUICtrlListBox_GetCaretIndex($idListBox)
    If $iTargetIdx = -1 Then $iTargetIdx = _GUICtrlListBox_GetCount($idListBox) - 1
    
    _GUICtrlListBox_BeginUpdate($idListBox)
    For $i = 0 To UBound($aIndividualImportKids) - 1
        _GUICtrlListBox_InsertString($idListBox, "Imported (" & StringRegExpReplace($aIndividualImportKids[$i], "\s+0\s+R", "") & ")", $iTargetIdx + 1 + $i)
        _ArrayInsert($aActivePageObjects, $iTargetIdx + 1 + $i, $aIndividualImportKids[$i])
    Next
    _GUICtrlListBox_EndUpdate($idListBox)
    
    MsgBox($MB_ICONINFORMATION, "Success", UBound($aIndividualImportKids) & " pages linked directly via leaf nodes.")
EndFunc

; ==========================================
; Workspace State Handlers
; ==========================================
Func _RebuildAndSavePDF($sTargetFile, $aPagesToRender)
    Local $sOutputBuffer = "%PDF-1.4" & @CRLF
    Local $aObjects = StringRegExp($sRawContent, "(?s)(\d+\s+\d+\s+obj.*?endobj)", 3)
    
    Local $iPageTargetCount = UBound($aPagesToRender)
    Local $aOffsets[UBound($aObjects) + 50]
    Local $iObjIndex = 1
    
    Local $sNewKidsArray = _ArrayToString($aPagesToRender, " ")

    For $i = 0 To UBound($aObjects) - 1
        Local $sCurrentObj = $aObjects[$i]
        If StringInStr($sCurrentObj, "/Type /Pages") Or StringInStr($sCurrentObj, "/Type/Pages") Then
            $sCurrentObj = StringRegExpReplace($sCurrentObj, "(?i)/Kids\s*\[[^\]]*\]", "/Kids [" & $sNewKidsArray & "]")
            $sCurrentObj = StringRegExpReplace($sCurrentObj, "(?i)/Count\s+\d+", "/Count " & $iPageTargetCount)
        EndIf
        
        $aOffsets[$iObjIndex] = StringLen($sOutputBuffer)
        $sOutputBuffer &= $sCurrentObj & @CRLF
        $iObjIndex += 1
    Next

    Local $iInfoObjNum = $iObjIndex
    $aOffsets[$iInfoObjNum] = StringLen($sOutputBuffer)
    Local $sInfoObj = $iInfoObjNum & " 0 obj" & @CRLF & "<< /Title (" & $sTitle & ") /Producer (" & $sProducer & ") >>" & @CRLF & "endobj" & @CRLF
    $sOutputBuffer &= $sInfoObj
    
    Local $iXrefPos = StringLen($sOutputBuffer)
    Local $sXrefBlock = "xref" & @CRLF & "0 " & ($iInfoObjNum + 1) & @CRLF & "0000000000 65535 f " & @CRLF
    For $k = 1 To $iInfoObjNum
        $sXrefBlock &= StringFormat("%010d 00000 n ", $aOffsets[$k]) & @CRLF
    Next
    $sOutputBuffer &= $sXrefBlock
    
    $sOutputBuffer &= "trailer" & @CRLF & "<< /Size " & ($iInfoObjNum + 1) & " /Root 1 0 R /Info " & $iInfoObjNum & " 0 R >>" & @CRLF
    $sOutputBuffer &= "startxref" & @CRLF & $iXrefPos & @CRLF & "%%EOF"
    
    Local $hOut = FileOpen($sTargetFile, BitOR($FO_OVERWRITE, $FO_BINARY))
    If $hOut <> -1 Then
        FileWrite($hOut, StringToBinary($sOutputBuffer, 1))
        FileClose($hOut)
        MsgBox($MB_ICONINFORMATION, "Success", "PDF File successfully saved.")
    EndIf
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

Func _ParsePDF($sFile)
    Local $hFile = FileOpen($sFile, $FO_BINARY)
    $sRawContent = BinaryToString(FileRead($hFile), 1)
    FileClose($hFile)
    
    Local $aKidsMatch = StringRegExp($sRawContent, "(?i)/Kids\s*\[([^\]]*)\]", 3)
    If Not @error Then $aActivePageObjects = StringRegExp($aKidsMatch[0], "(\d+\s+\d+\s+R)", 3)
EndFunc

Func _PopulateListBox()
    _GUICtrlListBox_ResetContent($idListBox)
    _GUICtrlListBox_BeginUpdate($idListBox)
    For $i = 0 To UBound($aActivePageObjects) - 1
        _GUICtrlListBox_AddString($idListBox, "Page " & ($i + 1) & " (" & StringRegExpReplace($aActivePageObjects[$i], "\s+0\s+R", "") & ")")
    Next
    _GUICtrlListBox_EndUpdate($idListBox)
EndFunc

Func _ShowPropertiesWindow()
    MsgBox($MB_ICONINFORMATION, "Properties", "Property editor omitted for brevity in this snippet.")
EndFunc