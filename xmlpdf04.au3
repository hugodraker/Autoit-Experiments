#include <GUIConstantsEx.au3>
#include <EditConstants.au3>
#include <WindowsConstants.au3>
#include <FileConstants.au3>
#include <MsgBoxConstants.au3>

Global $g_sXMLPath = ""
Global $g_sXMLDir = ""

Global $g_aOffsets[1]
Global $g_iObjCount = 0

; ============================
; Helper functions for PDF
; ============================
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


; ============================
; GUI
; ============================
Example_Main()

Func Example_Main()
    Local $hGUI = GUICreate("XML to PDF (Multi-image + Description Demo)", 800, 600)

    Local $btnBrowse = GUICtrlCreateButton("Browse XML", 20, 20, 120, 30)
    Local $btnCreatePDF = GUICtrlCreateButton("Create PDF", 160, 20, 120, 30)

    Local $editXML = GUICtrlCreateEdit("", 20, 70, 760, 500, _
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


; ============================
; Handle Create PDF
; ============================
Func _HandleCreatePDF()
    Local $sXML = FileRead($g_sXMLPath)
    If @error Or $sXML = "" Then
        MsgBox($MB_ICONERROR, "XML Error", "Failed to read XML file.")
        Return
    EndIf

    Local $aDesc = StringRegExp($sXML, "<ImageDesc>(.*?)</ImageDesc>", 3)
    Local $aPaths = StringRegExp($sXML, "<ImagePath>(.*?)</ImagePath>", 3)

    If @error Or UBound($aDesc) = 0 Or UBound($aPaths) = 0 Then
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

    Local $iWidth = 612
    Local $iHeight = 792

    Local $sOutPDF = $g_sXMLDir & "\output_multi_desc.pdf"
    If _PDF_CreateMultiImageWithText($sOutPDF, $aImages, $aTexts, $iWidth, $iHeight) Then
        MsgBox($MB_ICONINFORMATION, "PDF Created", "PDF created:" & @CRLF & $sOutPDF)
    Else
        MsgBox($MB_ICONERROR, "PDF Error", "Failed to create PDF.")
    EndIf
EndFunc


; ============================
; Multi-image + description PDF engine
; ============================
Func _PDF_CreateMultiImageWithText($sOutputPDF, ByRef $aImages, ByRef $aTexts, $iWidth, $iHeight)
    Local $hOut = FileOpen($sOutputPDF, 18)
    If $hOut = -1 Then Return SetError(1, 0, 0)

    _PDF_ResetObjects()

    FileWrite($hOut, "%PDF-1.4" & @CRLF)

    ; Font object
    Local $iFontObj = _PDF_NewObj()
    _PDF_WriteObj($hOut, $iFontObj, _
        $iFontObj & " 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj")

    Local $iCount = UBound($aImages)
    Local $aPageObjs[$iCount]

    For $i = 0 To $iCount - 1
        ; Read JPEG
        Local $hImg = FileOpen($aImages[$i], 16)
        If $hImg = -1 Then
            FileClose($hOut)
            Return SetError(2, 0, 0)
        EndIf
        Local $bImg = FileRead($hImg)
        FileClose($hImg)
        Local $iImgLen = BinaryLen($bImg)

        ; Image object
        Local $iImgObj = _PDF_NewObj()
        $g_aOffsets[$iImgObj] = FileGetPos($hOut)
        Local $sImgDict = _
            $iImgObj & " 0 obj << /Type /XObject /Subtype /Image " & _
            "/Width " & $iWidth & " /Height " & $iHeight & " " & _
            "/ColorSpace /DeviceRGB /BitsPerComponent 8 " & _
            "/Filter /DCTDecode /Length " & $iImgLen & " >> stream" & @CRLF
        FileWrite($hOut, $sImgDict)
        FileWrite($hOut, $bImg)
        FileWrite($hOut, @CRLF & "endstream endobj" & @CRLF)

        ; Content: text + image
        Local $sText = StringReplace($aTexts[$i], ")", "\)")
        Local $sContent = _
            "BT /F1 18 Tf 50 740 Td (" & $sText & ") Tj ET" & @CRLF & _
            "q " & $iWidth & " 0 0 " & ($iHeight - 100) & " 0 0 cm /Im0 Do Q"

        Local $iContLen = StringLen($sContent)
        Local $iContObj = _PDF_NewObj()
        Local $sContBody = _
            $iContObj & " 0 obj << /Length " & $iContLen & " >> stream" & @CRLF & _
            $sContent & @CRLF & _
            "endstream endobj"
        _PDF_WriteObj($hOut, $iContObj, $sContBody)

        ; Page object
        Local $iPageObj = _PDF_NewObj()
        Local $sPageBody = _
            $iPageObj & " 0 obj << /Type /Page " & _
            "/MediaBox [0 0 " & $iWidth & " " & $iHeight & "] " & _
            "/Resources << /XObject << /Im0 " & $iImgObj & " 0 R >> " & _
            "/Font << /F1 " & $iFontObj & " 0 R >> >> " & _
            "/Contents " & $iContObj & " 0 R >> endobj"
        _PDF_WriteObj($hOut, $iPageObj, $sPageBody)

        $aPageObjs[$i] = $iPageObj
    Next

    ; Pages tree
    Local $iPagesObj = _PDF_NewObj()
    Local $sKids = ""
    For $i = 0 To $iCount - 1
        $sKids &= $aPageObjs[$i] & " 0 R "
    Next
    Local $sPagesBody = _
        $iPagesObj & " 0 obj << /Type /Pages /Kids [" & $sKids & "] /Count " & $iCount & " >> endobj"
    _PDF_WriteObj($hOut, $iPagesObj, $sPagesBody)

    ; Catalog
    Local $iCatalogObj = _PDF_NewObj()
    Local $sCatalogBody = _
        $iCatalogObj & " 0 obj << /Type /Catalog /Pages " & $iPagesObj & " 0 R >> endobj"
    _PDF_WriteObj($hOut, $iCatalogObj, $sCatalogBody)

    ; xref
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
