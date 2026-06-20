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
Global $aActivePageObjects[1] ; Stores specific object references for the tracked pages

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

Global $mHelp = GUICtrlCreateMenu("&Help")
Global $mManual = GUICtrlCreateMenuItem("&User Manual", $mHelp)
Global $mAbout = GUICtrlCreateMenuItem("&About", $mHelp)

; Create Controls
Global $idListBox = GUICtrlCreateList("", 0, 0, 380, 430, BitOR($LBS_MULTIPLESEL, $WS_VSCROLL, $WS_BORDER))
GUICtrlSetResizing($idListBox, BitOR($GUI_DOCKLEFT, $GUI_DOCKTOP, $GUI_DOCKBOTTOM))

Global $idDeleteBtn = GUICtrlCreateButton("Delete Page(s)", 395, 10, 110, 35)
GUICtrlSetResizing($idDeleteBtn, BitOR($GUI_DOCKRIGHT, $GUI_DOCKTOP, $GUI_DOCKWIDTH, $GUI_DOCKHEIGHT))

Global $idExportBtn = GUICtrlCreateButton("Export Pages", 395, 55, 110, 35)
GUICtrlSetResizing($idExportBtn, BitOR($GUI_DOCKRIGHT, $GUI_DOCKTOP, $GUI_DOCKWIDTH, $GUI_DOCKHEIGHT))

Global $idImportBtn = GUICtrlCreateButton("Import Pages", 395, 100, 110, 35)
GUICtrlSetResizing($idImportBtn, BitOR($GUI_DOCKRIGHT, $GUI_DOCKTOP, $GUI_DOCKWIDTH, $GUI_DOCKHEIGHT))

Global $idDecompressBtn = GUICtrlCreateButton("Decompress", 395, 145, 110, 35)
GUICtrlSetResizing($idDecompressBtn, BitOR($GUI_DOCKRIGHT, $GUI_DOCKTOP, $GUI_DOCKWIDTH, $GUI_DOCKHEIGHT))

Global $idCompressBtn = GUICtrlCreateButton("Compress", 395, 190, 110, 35)
GUICtrlSetResizing($idCompressBtn, BitOR($GUI_DOCKRIGHT, $GUI_DOCKTOP, $GUI_DOCKWIDTH, $GUI_DOCKHEIGHT))

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
            If $sFilePath = "" Then
                MsgBox($MB_ICONINFORMATION, "Notice", "No open PDF file to save.")
            Else
                Local $sSavePath = $sFilePath
                If $nMsg = $mSaveAs Then
                    $sSavePath = FileSaveDialog("Save PDF As", @DesktopDir, "PDF Files (*.pdf)", $FD_PATHMUSTEXIST)
                EndIf
                If $sSavePath <> "" Then
                    _RebuildAndSavePDF($sSavePath)
                EndIf
            EndIf

        Case $mEditProps
            If $sFilePath = "" Then
                MsgBox($MB_ICONINFORMATION, "Notice", "Please open a PDF file first.")
            Else
                _ShowPropertiesWindow()
            EndIf
            
        Case $idDeleteBtn
            _DeleteSelectedPages()

        Case $idExportBtn
            _ExportSelectedPages()

        Case $idImportBtn
            _ImportPagesAfterSelection()

        Case $idDecompressBtn
            _TransformStreams(False) 

        Case $idCompressBtn
            _TransformStreams(True)  
            
        Case $mManual
            MsgBox($MB_ICONINFORMATION, "User Manual", "1. Open a PDF." & @CRLF & "2. Select pages to remove, or choose an insert marker to append external structures.")
            
        Case $mAbout
            MsgBox($MB_ICONINFORMATION, "About", "AutoIt PDF Splicer v4.1 - ID Namespace Collision Resolver.")
    EndSwitch
WEnd

