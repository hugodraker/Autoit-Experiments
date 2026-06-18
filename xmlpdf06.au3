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
; TABLE PARSING
; ============================================================
Func _ParseTableToArray($sTable)
    Local $aRowsRaw = StringRegExp($sTable, "(?is)<tr>(.*?)</tr>", 3)
    If @error Or UBound($aRowsRaw) = 0 Then Return SetError(1, 0, 0)

    Local $iRows = UBound($aRowsRaw)
    Local $iMaxCols = 0
    Local $i, $j

    ; First pass: find max columns
    For $i = 0 To $iRows - 1
        Local $aCells = StringRegExp($aRowsRaw[$i], "(?is)<td>(.*?)</td>", 3)
        If Not @error Then
            If UBound($aCells) > $iMaxCols Then $iMaxCols = UBound($aCells)
        EndIf
    Next

    If $iMaxCols = 0 Then Return SetError(2, 0, 0)

    Local $aTable[$iRows][$iMaxCols]
    For $i = 0 To $iRows - 1
        For $j = 0 To $iMaxCols - 1
            $aTable[$i][$j] = ""
        Next
    Next

    ; Second pass: fill cells
    For $i = 0 To $iRows - 1
        Local $aCells = StringRegExp($aRowsRaw[$i], "(?is)<td>(.*?)</td>", 3)
        If Not @error Then
            For $j = 0 To UBound($aCells) - 1
                Local $sCell = StringStripWS($aCells[$j], 7)
                $aTable[$i][$j] = $sCell
            Next
        EndIf
    Next

    Return $aTable
EndFunc

Func _BuildTableStream(ByRef $aTable, $iPageW, $iStartY, ByRef $fTableHeight)
    Local $iRows = UBound($aTable, 1)
    Local $iCols = UBound($aTable, 2)
    Local $i, $j

    ; Auto-size columns based on text length
    Local $aColWidths[$iCols]
    For $j = 0 To $iCols - 1
        $aColWidths[$j] = 0
    Next

    For $j = 0 To $iCols - 1
        Local $iMaxLen = 0
        For $i = 0 To $iRows - 1
            Local $sCell = $aTable[$i][$j]
            Local $iLen = StringLen($sCell)
            If $iLen > $iMaxLen Then $iMaxLen = $iLen
        Next
        ; Approximate width: 7 points per char + padding
        $aColWidths[$j] = $iMaxLen * 7 + 20
    Next

    ; Total width and scaling to fit page width (612)
    Local $fTotalW = 0
    For $j = 0 To $iCols - 1
        $fTotalW += $aColWidths[$j]
    Next

    Local $fMaxTableW = $iPageW ; full page width as requested
    Local $fScale = 1.0
    If $fTotalW > $fMaxTableW Then
        $fScale = $fMaxTableW / $fTotalW
    EndIf

    For $j = 0 To $iCols - 1
        $aColWidths[$j] *= $fScale
    Next

    ; Row height (single-line cells)
    Local $fRowH = 18
    Local $fTableH = $iRows * $fRowH
    $fTableHeight = $fTableH

    ; Table origin (x=0 to use full width)
    Local $fX0 = 0
    Local $fY0 = $iStartY

    Local $sStream = ""

    ; Draw grid and text
    ; Use 12pt font
    $sStream &= "BT /F1 12 Tf ET" & @CRLF

    Local $fY = $fY0
    For $i = 0 To $iRows - 1
        Local $fX = $fX0

        ; Horizontal lines (top of row)
        $sStream &= $fX0 & " " & $fY & " m " & ($fX0 + $fMaxTableW) & " " & $fY & " l S" & @CRLF

        ; Cells in this row
        For $j = 0 To $iCols - 1
            Local $fW = $aColWidths[$j]

            ; Vertical lines
            $sStream &= $fX & " " & $fY & " m " & $fX & " " & ($fY - $fRowH) & " l S" & @CRLF

            ; Text (single line, left padding 4, baseline -12)
            Local $sCell = _EscapePDFText($aTable[$i][$j])
            Local $fTextX = $fX + 4
            Local $fTextY = $fY - 13

            $sStream &= "BT /F1 12 Tf " & $fTextX & " " & $fTextY & " Td (" & $sCell & ") Tj ET" & @CRLF

            $fX += $fW
        Next

        ; Right border of last cell
        $sStream &= $fX & " " & $fY & " m " & $fX & " " & ($fY - $fRowH) & " l S" & @CRLF

        $fY -= $fRowH
    Next

    ; Bottom horizontal line
    $sStream &= $fX0 & " " & $fY & " m " & ($fX0 + $fMaxTableW) & " " & $fY & " l S" & @CRLF

    Return $sStream
