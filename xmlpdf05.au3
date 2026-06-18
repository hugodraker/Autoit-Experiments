#include <GUIConstantsEx.au3>
#include <EditConstants.au3>
#include <WindowsConstants.au3>
#include <FileConstants.au3>
#include <MsgBoxConstants.au3>
#include <GDIPlus.au3>

Global $g_sXMLPath = ""
Global $g_sXMLDir = ""

Global $g_aOffsets[1]
Global $g_iObjCount = 0

Global $g_lstCompression

; ============================================================
; PDF OBJECT HELPERS
; ============================================================
Func _PDF_ResetObjects()
    ReDim $g_aOffsets[1]
    $g_iObjCount = 0
EndFunc

Func _PDF_NewObj()
    $g_iObjCount += 1
    ReDim $g_aOffsets[$g_iObjCount + 1]
    Return $g_iObjCount
EndFunc

Func _PDF_WriteObj($hFile, $iNum, $sBody)
    $g_aOffsets[$iNum] = FileGetPos($hFile)
    FileWrite($hFile, $sBody & @CRLF)
EndFunc

; ============================================================
; TEXT WRAPPING + ESCAPING
; ============================================================
Func _WrapText($sText, $iMaxChars)
    Local $aWords = StringSplit($sText, " ", 2)
    Local $aLines[1]
    Local $sLine = ""
    Local $iCount = 0

    For $i = 0 To UBound($aWords) - 1
        Local $sWord = $aWords[$i]
        If StringLen($sLine) + 1 + StringLen($sWord) > $iMaxChars Then
            ReDim $aLines[$iCount + 1]
            $aLines[$iCount] = $sLine
            $iCount += 1
            $sLine = $sWord
        Else
            If $sLine = "" Then
                $sLine = $sWord
            Else
                $sLine &= " " & $sWord
            EndIf
        EndIf
    Next

    If $sLine <> "" Then
        ReDim $aLines[$iCount + 1]
        $aLines[$iCount] = $sLine
    EndIf

    Return $aLines
EndFunc

