#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <GDIPlus.au3>
#include <FileConstants.au3>
#include <MsgBoxConstants.au3>
#include <WinAPIGdi.au3>

; ============================================================
; GLOBALS
; ============================================================
Global $g_aData[0]          ; 1D array of numeric values
Global $g_sChartType = "line"
Global $g_sScale = "linear"
Global $g_fZoom = 1.0
Global $g_hBitmap = 0

_GDIPlus_Startup()

; ============================================================
; GUI SETUP
; ============================================================
$hGUI = GUICreate("CSV Chart Viewer", 900, 600)

; File menu
$hMenuFile = GUICtrlCreateMenu("&File")
$hOpen     = GUICtrlCreateMenuItem("Open", $hMenuFile)
$hSavePNG  = GUICtrlCreateMenuItem("Save As PNG", $hMenuFile)
$hClose    = GUICtrlCreateMenuItem("Close", $hMenuFile)
$hPrint    = GUICtrlCreateMenuItem("Print", $hMenuFile)
GUICtrlCreateMenuItem("", $hMenuFile)
$hExit     = GUICtrlCreateMenuItem("Exit", $hMenuFile)

; View menu
$hMenuView = GUICtrlCreateMenu("&View")
$hLine     = GUICtrlCreateMenuItem("Select Line Graph", $hMenuView)
$hBar      = GUICtrlCreateMenuItem("Select Bar Graph", $hMenuView)
$hPie      = GUICtrlCreateMenuItem("Select Pie Graph", $hMenuView)
GUICtrlCreateMenuItem("", $hMenuView)
$hLinear   = GUICtrlCreateMenuItem("Scale Linear", $hMenuView)
$hLog      = GUICtrlCreateMenuItem("Scale Logarithmic", $hMenuView)
GUICtrlCreateMenuItem("", $hMenuView)
$hZoomIn   = GUICtrlCreateMenuItem("Zoom In", $hMenuView)
$hZoomOut  = GUICtrlCreateMenuItem("Zoom Out", $hMenuView)

; Help menu
$hMenuHelp = GUICtrlCreateMenu("&Help")
$hManual   = GUICtrlCreateMenuItem("User Manual", $hMenuHelp)
$hAbout    = GUICtrlCreateMenuItem("About", $hMenuHelp)

; Chart display area
$hPic = GUICtrlCreatePic("", 10, 10, 880, 540)

GUISetState(@SW_SHOW)

; ============================================================
; MAIN LOOP
; ============================================================
While True
    Switch GUIGetMsg()
        Case $GUI_EVENT_CLOSE, $hExit
            ExitLoop

        Case $hOpen
            _OpenCSV()

        Case $hSavePNG
            _SavePNG()

        Case $hClose
            ReDim $g_aData[0]
            _DrawChart()

        Case $hPrint
            MsgBox($MB_ICONINFORMATION, "Print", "Printing not implemented.")

        Case $hLine
            $g_sChartType = "line"
            _DrawChart()

        Case $hBar
            $g_sChartType = "bar"
            _DrawChart()

        Case $hPie
            $g_sChartType = "pie"
            _DrawChart()

        Case $hLinear
            $g_sScale = "linear"
            _DrawChart()

        Case $hLog
            $g_sScale = "log"
            _DrawChart()

        Case $hZoomIn
            $g_fZoom *= 1.2
            _DrawChart()

        Case $hZoomOut
            $g_fZoom /= 1.2
            _DrawChart()

        Case $hManual
            MsgBox($MB_ICONINFORMATION, "User Manual", _
                "1. File → Open to load CSV" & @CRLF & _
                "2. View → choose chart type" & @CRLF & _
                "3. Zoom and scale options available.")

        Case $hAbout
            MsgBox($MB_ICONINFORMATION, "About", "CSV Chart Viewer" & @CRLF & "Created in AutoIt.")
    EndSwitch
WEnd

_GDIPlus_Shutdown()
Exit


; ============================================================
; FUNCTIONS
; ============================================================

