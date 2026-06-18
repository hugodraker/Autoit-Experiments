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
    Local $hGUI = GUICreate("XML to PDF (Raw PDF Image Embed Demo)", 800, 600)

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

    ; Find first <ImagePath>...</ImagePath>
    Local $aMatch = StringRegExp($sXML, "<ImagePath>(.*?)</ImagePath>", 3)
    If @error Or UBound($aMatch) = 0 Then
        MsgBox($MB_ICONERROR, "XML Error", "No <ImagePath> nodes found.")
        Return
    EndIf

    Local $sImageRel = $aMatch[0]
    Local $sImagePath = $g_sXMLDir & "\" & $sImageRel

    If Not FileExists($sImagePath) Then
        MsgBox($MB_ICONERROR, "Missing Image", "Image not found: " & $sImagePath)
        Return
    EndIf

    ; DEMO: assume JPEG and hardcode width/height
    ; For real use, parse JPEG header to get true dimensions.
    Local $iWidth = 612   ; pixels
    Local $iHeight = 792  ; pixels

    Local $sOutPDF = $g_sXMLDir & "\output_raw_embed.pdf"
    Local $iRet = _CreatePDFWithJPEG($sImagePath, $sOutPDF, $iWidth, $iHeight)
    If $iRet Then
        MsgBox($MB_ICONINFORMATION, "PDF Created", "PDF created:" & @CRLF & $sOutPDF)
    Else
        MsgBox($MB_ICONERROR, "PDF Error", "Failed to create PDF.")
    EndIf
EndFunc

    Func __AddObj(ByRef $sPDF, ByRef $aOffsets, ByRef $iObjCount, $iNum, $sObj)
        $aOffsets[$iNum] = StringLen($sPDF)
        $sPDF &= $sObj & @CRLF
        $iObjCount += 1
    EndFunc
	
; ============================
; Raw PDF with embedded JPEG
; ============================
Func _CreatePDFWithJPEG($sJpegPath, $sOutputPDF, $iWidth, $iHeight)
    ; Read JPEG bytes
    Local $hImg = FileOpen($sJpegPath, 16) ; binary
    If $hImg = -1 Then Return SetError(1, 0, 0)
    Local $bImg = FileRead($hImg)
    FileClose($hImg)

    Local $iImgLen = BinaryLen($bImg)

    ; Build PDF in memory up to the image stream
    Local $sPDF = ""
    Local $aOffsets[6] ; objects 0..5 (0 is free)

    ; helper
    Local $iObjCount = 0


    ; Header
    $sPDF &= "%PDF-1.4" & @CRLF

    ; 1 0 obj – Catalog
    __AddObj($sPDF, $aOffsets, $iObjCount, 1, _
        "1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj")

    ; 2 0 obj – Pages
    __AddObj($sPDF, $aOffsets, $iObjCount, 2, _
        "2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj")

    ; 3 0 obj – Page
    __AddObj($sPDF, $aOffsets, $iObjCount, 3, _
        "3 0 obj << /Type /Page /Parent 2 0 R " & _
        "/MediaBox [0 0 612 792] " & _
        "/Resources << /XObject << /Im0 5 0 R >> /ProcSet [/PDF /ImageC] >> " & _
        "/Contents 4 0 R >> endobj")

    ; 4 0 obj – Contents (draw image)
    Local $sContent = "q " & $iWidth & " 0 0 " & $iHeight & " 0 0 cm /Im0 Do Q"
    Local $iContentLen = StringLen($sContent)

    __AddObj($sPDF, $aOffsets, $iObjCount, 4, _
        "4 0 obj << /Length " & $iContentLen & " >> stream" & @CRLF & _
        $sContent & @CRLF & _
        "endstream endobj")

    ; 5 0 obj – Image XObject
    Local $sImgDict = _
        "5 0 obj << /Type /XObject /Subtype /Image " & _
        "/Width " & $iWidth & " /Height " & $iHeight & " " & _
        "/ColorSpace /DeviceRGB /BitsPerComponent 8 " & _
        "/Filter /DCTDecode /Length " & $iImgLen & " >> stream"

    $aOffsets[5] = StringLen($sPDF)
    $sPDF &= $sImgDict & @CRLF

    ; Write to file
    Local $hOut = FileOpen($sOutputPDF, 18) ; write binary
    If $hOut = -1 Then Return SetError(2, 0, 0)

    FileWrite($hOut, $sPDF)
    FileWrite($hOut, $bImg)
    FileWrite($hOut, @CRLF & "endstream endobj" & @CRLF)

    ; xref position
    Local $iXrefPos = FileGetPos($hOut)

    ; xref table
    Local $sXref = "xref" & @CRLF & "0 6" & @CRLF & _
        "0000000000 65535 f " & @CRLF

    For $i = 1 To 5
        Local $sOff = StringFormat("%010d", $aOffsets[$i])
        $sXref &= $sOff & " 00000 n " & @CRLF
    Next

    $sXref &= "trailer << /Size 6 /Root 1 0 R >>" & @CRLF & _
              "startxref" & @CRLF & _
              $iXrefPos & @CRLF & _
              "%%EOF"

    FileWrite($hOut, $sXref)
    FileClose($hOut)

    Return 1
EndFunc