Func _DeleteSelectedPages()
    Local $iSelCount = _GUICtrlListBox_GetSelCount($idListBox)
    If $iSelCount <= 0 Then
        MsgBox($MB_ICONEXCLAMATION, "Selection Error", "Please select pages to remove.")
        Return
    EndIf
    Local $iConfirm = MsgBox(BitOR($MB_YESNO, $MB_ICONQUESTION), "Confirm Deletion", "Remove " & $iSelCount & " page(s) from workspace layout?")
    If $iConfirm <> $IDYES Then Return
    
    _GUICtrlListBox_BeginUpdate($idListBox)
    For $i = _GUICtrlListBox_GetCount($idListBox) - 1 To 0 Step -1
        If _GUICtrlListBox_GetSel($idListBox, $i) Then
            _GUICtrlListBox_DeleteString($idListBox, $i)
            _ArrayDelete($aActivePageObjects, $i)
        EndIf
    Next
    _GUICtrlListBox_EndUpdate($idListBox)
EndFunc

Func _ExportSelectedPages()
    Local $iSelCount = _GUICtrlListBox_GetSelCount($idListBox)
    If $iSelCount <= 0 Then
        MsgBox($MB_ICONEXCLAMATION, "Selection Error", "Please select pages to export first.")
        Return
    EndIf
    Local $sExportPath = FileSaveDialog("Export Selected Pages As", @DesktopDir, "PDF Files (*.pdf)", $FD_PATHMUSTEXIST)
    If @error Then Return
    
    _RebuildAndSavePDF($sExportPath)
EndFunc

Func _ImportPagesAfterSelection()
    If $sFilePath = "" Then
        MsgBox($MB_ICONINFORMATION, "Notice", "Please open a base PDF file first.")
        Return
    EndIf
    Local $sImportFile = FileOpenDialog("Select PDF to Import", @DesktopDir, "PDF Files (*.pdf)", $FD_FILEMUSTEXIST)
    If @error Then Return
    
    Local $hFile = FileOpen($sImportFile, $FO_BINARY)
    Local $bData = FileRead($hFile)
    FileClose($hFile)
    Local $sImportContent = BinaryToString($bData, 1)
    
    ; 1. Find the highest Object ID in the current host file to avoid collisions
    Local $iMaxHostID = 0
    Local $aHostObjs = StringRegExp($sRawContent, "\b(\d+)\s+0\s+obj", 3)
    If Not @error Then
        For $i = 0 To UBound($aHostObjs) - 1
            If Int($aHostObjs[$i]) > $iMaxHostID Then $iMaxHostID = Int($aHostObjs[$i])
        Next
    EndIf
    
    ; Safe ID offset ceiling for incoming objects
    Local $iOffset = $iMaxHostID + 100 
    
    ; 2. Extract all object IDs from the imported file
    Local $aImportObjIDs = StringRegExp($sImportContent, "\b(\d+)\s+0\s+obj", 3)
    If @error Then
        MsgBox($MB_ICONSTOP, "Parsing Error", "Could not locate valid objects inside the import file.")
        Return
    EndIf
    
    ; 3. Sort IDs Descending: CRITICAL so replacing "1" doesn't corrupt "12"
    _ArraySort($aImportObjIDs, 1)
    
    Local $sRemappedImport = $sImportContent
    
    ; 4. Shift the imported file's namespace 
    For $i = 0 To UBound($aImportObjIDs) - 1
        Local $iOld = $aImportObjIDs[$i]
        Local $iNew = Int($iOld) + $iOffset
        ; Shift object headers
        $sRemappedImport = StringRegExpReplace($sRemappedImport, "(?m)^" & $iOld & "\s+0\s+obj", $iNew & " 0 obj")
        ; Shift object reference pointers inside streams/dictionaries
        $sRemappedImport = StringRegExpReplace($sRemappedImport, "\b" & $iOld & "\s+0\s+R", $iNew & " 0 R")
    Next

    ; 5. Locate the newly re-mapped /Kids references
    Local $aImportKids = StringRegExp($sRemappedImport, "(?i)/Kids\s*\[([^\]]*)\]", 3)
    If @error Then
        MsgBox($MB_ICONSTOP, "Parsing Error", "Could not locate /Kids tree in the remapped import file.")
        Return
    EndIf
    Local $aIndividualImportKids = StringRegExp($aImportKids[0], "(\d+\s+\d+\s+R)", 3)
    
    ; 6. Append the re-mapped raw objects into the active host workspace
    Local $aImportedObjects = StringRegExp($sRemappedImport, "(?s)(\d+\s+\d+\s+obj.*?endobj)", 3)
    If Not @error Then
        For $i = 0 To UBound($aImportedObjects) - 1
            If Not StringInStr($aImportedObjects[$i], "/Type /Catalog") And Not StringInStr($aImportedObjects[$i], "/Type /Pages") Then
                $sRawContent &= @CRLF & $aImportedObjects[$i]
            EndIf
        Next
    EndIf
    
    ; 7. Update UI and Trackers
    Local $iTargetIdx = _GUICtrlListBox_GetCaretIndex($idListBox)
    If $iTargetIdx = -1 Then $iTargetIdx = _GUICtrlListBox_GetCount($idListBox) - 1
    
    _GUICtrlListBox_BeginUpdate($idListBox)
    For $i = 0 To UBound($aIndividualImportKids) - 1
        Local $sCleanID = StringRegExpReplace($aIndividualImportKids[$i], "\s+0\s+R", "")
        _GUICtrlListBox_InsertString($idListBox, "Imported Page (" & $sCleanID & ")", $iTargetIdx + 1 + $i)
        _ArrayInsert($aActivePageObjects, $iTargetIdx + 1 + $i, $aIndividualImportKids[$i])
    Next
    _GUICtrlListBox_EndUpdate($idListBox)
    
    MsgBox($MB_ICONINFORMATION, "Success", UBound($aIndividualImportKids) & " namespace-shifted pages safely linked.")
