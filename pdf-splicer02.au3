#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <GuiListBox.au3>
#include <MsgBoxConstants.au3>
#include <FileConstants.au3>

; Global State Variables
Global $sFilePath = ""
Global $iPageCount = 0
Global $sTitle = "", $sSubject = "", $sCreator = "", $sProducer = "", $sKeywords = ""
Global $fWidthPoints = 0.0, $fHeightPoints = 0.0

; Create Main GUI (Resizable)
Global $hMainGUI = GUICreate("Native PDF Page Reader", 500, 400, -1, -1, BitOR($WS_MINIMIZEBOX, $WS_SIZEBOX, $WS_THICKFRAME, $WS_MAXIMIZEBOX))

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

; Create Controls (ListBox on the left, Delete button on the right)
Global $idListBox = GUICtrlCreateList("", 0, 0, 380, 400, BitOR($LBS_MULTIPLESEL, $WS_VSCROLL, $WS_BORDER))
; Lock the listbox to the top, bottom, and left borders, but let the right side expand
GUICtrlSetResizing($idListBox, BitOR($GUI_DOCKLEFT, $GUI_DOCKTOP, $GUI_DOCKBOTTOM))

Global $idDeleteBtn = GUICtrlCreateButton("Delete Page(s)", 390, 10, 100, 35)
; Lock the button to the top and right borders so it stays on the right side when resized
GUICtrlSetResizing($idDeleteBtn, BitOR($GUI_DOCKRIGHT, $GUI_DOCKTOP, $GUI_DOCKWIDTH, $GUI_DOCKHEIGHT))

; Register the Windows Message for resizing to manually keep elements perfectly aligned
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
                WinSetTitle($hMainGUI, "", "Native PDF Page Reader - " & $sFilePath)
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
                    _WritePDFProperties($sSavePath)
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
            
        Case $mManual
            MsgBox($MB_ICONINFORMATION, "User Manual", "1. Use File -> Open to load a PDF natively." & @CRLF & "2. Select multiple pages inside the listbox view." & @CRLF & "3. Click 'Delete Page(s)' to remove them from your active workspace list.")
            
        Case $mAbout
            MsgBox($MB_ICONINFORMATION, "About", "Native PDF Structural Reader" & @CRLF & "Built using AutoIt 3.3.")
    EndSwitch
WEnd

; Handles deletion mechanics out of the listbox selection matrix
Func _DeleteSelectedPages()
    Local $iSelCount = _GUICtrlListBox_GetSelCount($idListBox)
    If $iSelCount <= 0 Then
        MsgBox($MB_ICONEXCLAMATION, "Selection Error", "Please select one or more pages from the listbox grid first.")
        Return
    EndIf
    
    Local $iConfirm = MsgBox(BitOR($MB_YESNO, $MB_ICONQUESTION), "Confirm Deletion", "Are you sure you want to delete the " & $iSelCount & " selected page(s) from the list?")
    If $iConfirm <> $IDYES Then Return
    
    _GUICtrlListBox_BeginUpdate($idListBox)
    ; Loop backwards when deleting index arrays so the changing counts don't skip items
    For $i = _GUICtrlListBox_GetCount($idListBox) - 1 To 0 Step -1
        If _GUICtrlListBox_GetSel($idListBox, $i) Then
            _GUICtrlListBox_DeleteString($idListBox, $i)
        EndIf
    Next
    _GUICtrlListBox_EndUpdate($idListBox)
EndFunc

; Dynamic Layout Management Callback for Resizable UI Space
Func WM_SIZE($hWnd, $iMsg, $wParam, $lParam)
    #forceref $hWnd, $iMsg, $wParam
    Local $iWidth = BitAND($lParam, 0xFFFF)
    Local $iHeight = BitShift($lParam, 16)
    
    ; Ensure elements scale correctly relative to each other 
    GUICtrlSetPos($idListBox, 0, 0, $iWidth - 120, $iHeight)
    GUICtrlSetPos($idDeleteBtn, $iWidth - 110, 10, 100, 35)
    Return $GUI_RUNDEFMSG
EndFunc

