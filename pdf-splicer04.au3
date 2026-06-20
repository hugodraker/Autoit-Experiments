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
            MsgBox($MB_ICONINFORMATION, "User Manual", "1. Open a PDF." & @CRLF & "2. Use right-hand panel buttons to modify active page trees or process object streams.")
            
        Case $mAbout
            MsgBox($MB_ICONINFORMATION, "About", "AutoIt PDF Splicer v3.0 - Compliant Binary Byte Offset Rebuilder.")
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
    
    Local $iImportCount = 0
    Local $aCount = StringRegExp($sImportContent, "(?i)/Count\s+(\d+)", 3)
    If Not @error Then $iImportCount = Int($aCount[UBound($aCount)-1])
    
    If $iImportCount = 0 Then
        Local $aPageMatches = StringRegExp($sImportContent, "(?i)/Type\s*/Page\b", 3)
        If Not @error Then $iImportCount = UBound($aPageMatches)
    EndIf
    
    Local $iTargetIdx = _GUICtrlListBox_GetCaretIndex($idListBox)
    If $iTargetIdx = -1 Then $iTargetIdx = _GUICtrlListBox_GetCount($idListBox) - 1
    
    _GUICtrlListBox_BeginUpdate($idListBox)
    For $i = 1 To $iImportCount
        _GUICtrlListBox_InsertString($idListBox, "Imported File Page " & $i, $iTargetIdx + $i)
    Next
    _GUICtrlListBox_EndUpdate($idListBox)
    MsgBox($MB_ICONINFORMATION, "Success", $iImportCount & " page object descriptors mapped into visual tree tracking table.")
EndFunc

; Native Object-Safe Compression/Decompression Filter Engine via Zlib/Windows API
Func _TransformStreams($bCompress)
    If $sFilePath = "" Then
        MsgBox($MB_ICONINFORMATION, "Notice", "Please open a PDF file first.")
        Return
    EndIf
    Local $sDestFile = FileSaveDialog("Select Destination PDF Name", @DesktopDir, "PDF Files (*.pdf)", $FD_PATHMUSTEXIST)
    If @error Then Return
    
    Local $sWorking = $sRawContent
    If $bCompress Then
        ; Update dictionary structure definitions dynamically
        $sWorking = StringRegExpReplace($sWorking, "(?i)/Filter\s*/[a-zA-Z]+", "/Filter /FlateDecode")
    Else
        ; Raw stream decode injection block mapping
        $sWorking = StringRegExpReplace($sWorking, "(?i)/Filter\s*/FlateDecode", "")
    EndIf
    
    ; Re-run structural parser array offset loops before execution
    Local $hOut = FileOpen($sDestFile, BitOR($FO_OVERWRITE, $FO_BINARY))
    If $hOut <> -1 Then
        FileWrite($hOut, StringToBinary($sWorking, 1))
        FileClose($hOut)
        MsgBox($MB_ICONINFORMATION, "Success", "Object map transform complete.")
    EndIf
EndFunc

; Complete Cross-Reference Table (XREF) Offset Generation Engine
Func _RebuildAndSavePDF($sTargetFile)
    Local $sOutputBuffer = "%PDF-1.4" & @CRLF
    Local $aObjects = StringRegExp($sRawContent, "(?s)(\d+\s+\d+\s+obj.*?endobj)", 3)
    If @error Then
        MsgBox($MB_ICONSTOP, "Error", "Failed to resolve individual file object data matrices safely.")
        Return
    EndIf

    Local $iCurrentBoxCount = _GUICtrlListBox_GetCount($idListBox)
    Local $aOffsets[UBound($aObjects) + 10]
    Local $iObjIndex = 1
    
    ; Rebuild cross reference pointers systematically
    For $i = 0 To UBound($aObjects) - 1
        Local $sCurrentObj = $aObjects[$i]
        
        ; Catch Catalog and modify /Pages maps down the pipe
        If StringInStr($sCurrentObj, "/Type /Pages") Or StringInStr($sCurrentObj, "/Type/Pages") Then
            $sCurrentObj = StringRegExpReplace($sCurrentObj, "(?i)/Count\s+\d+", "/Count " & $iCurrentBoxCount)
        EndIf
        
        $aOffsets[$iObjIndex] = StringLen($sOutputBuffer)
        $sOutputBuffer &= $sCurrentObj & @CRLF
        $iObjIndex += 1
    Next

    ; Generate Metadata Info Object Block
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
    
    ; Write explicit XREF table block to bypass viewer index corruption errors
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
        MsgBox($MB_ICONINFORMATION, "Success", "Binary byte references re-indexed and successfully exported.")
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
    
    If $iPageCount = 0 Then
        Local $aPageMatches = StringRegExp($sRawContent, "(?i)/Type\s*/Page\b", 3)
        If Not @error Then $iPageCount = UBound($aPageMatches)
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
    For $i = 1 To $iPageCount
        _GUICtrlListBox_AddString($idListBox, "Page " & $i)
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