EndFunc

Func _TransformStreams($bCompress)
    If $sFilePath = "" Then
        MsgBox($MB_ICONINFORMATION, "Notice", "Please open a PDF file first.")
        Return
    EndIf
    Local $sDestFile = FileSaveDialog("Select Destination PDF Name", @DesktopDir, "PDF Files (*.pdf)", $FD_PATHMUSTEXIST)
    If @error Then Return
    
    Local $sWorking = $sRawContent
    If $bCompress Then
        $sWorking = StringRegExpReplace($sWorking, "(?i)/Filter\s*/[a-zA-Z]+", "/Filter /FlateDecode")
    Else
        $sWorking = StringRegExpReplace($sWorking, "(?i)/Filter\s*/FlateDecode", "")
    EndIf
    
    Local $hOut = FileOpen($sDestFile, BitOR($FO_OVERWRITE, $FO_BINARY))
    If $hOut <> -1 Then
        FileWrite($hOut, StringToBinary($sWorking, 1))
        FileClose($hOut)
        MsgBox($MB_ICONINFORMATION, "Success", "Object stream transformation complete.")
    EndIf
EndFunc

Func _RebuildAndSavePDF($sTargetFile)
    Local $sOutputBuffer = "%PDF-1.4" & @CRLF
    Local $aObjects = StringRegExp($sRawContent, "(?s)(\d+\s+\d+\s+obj.*?endobj)", 3)
    If @error Then
        MsgBox($MB_ICONSTOP, "Error", "Failed to resolve structural source blocks.")
        Return
    EndIf

    Local $iCurrentBoxCount = _GUICtrlListBox_GetCount($idListBox)
    Local $aOffsets[UBound($aObjects) + 50]
    Local $iObjIndex = 1
    
    Local $sNewKidsArray = ""
    For $p = 0 To UBound($aActivePageObjects) - 1
        $sNewKidsArray &= $aActivePageObjects[$p] & " "
    Next
    $sNewKidsArray = StringStripWS($sNewKidsArray, 3)

    For $i = 0 To UBound($aObjects) - 1
        Local $sCurrentObj = $aObjects[$i]
        If StringInStr($sCurrentObj, "/Type /Pages") Or StringInStr($sCurrentObj, "/Type/Pages") Then
            $sCurrentObj = StringRegExpReplace($sCurrentObj, "(?i)/Kids\s*\[[^\]]*\]", "/Kids [" & $sNewKidsArray & "]")
            $sCurrentObj = StringRegExpReplace($sCurrentObj, "(?i)/Count\s+\d+", "/Count " & $iCurrentBoxCount)
        EndIf
        
        $aOffsets[$iObjIndex] = StringLen($sOutputBuffer)
        $sOutputBuffer &= $sCurrentObj & @CRLF
        $iObjIndex += 1
    Next

    Local $iInfoObjNum = $iObjIndex
    $aOffsets[$iInfoObjNum] = StringLen($sOutputBuffer)
    Local $sInfoObj = $iInfoObjNum & " 0 obj" & @CRLF & "<< "
    If $sTitle <> "" Then $sInfoObj &= "/Title (" & $sTitle & ") "
    If $sSubject <> "" Then $sInfoObj &= "/Subject (" & $sSubject & ") "
    If $sCreator <> "" Then $sInfoObj &= "/Creator (" & $sCreator & ") "
    If $sProducer <> "" Then $sInfoObj &= "/Producer (" & $sProducer & ") "
    If $sAuthor <> "" Then $sInfoObj &= "/Author (" & $sAuthor & ") "
    If $sKeywords <> "" Then $sInfoObj &= "/Keywords (" & $sKeywords & ") "
    $sInfoObj &= ">>" & @CRLF & "endobj" & @CRLF
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
        $sRawContent = $sOutputBuffer 
        $iPageCount = $iCurrentBoxCount
        _ParsePDF($sTargetFile) 
        _PopulateListBox()
        MsgBox($MB_ICONINFORMATION, "Success", "PDF File successfully saved with synchronized namespaces.")
    EndIf