EndFunc

; ============================================================
; GUI
; ============================================================
Example_Main()

Func Example_Main()
    Local $hGUI = GUICreate("XML → PDF Generator (Images + Text + Tables + Compression)", 900, 600)

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
    Local $aTables = StringRegExp($sXML, "(?is)<table>(.*?)</table>", 3)

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
    Local $aTablesPerPage[$iCount]

    Local $i
    For $i = 0 To $iCount - 1
        $aTexts[$i] = $aDesc[$i]
        $aImages[$i] = $g_sXMLDir & "\" & $aPaths[$i]
        If Not FileExists($aImages[$i]) Then
            MsgBox($MB_ICONERROR, "Missing Image", "Image not found: " & $aImages[$i])
            Return
        EndIf

        If UBound($aTables) > $i Then
            $aTablesPerPage[$i] = $aTables[$i]
        Else
            $aTablesPerPage[$i] = ""
        EndIf
    Next

    Local $sComp = GUICtrlRead($g_lstCompression)
    Local $iComp = Int(StringTrimRight($sComp, 1))
    If $iComp <= 0 Then $iComp = 10

    Local $sOutPDF = $g_sXMLDir & "\output_with_tables.pdf"

    If _PDF_CreateMultiImageWithTextAndTables($sOutPDF, $aImages, $aTexts, $aTablesPerPage, 612, 792, $iComp) Then
        MsgBox($MB_ICONINFORMATION, "PDF Created", "PDF created:" & @CRLF & $sOutPDF)
    Else
        MsgBox($MB_ICONERROR, "PDF Error", "Failed to create PDF.")
    EndIf
EndFunc

; ============================================================
; MAIN PDF ENGINE (TEXT + TABLE + IMAGE)
; ============================================================
Func _PDF_CreateMultiImageWithTextAndTables($sOutputPDF, ByRef $aImages, ByRef $aTexts, ByRef $aTablesPerPage, $iPageW, $iPageH, $iCompPercent)
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

    Local $i
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
        Local $j
        For $j = 0 To UBound($aLines) - 1
            Local $sLine = _EscapePDFText($aLines[$j])
            If $j = 0 Then
                $sTextStream &= "(" & $sLine & ") Tj" & @CRLF
            Else
                $sTextStream &= "0 -22 Td (" & $sLine & ") Tj" & @CRLF
            EndIf
        Next
        $sTextStream &= "ET" & @CRLF

        Local $iLineHeight = 22
        Local $iTextHeight = UBound($aLines) * $iLineHeight

        ; --------------------------------------------------------
        ; TABLE (IF PRESENT)
        ; --------------------------------------------------------
        Local $sTableStream = ""
        Local $fTableHeight = 0
        Local $sTableRaw = $aTablesPerPage[$i]

        If $sTableRaw <> "" Then
            Local $aTable = _ParseTableToArray($sTableRaw)
            If Not @error Then
                ; Table starts below text with 20pt spacing
                Local $fTableStartY = $iPageH - 100 - $iTextHeight - 20
                $sTableStream = _BuildTableStream($aTable, $iPageW, $fTableStartY, $fTableHeight)
            EndIf
        EndIf

        ; --------------------------------------------------------
        ; LAYOUT: IMAGE BELOW TEXT + TABLE, FULLY ON PAGE
        ; --------------------------------------------------------
        Local $iTopMargin = 100
        Local $iSpacing = 50
        Local $iBottomMargin = 50

        Local $iTotalTextTableHeight = $iTextHeight + $fTableHeight + 20
        Local $iMaxImgH = $iPageH - ($iTopMargin + $iTotalTextTableHeight + $iSpacing + $iBottomMargin)
        If $iMaxImgH < 1 Then $iMaxImgH = 1

        Local $iAvailW = $iPageW - 100
        Local $fScaleW = $iAvailW / $iScaledW
        Local $fScaleH = $iMaxImgH / $iScaledH
        Local $fScale = $fScaleW
        If $fScaleH < $fScale Then $fScale = $fScaleH

        Local $fDisplayW = $iScaledW * $fScale
        Local $fDisplayH = $iScaledH * $fScale

        Local $fImgY = $iPageH - $iTopMargin - $iTotalTextTableHeight - $fDisplayH
        If $fImgY < $iBottomMargin Then $fImgY = $iBottomMargin

        Local $sImgStream = _
            "q " & $fDisplayW & " 0 0 " & $fDisplayH & " 50 " & $fImgY & " cm /Im0 Do Q" & @CRLF

        ; --------------------------------------------------------
        ; CONTENT STREAM
        ; --------------------------------------------------------
        Local $sContent = $sTextStream & $sTableStream & $sImgStream
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
