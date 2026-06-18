#include <GUIConstantsEx.au3>
#include <EditConstants.au3>
#include <FileConstants.au3>
#include <MsgBoxConstants.au3>
#include <Array.au3>
#include <XMLDomWrapper.au3>
#include <WindowsConstants.au3>

Global $g_sXMLPath = ""
Global $g_sXMLDir = ""

; ---------------------------
; Create GUI
; ---------------------------
$hGUI = GUICreate("XML to PDF Tool", 700, 500)

$btnBrowse = GUICtrlCreateButton("Browse XML", 20, 20, 120, 30)
$btnCreatePDF = GUICtrlCreateButton("Create PDF", 160, 20, 120, 30)

$editXML = GUICtrlCreateEdit("", 20, 70, 660, 400, BitOR($ES_MULTILINE, $ES_AUTOVSCROLL, $WS_VSCROLL))

GUISetState(@SW_SHOW)

; ---------------------------
; Main Loop
; ---------------------------
While 1
    Switch GUIGetMsg()
        Case $GUI_EVENT_CLOSE
            Exit

        Case $btnBrowse
            _BrowseXML()

        Case $btnCreatePDF
            _CreatePDF()
    EndSwitch
WEnd


; ---------------------------
; Browse for XML file
; ---------------------------
Func _BrowseXML()
    Local $sFile = FileOpenDialog("Select XML File", @ScriptDir, "XML (*.xml)", 1)
    If @error Then Return

    $g_sXMLPath = $sFile
    $g_sXMLDir = StringRegExpReplace($sFile, "\\[^\\]+$", "")

    Local $sContent = FileRead($sFile)
    GUICtrlSetData($editXML, $sContent)
EndFunc


; ---------------------------
; REAL PDF CREATION FUNCTION
; ---------------------------
Func _CreatePDF()
    If $g_sXMLPath = "" Then
        MsgBox($MB_ICONWARNING, "No XML", "Please select an XML file first.")
        Return
    EndIf

    ; Load XML
    _XMLLoad($g_sXMLPath)
    If @error Then
        MsgBox($MB_ICONERROR, "XML Error", "Failed to load XML.")
        Return
    EndIf

    ; Extract <ImagePath> nodes
    Local $aNodes = _XMLGetNodes("//ImagePath")
    If @error Then
        MsgBox($MB_ICONERROR, "XML Error", "No <ImagePath> nodes found.")
        Return
    EndIf

    Local $aImages[UBound($aNodes)]
    For $i = 0 To UBound($aNodes) - 1
        Local $sImage = _XMLGetValue($aNodes[$i])
        $aImages[$i] = $g_sXMLDir & "\" & $sImage

        If Not FileExists($aImages[$i]) Then
            MsgBox($MB_ICONERROR, "Missing File", "Image not found: " & $aImages[$i])
            Return
        EndIf
    Next

    ; Build command for ImageMagick
    Local $sOutputPDF = $g_sXMLDir & "\output.pdf"
    Local $sCmd = ""

    For $i = 0 To UBound($aImages) - 1
        $sCmd &= '"' & $aImages[$i] & '" '
    Next

    $sCmd &= '"' & $sOutputPDF & '"'

    ; Run ImageMagick convert
    Local $iPID = Run('magick convert ' & $sCmd, "", @SW_HIDE, $RUN_CREATE_NEW_CONSOLE)
    ProcessWaitClose($iPID)

    MsgBox($MB_ICONINFORMATION, "PDF Created", "PDF saved as:" & @CRLF & $sOutputPDF)
EndFunc