EndFunc

Func WM_SIZE($hWnd, $iMsg, $wParam, $lParam)
    #forceref $hWnd, $iMsg, $wParam
    Local $iWidth = BitAND($lParam, 0xFFFF)
    Local $iHeight = BitShift($lParam, 16)
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
    If $hFile = -1 Then Return
    Local $bData = FileRead($hFile)
    FileClose($hFile)
    
    $sRawContent = BinaryToString($bData, 1)
    
    $iPageCount = 0
    $sTitle = ""
    $sSubject = ""
    $sCreator = ""
    $sProducer = ""
    $sKeywords = ""
    $sAuthor = ""

    Local $aCount = StringRegExp($sRawContent, "(?i)/Count\s+(\d+)", 3)
    If Not @error Then
        For $i = 0 To UBound($aCount) - 1
            If Int($aCount[$i]) > $iPageCount Then $iPageCount = Int($aCount[$i])
        Next
    EndIf
    
    Local $aKidsMatch = StringRegExp($sRawContent, "(?i)/Kids\s*\[([^\]]*)\]", 3)
    If Not @error Then
        $aActivePageObjects = StringRegExp($aKidsMatch[0], "(\d+\s+\d+\s+R)", 3)
        $iPageCount = UBound($aActivePageObjects)
    EndIf

    Local $aBox = StringRegExp($sRawContent, "\[\s*0\s+0\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s*\]", 3)
    If Not @error Then
        $fWidthPoints = Number($aBox[0])
        $fHeightPoints = Number($aBox[1])
    Else
        Local $aMediaBox = StringRegExp($sRawContent, "(?i)/MediaBox\s*\[\s*(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s*(\d+(?:\.\d+)?)\s*(\d+(?:\.\d+)?)\s*\]", 3)
        If Not @error And UBound($aMediaBox) >= 4 Then
            $fWidthPoints = Number($aMediaBox[2]) - Number($aMediaBox[0])
            $fHeightPoints = Number($aMediaBox[3]) - Number($aMediaBox[1])
        EndIf
    EndIf

    $sTitle = _ExtractMetadataField($sRawContent, "Title")
    $sSubject = _ExtractMetadataField($sRawContent, "Subject")
    $sCreator = _ExtractMetadataField($sRawContent, "Creator")
    $sProducer = _ExtractMetadataField($sRawContent, "Producer")
    $sKeywords = _ExtractMetadataField($sRawContent, "Keywords")
    $sAuthor = _ExtractMetadataField($sRawContent, "Author")
EndFunc