Func _EscapePDFText($sText)
    $sText = StringReplace($sText, "\", "\\")
    $sText = StringReplace($sText, "(", "\(")
    $sText = StringReplace($sText, ")", "\)")
    Return $sText
EndFunc

; ============================================================
; GUI
; ============================================================
Example_Main()

Func Example_Main()
    Local $hGUI = GUICreate("XML → PDF Generator (Images + Wrapped Text + Compression)", 900, 600)

    Local $btnBrowse = GUICtrlCreateButton("Browse XML", 20, 20, 120, 30)
    Local $btnCreatePDF = GUICtrlCreateButton("Create PDF", 160, 20, 120, 30)

    GUICtrlCreateLabel("Compression:", 320, 10, 100, 20)
    $g_lstCompression = GUICtrlCreateList("", 320, 30, 120, 80)
    GUICtrlSetData($g_lstCompression, "0%|20%|40%|60%|80%|100%", "100%")

    Local $editXML = GUICtrlCreateEdit("", 20, 120, 860, 450, _
        BitOR($ES_MULTILINE, $ES_AUTOVSCROLL, $WS_VSCROLL))

    GUISetState(@SW_SHOW)

    While 1
        Switch GUIGetMsg()
            Case $GUI_EVENT_CLOSE
                Exit

            Case $btnBrowse
                Local $sFile = FileOpenDialog("Select XML File", @ScriptDir, "XML (*.xml)", 1)
                If Not @error Then
                    $g_sXMLPath = $sFile
                    $g_sXMLDir = StringRegExpReplace($sFile, "\\[^\\]+$", "")
                    Local $sContent = FileRead($sFile)
                    GUICtrlSetData($editXML, $sContent)
                EndIf

            Case $btnCreatePDF
                If $g_sXMLPath = "" Then
                    MsgBox($MB_ICONWARNING, "No XML", "Please select an XML file first.")
                Else
                    _HandleCreatePDF()
                EndIf
        EndSwitch
    WEnd
EndFunc

; ============================================================
; HANDLE PDF CREATION
; ============================================================
Func _HandleCreatePDF()
    Local $sXML = FileRead($g_sXMLPath)
    If @error Or $sXML = "" Then
        MsgBox($MB_ICONERROR, "XML Error", "Failed to read XML file.")
        Return
    EndIf

    Local $aDesc = StringRegExp($sXML, "<ImageDesc>(.*?)</ImageDesc>", 3)
    Local $aPaths = StringRegExp($sXML, "<ImagePath>(.*?)</ImagePath>", 3)

    If UBound($aDesc) = 0 Or UBound($aPaths) = 0 Then
        MsgBox($MB_ICONERROR, "XML Error", "Missing <ImageDesc> or <ImagePath> tags.")
        Return
    EndIf

    If UBound($aDesc) <> UBound($aPaths) Then
        MsgBox($MB_ICONERROR, "XML Error", "Mismatched number of <ImageDesc> and <ImagePath> tags.")
        Return
    EndIf

    Local $iCount = UBound($aDesc)
    Local $aImages[$iCount]
    Local $aTexts[$iCount]

    For $i = 0 To $iCount - 1
        $aTexts[$i] = $aDesc[$i]
        $aImages[$i] = $g_sXMLDir & "\" & $aPaths[$i]

        If Not FileExists($aImages[$i]) Then
            MsgBox($MB_ICONERROR, "Missing Image", "Image not found: " & $aImages[$i])
            Return
        EndIf
    Next

    Local $sComp = GUICtrlRead($g_lstCompression)
    Local $iComp = Int(StringTrimRight($sComp, 1))
    If $iComp <= 0 Then $iComp = 10

    Local $sOutPDF = $g_sXMLDir & "\output_final.pdf"

    If _PDF_CreateMultiImageWithText($sOutPDF, $aImages, $aTexts, 612, 792, $iComp) Then
        MsgBox($MB_ICONINFORMATION, "PDF Created", "PDF created:" & @CRLF & $sOutPDF)
    Else
        MsgBox($MB_ICONERROR, "PDF Error", "Failed to create PDF.")
    EndIf
EndFunc

; ============================================================
; MAIN PDF ENGINE
; ============================================================
Func _PDF_CreateMultiImageWithText($sOutputPDF, ByRef $aImages, ByRef $aTexts, $iPageW, $iPageH, $iCompPercent)
    Local $hOut = FileOpen($sOutputPDF, 18)
    If $hOut = -1 Then Return SetError(1, 0, 0)

    _PDF_ResetObjects()
    FileWrite($hOut, "%PDF-1.4" & @CRLF)

    _GDIPlus_Startup()

    ; FONT OBJECT
    Local $iFontObj = _PDF_NewObj()
    _PDF_WriteObj($hOut, $iFontObj, _
        $iFontObj & " 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj")

    Local $iCount = UBound($aImages)
    Local $aPageObjs[$iCount]

    For $i = 0 To $iCount - 1

        ; --------------------------------------------------------
        ; LOAD + SCALE IMAGE (NATIVE COMPRESSION)
        ; --------------------------------------------------------
        Local $hImg = _GDIPlus_ImageLoadFromFile($aImages[$i])
        If $hImg = 0 Then
            _GDIPlus_Shutdown()
            FileClose($hOut)
            Return SetError(2, 0, 0)
        EndIf

        Local $iOrigW = _GDIPlus_ImageGetWidth($hImg)
        Local $iOrigH = _GDIPlus_ImageGetHeight($hImg)

        Local $fScaleComp = $iCompPercent / 100
        Local $iScaledW = Int($iOrigW * $fScaleComp)
        Local $iScaledH = Int($iOrigH * $fScaleComp)
        If $iScaledW < 1 Then $iScaledW = 1
        If $iScaledH < 1 Then $iScaledH = 1

        Local $hScaled = _GDIPlus_ImageResize($hImg, $iScaledW, $iScaledH)
        Local $sTempImg = @TempDir & "\pdf_img_" & $i & ".jpg"
        _GDIPlus_ImageSaveToFile($hScaled, $sTempImg)

        _GDIPlus_ImageDispose($hImg)
        _GDIPlus_ImageDispose($hScaled)

        Local $hFileImg = FileOpen($sTempImg, 16)
        If $hFileImg = -1 Then
            _GDIPlus_Shutdown()
            FileClose($hOut)
            Return SetError(3, 0, 0)
        EndIf
        Local $bImg = FileRead($hFileImg)
        FileClose($hFileImg)
        Local $iImgLen = BinaryLen($bImg)

        ; --------------------------------------------------------
        ; IMAGE OBJECT
        ; --------------------------------------------------------
        Local $iImgObj = _PDF_NewObj()
        $g_aOffsets[$iImgObj] = FileGetPos($hOut)

        Local $sImgDict = _
            $iImgObj & " 0 obj << /Type /XObject /Subtype /Image " & _
            "/Width " & $iScaledW & " /Height " & $iScaledH & " " & _
            "/ColorSpace /DeviceRGB /BitsPerComponent 8 " & _
            "/Filter /DCTDecode /Length " & $iImgLen & " >> stream" & @CRLF

        FileWrite($hOut, $sImgDict)
        FileWrite($hOut, $bImg)
        FileWrite($hOut, @CRLF & "endstream endobj" & @CRLF)

        ; --------------------------------------------------------
        ; WRAPPED TEXT BLOCK
        ; --------------------------------------------------------
        Local $sDesc = _EscapePDFText($aTexts[$i])
        Local $aLines = _WrapText($sDesc, 60)

        Local $sTextStream = "BT /F1 18 Tf 50 740 Td" & @CRLF
        For $j = 0 To UBound($aLines) - 1
            Local $sLine = _EscapePDFText($aLines[$j])
            If $j = 0 Then
                $sTextStream &= "(" & $sLine & ") Tj" & @CRLF
            Else
                $sTextStream &= "0 -22 Td (" & $sLine & ") Tj" & @CRLF
            EndIf
        Next
        $sTextStream &= "ET" & @CRLF

        ; --------------------------------------------------------
        ; LAYOUT: FORCE IMAGE BELOW TEXT, FULLY ON PAGE
        ; --------------------------------------------------------
        Local $iLineHeight = 22
        Local $iTextHeight = UBound($aLines) * $iLineHeight

        Local $iTopMargin = 100
        Local $iSpacing = 50
        Local $iBottomMargin = 50

        Local $iMaxImgH = $iPageH - ($iTopMargin + $iTextHeight + $iSpacing + $iBottomMargin)
        If $iMaxImgH < 1 Then $iMaxImgH = 1

        Local $iAvailW = $iPageW - 100
        Local $fScaleW = $iAvailW / $iScaledW
        Local $fScaleH = $iMaxImgH / $iScaledH
        Local $fScale = $fScaleW
        If $fScaleH < $fScale Then $fScale = $fScaleH

        Local $fDisplayW = $iScaledW * $fScale
        Local $fDisplayH = $iScaledH * $fScale

        Local $fImgY = $iPageH - $iTopMargin - $iTextHeight - $fDisplayH
        If $fImgY < $iBottomMargin Then $fImgY = $iBottomMargin

        Local $sImgStream = _
            "q " & $fDisplayW & " 0 0 " & $fDisplayH & " 50 " & $fImgY & " cm /Im0 Do Q" & @CRLF

        ; --------------------------------------------------------
        ; CONTENT STREAM
        ; --------------------------------------------------------
        Local $sContent = $sTextStream & $sImgStream
        Local $iContLen = StringLen($sContent)

        Local $iContObj = _PDF_NewObj()
        Local $sContBody = _
            $iContObj & " 0 obj << /Length " & $iContLen & " >> stream" & @CRLF & _
            $sContent & @CRLF & _
            "endstream endobj"
        _PDF_WriteObj($hOut, $iContObj, $sContBody)

        ; --------------------------------------------------------
        ; PAGE OBJECT
        ; --------------------------------------------------------
        Local $iPageObj = _PDF_NewObj()
        Local $sPageBody = _
            $iPageObj & " 0 obj << /Type /Page " & _
            "/MediaBox [0 0 " & $iPageW & " " & $iPageH & "] " & _
            "/Resources << /XObject << /Im0 " & $iImgObj & " 0 R >> " & _
            "/Font << /F1 " & $iFontObj & " 0 R >> >> " & _
            "/Contents " & $iContObj & " 0 R >> endobj"

        _PDF_WriteObj($hOut, $iPageObj, $sPageBody)
        $aPageObjs[$i] = $iPageObj
    Next

    _GDIPlus_Shutdown()

    ; ============================================================
    ; PAGES TREE
    ; ============================================================
    Local $iPagesObj = _PDF_NewObj()
    Local $sKids = ""
    For $i = 0 To $iCount - 1
        $sKids &= $aPageObjs[$i] & " 0 R "
    Next

    Local $sPagesBody = _
        $iPagesObj & " 0 obj << /Type /Pages /Kids [" & $sKids & "] /Count " & $iCount & " >> endobj"
    _PDF_WriteObj($hOut, $iPagesObj, $sPagesBody)

    ; ============================================================
    ; CATALOG
    ; ============================================================
    Local $iCatalogObj = _PDF_NewObj()
    Local $sCatalogBody = _
        $iCatalogObj & " 0 obj << /Type /Catalog /Pages " & $iPagesObj & " 0 R >> endobj"
    _PDF_WriteObj($hOut, $iCatalogObj, $sCatalogBody)

    ; ============================================================
    ; XREF + TRAILER
    ; ============================================================
    Local $iXrefPos = FileGetPos($hOut)
    Local $sXref = "xref" & @CRLF & "0 " & ($g_iObjCount + 1) & @CRLF & _
        "0000000000 65535 f " & @CRLF

    For $i = 1 To $g_iObjCount
        Local $sOff = StringFormat("%010d", $g_aOffsets[$i])
        $sXref &= $sOff & " 00000 n " & @CRLF
    Next

    Local $sTrailer = _
        "trailer << /Size " & ($g_iObjCount + 1) & " /Root " & $iCatalogObj & " 0 R >>" & @CRLF & _
        "startxref" & @CRLF & _
        $iXrefPos & @CRLF & _
        "%%EOF"

    FileWrite($hOut, $sXref & $sTrailer)
    FileClose($hOut)

    Return 1
EndFunc
