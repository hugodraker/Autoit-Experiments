#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <GDIPlus.au3>
#include <FileConstants.au3>
#include <MsgBoxConstants.au3>
#include <WinAPIGdi.au3>

; ============================================================
; GLOBALS
; ============================================================
Global $g_aData[0]                  ; 1D array of numeric values
Global $g_sIni = @ScriptDir & "\chart_settings.ini"
Global $g_sChartType = IniRead($g_sIni, "Settings", "ChartType", "line")
Global $g_sScale = IniRead($g_sIni, "Settings", "Scale", "linear")
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
            IniWrite($g_sIni, "Settings", "ChartType", $g_sChartType)
            _DrawChart()

        Case $hBar
            $g_sChartType = "bar"
            IniWrite($g_sIni, "Settings", "ChartType", $g_sChartType)
            _DrawChart()

        Case $hPie
            $g_sChartType = "pie"
            IniWrite($g_sIni, "Settings", "ChartType", $g_sChartType)
            _DrawChart()

        Case $hLinear
            $g_sScale = "linear"
            IniWrite($g_sIni, "Settings", "Scale", $g_sScale)
            _DrawChart()

        Case $hLog
            $g_sScale = "log"
            IniWrite($g_sIni, "Settings", "Scale", $g_sScale)
            _DrawChart()

        Case $hZoomIn
            $g_fZoom *= 1.2
            _DrawChart()

        Case $hZoomOut
            $g_fZoom /= 1.2
            _DrawChart()

        Case $hManual
            MsgBox($MB_ICONINFORMATION, "User Manual", _
                "1. File → Open to load CSV (Label,Value per line)" & @CRLF & _
                "2. View → choose Line/Bar/Pie" & @CRLF & _
                "3. View → Scale Linear/Logarithmic" & @CRLF & _
                "4. View → Zoom In/Out" & @CRLF & _
                "5. File → Save As PNG to export chart.")

        Case $hAbout
            MsgBox($MB_ICONINFORMATION, "About", "CSV Chart Viewer" & @CRLF & "AutoIt GDI+ chart demo.")
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

    ; margins
    Local $left = 70, $right = 20, $top = 20, $bottom = 60
    Local $plotW = $width - $left - $right
    Local $plotH = $height - $top - $bottom

    ; grid + axes
    _DrawGridAndAxes($g, $left, $top, $plotW, $plotH, $width, $height)

    ; chart
    Switch $g_sChartType
        Case "line"
            _DrawLineChart($g, $left, $top, $plotW, $plotH)
        Case "bar"
            _DrawBarChart($g, $left, $top, $plotW, $plotH)
        Case "pie"
            _DrawPieChart($g, $left, $top, $plotW, $plotH)
    EndSwitch

    ; axis labels
    _DrawAxisLabels($g, $width, $height, $left, $top, $plotW, $plotH)

    Local $hHBitmap = _GDIPlus_BitmapCreateHBITMAPFromBitmap($g_hBitmap)
    GUICtrlSetImage($hPic, "", $hHBitmap)
    _WinAPI_DeleteObject($hHBitmap)
EndFunc


Func _DrawGridAndAxes($g, $left, $top, $plotW, $plotH, $w, $h)
    Local $penGrid = _GDIPlus_PenCreate(0xFFDDDDDD, 1)
    Local $penAxis = _GDIPlus_PenCreate(0xFF000000, 2)

    ; horizontal grid (10 divisions)
    Local $rows = 10
    For $i = 0 To $rows
        Local $y = $top + ($plotH / $rows) * $i
        _GDIPlus_GraphicsDrawLine($g, $left, $y, $left + $plotW, $y, $penGrid)
    Next

    ; vertical grid (based on data count or max 20)
    Local $count = UBound($g_aData)
    Local $cols = $count
    If $cols > 20 Then $cols = 20
    If $cols < 1 Then $cols = 1
    For $i = 0 To $cols
        Local $x = $left + ($plotW / $cols) * $i
        _GDIPlus_GraphicsDrawLine($g, $x, $top, $x, $top + $plotH, $penGrid)
    Next

    ; axes
    ; Y axis
    _GDIPlus_GraphicsDrawLine($g, $left, $top, $left, $top + $plotH, $penAxis)
    ; X axis
    _GDIPlus_GraphicsDrawLine($g, $left, $top + $plotH, $left + $plotW, $top + $plotH, $penAxis)

    _GDIPlus_PenDispose($penGrid)
    _GDIPlus_PenDispose($penAxis)
EndFunc


Func _ScaleValueToY($value, $top, $plotH)
    Local $v = $value
    If $g_sScale = "log" Then
        If $v <= 0 Then $v = 0.1
        Local $logv = Log($v) / Log(10)
        ; assume range roughly 0..2 (for values up to 100)
        If $logv < 0 Then $logv = 0
        If $logv > 2 Then $logv = 2
        Local $norm = $logv / 2
        Return $top + $plotH - ($norm * $plotH)
    Else
        ; linear, assume 0..100
        If $v < 0 Then $v = 0
        If $v > 100 Then $v = 100
        Local $norm = $v / 100
        Return $top + $plotH - ($norm * $plotH)
    EndIf
