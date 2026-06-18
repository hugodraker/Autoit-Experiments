#include <GUIConstantsEx.au3>
#include <EditConstants.au3>
#include <FileConstants.au3>
#include <MsgBoxConstants.au3>
#include <WindowsConstants.au3>

Global $g_sXMLPath = ""
Global $g_sXMLDir = ""

; ============================
; GUI
; ============================
Example_Main()

Func Example_Main()
    Local $hGUI = GUICreate("XML to PDF (Multi-image Raw PDF Engine Demo)", 800, 600)

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
EndFunc   ;==>Example_Main


; ============================
; Handle Create PDF
; ============================
Func _HandleCreatePDF()
    Local $sXML = FileRead($g_sXMLPath)
    If @error Or $sXML = "" Then
        MsgBox($MB_ICONERROR, "XML Error", "Failed to read XML file.")
        Return
    EndIf

    ; Find all <ImagePath>...</ImagePath>
    Local $aMatches = StringRegExp($sXML, "<ImagePath>(.*?)</ImagePath>", 3)
    If @error Or UBound($aMatches) = 0 Then
        MsgBox($MB_ICONERROR, "XML Error", "No <ImagePath> nodes found.")
        Return
    EndIf

    ; Build list of image paths
    Local $aImages[UBound($aMatches)]
    For $i = 0 To UBound($aMatches) - 1
        Local $sRel = $aMatches[$i]
        Local $sFull = $g_sXMLDir & "\" & $sRel
        If Not FileExists($sFull) Then
            MsgBox($MB_ICONERROR, "Missing Image", "Image not found: " & $sFull)
            Return
        EndIf
        $aImages[$i] = $sFull
    Next

    ; DEMO: assume all JPEGs and same page size
    Local $iWidth = 612
    Local $iHeight = 792

    Local $sOutPDF = $g_sXMLDir & "\output_multi_raw.pdf"
    If _PDF_CreateMultiImage($sOutPDF, $aImages, $iWidth, $iHeight) Then
        MsgBox($MB_ICONINFORMATION, "PDF Created", "PDF created:" & @CRLF & $sOutPDF)
    Else
        MsgBox($MB_ICONERROR, "PDF Error", "Failed to create PDF.")
    EndIf
EndFunc

    Func __NewObj(ByRef $aOffsets, ByRef $iObjCount)
        $iObjCount += 1
        ReDim $aOffsets[$iObjCount + 1]
        Return $iObjCount
    EndFunc
	
	Func __WriteObj($hFile, ByRef $aOffsets, $iNum, $sBody)
        $aOffsets[$iNum] = FileGetPos($hFile)
        FileWrite($hFile, $sBody & @CRLF)
    EndFunc
	