Func _ExtractMetadataField($sText, $sField)
    Local $aMatch = StringRegExp($sText, "(?i)/" & $sField & "\s*\((.*?)\)", 3)
    If Not @error Then Return $aMatch[UBound($aMatch)-1]
    Return ""
EndFunc

Func _PopulateListBox()
    _GUICtrlListBox_ResetContent($idListBox)
    If $iPageCount = 0 Then Return
    _GUICtrlListBox_BeginUpdate($idListBox)
    For $i = 0 To UBound($aActivePageObjects) - 1
        Local $sCleanID = StringRegExpReplace($aActivePageObjects[$i], "\s+0\s+R", "")
        _GUICtrlListBox_AddString($idListBox, "Page " & ($i + 1) & " (" & $sCleanID & ")")
    Next
    _GUICtrlListBox_EndUpdate($idListBox)
EndFunc

Func _ShowPropertiesWindow()
    Local $hPropGUI = GUICreate("PDF Property Editor", 460, 365, -1, -1, -1, -1, $hMainGUI)
    
    GUICtrlCreateLabel("Title:", 10, 15, 80, 20)
    Local $idInTitle = GUICtrlCreateInput($sTitle, 100, 12, 340, 20)
    
    GUICtrlCreateLabel("Subject:", 10, 45, 80, 20)
    Local $idInSubj = GUICtrlCreateInput($sSubject, 100, 42, 340, 20)
    
    GUICtrlCreateLabel("Creator:", 10, 75, 80, 20)
    Local $idInCreat = GUICtrlCreateInput($sCreator, 100, 72, 340, 20)
    
    GUICtrlCreateLabel("Producer:", 10, 105, 80, 20)
    Local $idInProd = GUICtrlCreateInput($sProducer, 100, 102, 340, 20)
    
    GUICtrlCreateLabel("Author:", 10, 135, 80, 20)
    Local $idInAuth = GUICtrlCreateInput($sAuthor, 100, 132, 340, 20)
    
    GUICtrlCreateLabel("Keywords:", 10, 165, 80, 20)
    Local $idInKey = GUICtrlCreateInput($sKeywords, 100, 162, 340, 20)
    
    GUICtrlCreateLabel("Total Pages:", 10, 195, 80, 20)
    GUICtrlCreateLabel(_GUICtrlListBox_GetCount($idListBox), 100, 195, 340, 20)
    
    Local $fWInches = $fWidthPoints / 72.0
    Local $fHInches = $fHeightPoints / 72.0
    Local $fWMm = $fWInches * 25.4
    Local $fHMm = $fHInches * 25.4
    
    GUICtrlCreateLabel("Page Size (Pts):", 10, 225, 90, 20)
    GUICtrlCreateLabel(Round($fWidthPoints, 1) & " x " & Round($fHeightPoints, 1) & " pt", 100, 225, 340, 20)
    
    GUICtrlCreateLabel("Page Size (In):", 10, 255, 90, 20)
    GUICtrlCreateLabel(Round($fWInches, 2) & " x " & Round($fHInches, 2) & " in", 100, 255, 340, 20)
    
    GUICtrlCreateLabel("Page Size (mm):", 10, 285, 90, 20)
    GUICtrlCreateLabel(Round($fWMm, 1) & " x " & Round($fHMm, 1) & " mm", 100, 285, 340, 20)
    
    Local $idSaveBtn = GUICtrlCreateButton("&Apply", 160, 325, 120, 30)
    
    GUISetState(@SW_SHOW, $hPropGUI)
    GUISwitch($hPropGUI)
    
    While 1
        Local $pMsg = GUIGetMsg()
        If $pMsg = $GUI_EVENT_CLOSE Then ExitLoop
        
        If $pMsg = $idSaveBtn Then
            $sTitle = GUICtrlRead($idInTitle)
            $sSubject = GUICtrlRead($idInSubj)
            $sCreator = GUICtrlRead($idInCreat)
            $sProducer = GUICtrlRead($idInProd)
            $sAuthor = GUICtrlRead($idInAuth)
            $sKeywords = GUICtrlRead($idInKey)
            ExitLoop
        EndIf
    WEnd
    
    GUIDelete($hPropGUI)
    GUISwitch($hMainGUI)
EndFunc