Func _OpenCSV()
    Local $sFile = FileOpenDialog("Open CSV", "", "CSV Files (*.csv)", $FD_FILEMUSTEXIST)
    If @error Then Return

    Local $hFile = FileOpen($sFile, $FO_READ)
    If $hFile = -1 Then Return

    ReDim $g_aData[0]

    While 1
        Local $line = FileReadLine($hFile)
        If @error Then ExitLoop

        Local $parts = StringSplit($line, ",", 2)
        If UBound($parts) >= 2 Then
            Local $value = Number($parts[1])
            If Not @error Then
                Local $n = UBound($g_aData)
                ReDim $g_aData[$n + 1]
                $g_aData[$n] = $value
            EndIf
        EndIf
    WEnd
    FileClose($hFile)

    _DrawChart()
EndFunc


Func _DrawChart()
    If UBound($g_aData) = 0 Then
        GUICtrlSetImage($hPic, "")
        Return
    EndIf

    Local $width = 880 * $g_fZoom
    Local $height = 540 * $g_fZoom

    If $g_hBitmap Then _GDIPlus_BitmapDispose($g_hBitmap)
    $g_hBitmap = _GDIPlus_BitmapCreateFromScan0($width, $height)

    Local $g = _GDIPlus_ImageGetGraphicsContext($g_hBitmap)
    _GDIPlus_GraphicsClear($g, 0xFFFFFFFF)

    Switch $g_sChartType
        Case "line"
            _DrawLineChart($g, $width, $height)
        Case "bar"
            _DrawBarChart($g, $width, $height)
        Case "pie"
            _DrawPieChart($g, $width, $height)
    EndSwitch

    Local $hHBitmap = _GDIPlus_BitmapCreateHBITMAPFromBitmap($g_hBitmap)
    GUICtrlSetImage($hPic, "", $hHBitmap)
    _WinAPI_DeleteObject($hHBitmap)
EndFunc


Func _DrawLineChart($g, $w, $h)
    Local $pen = _GDIPlus_PenCreate(0xFF0000FF, 2)
    Local $count = UBound($g_aData)

    If $count < 2 Then Return

    For $i = 1 To $count - 1
        Local $x1 = ($i - 1) * ($w / $count)
        Local $y1 = $h - ($g_aData[$i - 1] * ($h / 100))
        Local $x2 = $i * ($w / $count)
        Local $y2 = $h - ($g_aData[$i] * ($h / 100))
        _GDIPlus_GraphicsDrawLine($g, $x1, $y1, $x2, $y2, $pen)
    Next
    _GDIPlus_PenDispose($pen)
EndFunc


Func _DrawBarChart($g, $w, $h)
    Local $brush = _GDIPlus_BrushCreateSolid(0xFF00AA00)
    Local $count = UBound($g_aData)
    Local $barW = $w / $count

    For $i = 0 To $count - 1
        Local $value = $g_aData[$i]
        Local $barH = $value * ($h / 100)
        _GDIPlus_GraphicsFillRect($g, $i * $barW, $h - $barH, $barW - 2, $barH, $brush)
    Next
    _GDIPlus_BrushDispose($brush)
EndFunc


Func _DrawPieChart($g, $w, $h)
    Local $sum = 0
    For $i = 0 To UBound($g_aData) - 1
        $sum += $g_aData[$i]
    Next
    If $sum = 0 Then Return

    Local $start = 0
    For $i = 0 To UBound($g_aData) - 1
        Local $value = $g_aData[$i]
        Local $sweep = ($value / $sum) * 360
        Local $color = 0xFF000000 + Random(0, 0xFFFFFF)
        Local $brush = _GDIPlus_BrushCreateSolid($color)
        _GDIPlus_GraphicsFillPie($g, 10, 10, $w - 20, $h - 20, $start, $sweep, $brush)
        _GDIPlus_BrushDispose($brush)
        $start += $sweep
    Next
EndFunc


Func _SavePNG()
    If $g_hBitmap = 0 Then Return
    Local $sFile = FileSaveDialog("Save PNG", "", "PNG (*.png)", 2)
    If @error Then Return
    _GDIPlus_ImageSaveToFile($g_hBitmap, $sFile)
EndFunc