EndFunc


Func _DrawLineChart($g, $left, $top, $plotW, $plotH)
    Local $pen = _GDIPlus_PenCreate(0xFF0000FF, 2)
    Local $count = UBound($g_aData)
    If $count < 2 Then
        _GDIPlus_PenDispose($pen)
        Return
    EndIf

    For $i = 1 To $count - 1
        Local $x1 = $left + ($plotW / ($count - 1)) * ($i - 1)
        Local $y1 = _ScaleValueToY($g_aData[$i - 1], $top, $plotH)
        Local $x2 = $left + ($plotW / ($count - 1)) * $i
        Local $y2 = _ScaleValueToY($g_aData[$i], $top, $plotH)
        _GDIPlus_GraphicsDrawLine($g, $x1, $y1, $x2, $y2, $pen)
    Next
    _GDIPlus_PenDispose($pen)
EndFunc


Func _DrawBarChart($g, $left, $top, $plotW, $plotH)
    Local $brush = _GDIPlus_BrushCreateSolid(0xFF00AA00)
    Local $count = UBound($g_aData)
    If $count = 0 Then
        _GDIPlus_BrushDispose($brush)
        Return
    EndIf

    Local $barW = $plotW / $count

    For $i = 0 To $count - 1
        Local $x = $left + $i * $barW
        Local $yTop = _ScaleValueToY($g_aData[$i], $top, $plotH)
        Local $barH = ($top + $plotH) - $yTop
        _GDIPlus_GraphicsFillRect($g, $x + 1, $yTop, $barW - 2, $barH, $brush)
    Next
    _GDIPlus_BrushDispose($brush)
EndFunc


Func _DrawPieChart($g, $left, $top, $plotW, $plotH)
    Local $sum = 0
    For $i = 0 To UBound($g_aData) - 1
        $sum += $g_aData[$i]
    Next
    If $sum = 0 Then Return

    Local $diam = _Min($plotW, $plotH)
    Local $x = $left + ($plotW - $diam) / 2
    Local $y = $top + ($plotH - $diam) / 2

    Local $start = 0
    For $i = 0 To UBound($g_aData) - 1
        Local $value = $g_aData[$i]
        Local $sweep = ($value / $sum) * 360
        Local $color = 0xFF000000 + Random(0, 0xFFFFFF)
        Local $brush = _GDIPlus_BrushCreateSolid($color)
        _GDIPlus_GraphicsFillPie($g, $x, $y, $diam, $diam, $start, $sweep, $brush)
        _GDIPlus_BrushDispose($brush)
        $start += $sweep
    Next
EndFunc


Func _DrawAxisLabels($g, $w, $h, $left, $top, $plotW, $plotH)
    Local $hFamily = _GDIPlus_FontFamilyCreate("Segoe UI")
    Local $hFont = _GDIPlus_FontCreate($hFamily, 10, 0)
    Local $hBrush = _GDIPlus_BrushCreateSolid(0xFF000000)

    ; X axis label
    Local $sX = "Index"
    Local $layoutX = _GDIPlus_RectFCreate($left, $top + $plotH + 25, $plotW, 20)
    _GDIPlus_GraphicsDrawStringEx($g, $sX, $hFont, $layoutX, 0, $hBrush)

    ; Y axis label (rotated)
    Local $sY = "Value (" & $g_sScale & ")"
    Local $layoutY = _GDIPlus_RectFCreate(5, $top, 60, $plotH)
    Local $hFormat = _GDIPlus_StringFormatCreate()
    _GDIPlus_StringFormatSetAlign($hFormat, 1) ; center
    Local $hState = _GDIPlus_GraphicsSave($g)
    _GDIPlus_GraphicsTranslateTransform($g, 20, $top + $plotH / 2)
    _GDIPlus_GraphicsRotateTransform($g, -90)
    Local $layoutY2 = _GDIPlus_RectFCreate(-$plotH / 2, -10, $plotH, 20)
    _GDIPlus_GraphicsDrawStringEx($g, $sY, $hFont, $layoutY2, $hFormat, $hBrush)
    _GDIPlus_GraphicsRestore($g, $hState)
    _GDIPlus_StringFormatDispose($hFormat)

    _GDIPlus_BrushDispose($hBrush)
    _GDIPlus_FontDispose($hFont)
    _GDIPlus_FontFamilyDispose($hFamily)
EndFunc


Func _SavePNG()
    If $g_hBitmap = 0 Then Return
    Local $sFile = FileSaveDialog("Save PNG", "", "PNG (*.png)", 2)
    If @error Then Return
    _GDIPlus_ImageSaveToFile($g_hBitmap, $sFile)
EndFunc


Func _Min($a, $b)
    If $a < $b Then Return $a
    Return $b
EndFunc