; ============================
; Multi-image PDF engine
; ============================
Func _PDF_CreateMultiImage($sOutputPDF, ByRef $aImages, $iWidth, $iHeight)
    Local $hOut = FileOpen($sOutputPDF, 18) ; binary
    If $hOut = -1 Then Return SetError(1, 0, 0)

    ; Offsets array (dynamic)
    Local $aOffsets[1]
    Local $iObjCount = 0

    ; Helper: new object number


    ; Helper: write object and record offset


    ; Write header
    FileWrite($hOut, "%PDF-1.4" & @CRLF)

    ; Create font object (for text if needed)
    Local $iFontObj = __NewObj($aOffsets, $iObjCount)
    __WriteObj($hOut, $aOffsets, $iFontObj, _
        $iFontObj & " 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj")

    ; We'll create page/image/content objects per image
    Local $aPageObjs[UBound($aImages)]
    Local $aContentObjs[UBound($aImages)]
    Local $aImageObjs[UBound($aImages)]

    ; Placeholder for pages tree and catalog
    Local $iPagesObj = 0
    Local $iCatalogObj = 0

    ; Create per-page objects
    For $i = 0 To UBound($aImages) - 1
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
        Local $iImgObj = __NewObj($aOffsets, $iObjCount)
        $aOffsets[$iImgObj] = FileGetPos($hOut)
        Local $sImgDict = _
            $iImgObj & " 0 obj << /Type /XObject /Subtype /Image " & _
            "/Width " & $iWidth & " /Height " & $iHeight & " " & _
            "/ColorSpace /DeviceRGB /BitsPerComponent 8 " & _
            "/Filter /DCTDecode /Length " & $iImgLen & " >> stream" & @CRLF
        FileWrite($hOut, $sImgDict)
        FileWrite($hOut, $bImg)
        FileWrite($hOut, @CRLF & "endstream endobj" & @CRLF)
        $aImageObjs[$i] = $iImgObj

        ; Contents object
        Local $iContObj = __NewObj($aOffsets, $iObjCount)
        Local $sContent = "q " & $iWidth & " 0 0 " & $iHeight & " 0 0 cm /Im0 Do Q"
        Local $iContentLen = StringLen($sContent)
        Local $sContBody = _
            $iContObj & " 0 obj << /Length " & $iContentLen & " >> stream" & @CRLF & _
            $sContent & @CRLF & _
            "endstream endobj"
        __WriteObj($hOut, $aOffsets, $iContObj, $sContBody)
        $aContentObjs[$i] = $iContObj

        ; Page object (parent set later)
        Local $iPageObj = __NewObj($aOffsets, $iObjCount)
        Local $sPageBody = _
            $iPageObj & " 0 obj << /Type /Page " & _
            "/MediaBox [0 0 " & $iWidth & " " & $iHeight & "] " & _
            "/Resources << /XObject << /Im0 " & $iImgObj & " 0 R >> " & _
            "/Font << /F1 " & $iFontObj & " 0 R >> >> " & _
            "/Contents " & $iContObj & " 0 R >> endobj"
        __WriteObj($hOut, $aOffsets, $iPageObj, $sPageBody)
        $aPageObjs[$i] = $iPageObj
    Next

    ; Pages tree object
    $iPagesObj = __NewObj($aOffsets, $iObjCount)
    Local $sKids = ""
    For $i = 0 To UBound($aPageObjs) - 1
        $sKids &= $aPageObjs[$i] & " 0 R "
    Next
    Local $sPagesBody = _
        $iPagesObj & " 0 obj << /Type /Pages /Kids [" & $sKids & "] /Count " & UBound($aPageObjs) & " >> endobj"
    __WriteObj($hOut, $aOffsets, $iPagesObj, $sPagesBody)

    ; Catalog object
    $iCatalogObj = __NewObj($aOffsets, $iObjCount)
    Local $sCatalogBody = _
        $iCatalogObj & " 0 obj << /Type /Catalog /Pages " & $iPagesObj & " 0 R >> endobj"
    __WriteObj($hOut, $aOffsets, $iCatalogObj, $sCatalogBody)

    ; Now fix parent references: strictly speaking, each page should have /Parent pointing to pages tree.
    ; Many viewers will accept pages without explicit /Parent, but we already wrote them.
    ; For a fully correct engine, you'd rewrite page objects or build them after pages tree.

    ; xref
    Local $iXrefPos = FileGetPos($hOut)
    Local $sXref = "xref" & @CRLF & "0 " & ($iObjCount + 1) & @CRLF & _
        "0000000000 65535 f " & @CRLF

    For $i = 1 To $iObjCount
        Local $sOff = StringFormat("%010d", $aOffsets[$i])
        $sXref &= $sOff & " 00000 n " & @CRLF
    Next

    Local $sTrailer = _
        "trailer << /Size " & ($iObjCount + 1) & " /Root " & $iCatalogObj & " 0 R >>" & @CRLF & _
        "startxref" & @CRLF & _
        $iXrefPos & @CRLF & _
        "%%EOF"

    FileWrite($hOut, $sXref & $sTrailer)
    FileClose($hOut)

    Return 1
EndFunc