Func _ParsePDF($sFile)
    Local $hFile = FileOpen($sFile, $FO_BINARY)
    If $hFile = -1 Then Return
    Local $bData = FileRead($hFile)
    FileClose($hFile)
    
    Local $sContent = BinaryToString($bData, 1)
    
    $iPageCount = 0
    $sTitle = ""
    $sSubject = ""
    $sCreator = ""
    $sProducer = ""
    $sKeywords = ""
    $fWidthPoints = 612.0  
    $fHeightPoints = 792.0 

    Local $aCount = StringRegExp($sContent, "(?i)/Count\s+(\d+)", 3)
    If Not @error Then
        For $i = 0 To UBound($aCount) - 1
            If Int($aCount[$i]) > $iPageCount Then $iPageCount = Int($aCount[$i])
        Next
    EndIf
    
    If $iPageCount = 0 Then
        Local $aPageMatches = StringRegExp($sContent, "(?i)/Type\s*/Page\b", 3)
        If Not @error Then $iPageCount = UBound($aPageMatches)
    EndIf

    Local $aBox = StringRegExp($sContent, "\[\s*0\s+0\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s*\]", 3)
    If Not @error Then
        $fWidthPoints = Number($aBox[0])
        $fHeightPoints = Number($aBox[1])
    Else
        Local $aMediaBox = StringRegExp($sContent, "(?i)/MediaBox\s*\[\s*(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s*(\d+(?:\.\d+)?)\s*(\d+(?:\.\d+)?)\s*\]", 3)
        If Not @error And UBound($aMediaBox) >= 4 Then
            $fWidthPoints = Number($aMediaBox[2]) - Number($aMediaBox[0])
            $fHeightPoints = Number($aMediaBox[3]) - Number($aMediaBox[1])
        EndIf
    EndIf

    $sTitle = _ExtractMetadataField($sContent, "Title")
    $sSubject = _ExtractMetadataField($sContent, "Subject")
    $sCreator = _ExtractMetadataField($sContent, "Creator")
    $sProducer = _ExtractMetadataField($sContent, "Producer")
    $sKeywords = _ExtractMetadataField($sContent, "Keywords")
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
    Local $hPropGUI = GUICreate("PDF Property Editor", 460, 340, -1, -1, -1, -1, $hMainGUI)
    
    GUICtrlCreateLabel("Title:", 10, 15, 80, 20)
    Local $idInTitle = GUICtrlCreateInput($sTitle, 100, 12, 340, 20)
    
    GUICtrlCreateLabel("Subject:", 10, 45, 80, 20)
    Local $idInSubj = GUICtrlCreateInput($sSubject, 100, 42, 340, 20)
    
    GUICtrlCreateLabel("Creator:", 10, 75, 80, 20)
    Local $idInCreat = GUICtrlCreateInput($sCreator, 100, 72, 340, 20)
    
    GUICtrlCreateLabel("Producer:", 10, 105, 80, 20)
    Local $idInProd = GUICtrlCreateInput($sProducer, 100, 102, 340, 20)
    
    GUICtrlCreateLabel("Keywords:", 10, 135, 80, 20)
    Local $idInKey = GUICtrlCreateInput($sKeywords, 100, 132, 340, 20)
    
    GUICtrlCreateLabel("Total Pages:", 10, 170, 80, 20)
    GUICtrlCreateLabel($iPageCount, 100, 170, 340, 20)
    
    Local $fWInches = $fWidthPoints / 72.0
    Local $fHInches = $fHeightPoints / 72.0
    Local $fWMm = $fWInches * 25.4
    Local $fHMm = $fHInches * 25.4
    
    GUICtrlCreateLabel("Page Size (Pts):", 10, 200, 90, 20)
    GUICtrlCreateLabel(Round($fWidthPoints, 1) & " x " & Round($fHeightPoints, 1) & " pt", 100, 200, 340, 20)
    
    GUICtrlCreateLabel("Page Size (In):", 10, 225, 90, 20)
    GUICtrlCreateLabel(Round($fWInches, 2) & " x " & Round($fHInches, 2) & " in", 100, 225, 340, 20)
    
    GUICtrlCreateLabel("Page Size (mm):", 10, 250, 90, 20)
    GUICtrlCreateLabel(Round($fWMm, 1) & " x " & Round($fHMm, 1) & " mm", 100, 250, 340, 20)
    
    Local $idSaveBtn = GUICtrlCreateButton("&Save Changes", 160, 295, 120, 30)
    
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
            $sKeywords = GUICtrlRead($idInKey)
            ExitLoop
        EndIf
    WEnd
    
    GUIDelete($hPropGUI)
    GUISwitch($hMainGUI)
EndFunc

Func _WritePDFProperties($sTargetFile)
    Local $hFile = FileOpen($sFilePath, $FO_BINARY)
    If $hFile = -1 Then Return
    Local $bData = FileRead($hFile)
    FileClose($hFile)
    
    Local $sContent = BinaryToString($bData, 1)
    
    Local $sNewInfoObj = @CRLF & ">>>>" & @CRLF & " trailer" & @CRLF & "<< /Info << "
    If $sTitle <> "" Then $sNewInfoObj &= "/Title (" & $sTitle & ") "
    If $sSubject <> "" Then $sNewInfoObj &= "/Subject (" & $sSubject & ") "
    If $sCreator <> "" Then $sNewInfoObj &= "/Creator (" & $sCreator & ") "
    If $sProducer <> "" Then $sNewInfoObj &= "/Producer (" & $sProducer & ") "
    If $sKeywords <> "" Then $sNewInfoObj &= "/Keywords (" & $sKeywords & ") "
    $sNewInfoObj &= ">> >>" & @CRLF
    
    Local $iEofPos = StringInStr($sContent, "%%EOF", 0, -1)
    If $iEofPos > 0 Then
        $sContent = StringLeft($sContent, $iEofPos - 1) & $sNewInfoObj & "%%EOF"
    Else
        $sContent &= $sNewInfoObj & "%%EOF"
    EndIf
    
    Local $hOut = FileOpen($sTargetFile, BitOR($FO_OVERWRITE, $FO_BINARY))
    If $hOut <> -1 Then
        FileWrite($hOut, StringToBinary($sContent, 1))
        FileClose($hOut)
        MsgBox($MB_ICONINFORMATION, "Success", "PDF updated via incremental block structure.")
    EndIf
EndFunc