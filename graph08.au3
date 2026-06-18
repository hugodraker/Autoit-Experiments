#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <FileConstants.au3>
#include <MsgBoxConstants.au3>
#include <WinAPIGdi.au3>
#include <GDIPlus.au3>
#include <FontConstants.au3>

; ============================================================
; GLOBALS
; ============================================================
Global $g_aValues[0]
Global $g_aLabels[0]
Global $g_sIni       = @ScriptDir & "\chart_settings.ini"
Global $g_sChartType = IniRead($g_sIni, "Settings", "ChartType", "line")
Global $g_sScale     = IniRead($g_sIni, "Settings", "Scale", "linear")
Global $g_bTrend     = (IniRead($g_sIni, "Settings", "Trend", "0") = "1")
Global $g_fZoom      = 1.0
Global $g_sCurrentFile = ""

Global $hGUI, $hPic
Global $hMemDC = 0, $hMemBmp = 0
Global $g_iBackW = 0, $g_iBackH = 0

_GDIPlus_Startup()

; ============================================================
; GUI
; ============================================================
$hGUI = GUICreate("CSV Chart Viewer (GDI)", 900, 600, -1, -1, _
    BitOR($WS_OVERLAPPEDWINDOW, $WS_CLIPSIBLINGS, $WS_CLIPCHILDREN))

; File menu
$hMenuFile = GUICtrlCreateMenu("&File")
$hOpen     = GUICtrlCreateMenuItem("Open", $hMenuFile)
$hSavePNG  = GUICtrlCreateMenuItem("Save As PNG", $hMenuFile)
$hSaveWMF  = GUICtrlCreateMenuItem("Save As WMF", $hMenuFile)
$hSaveEMF  = GUICtrlCreateMenuItem("Save As EMF", $hMenuFile)
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
GUICtrlCreateMenuItem("", $hMenuView)
$hTrend    = GUICtrlCreateMenuItem("Show Trend Line", $hMenuView)

; Help menu
$hMenuHelp = GUICtrlCreateMenu("&Help")
$hManual   = GUICtrlCreateMenuItem("User Manual", $hMenuHelp)
$hAbout    = GUICtrlCreateMenuItem("About", $hMenuHelp)

$hPic = GUICtrlCreatePic("", 10, 10, 880, 540)

GUISetState(@SW_SHOW)

_UpdateChartTypeChecks()
_UpdateScaleChecks()
_UpdateTrendCheck()

; ============================================================
; MAIN LOOP
; ============================================================
While True
    Switch GUIGetMsg()
        Case $GUI_EVENT_CLOSE, $hExit
            ExitLoop

        Case $GUI_EVENT_RESIZED
            _OnResize()

        Case $hOpen
            _OpenCSV()

        Case $hSavePNG
            _SavePNG()

        Case $hSaveWMF
            _SaveMetaFile(False)

        Case $hSaveEMF
            _SaveMetaFile(True)

        Case $hClose
            ReDim $g_aValues[0]
            ReDim $g_aLabels[0]
            _RedrawToWindow()

        Case $hPrint
            MsgBox($MB_ICONINFORMATION, "Print", "Printing not implemented.")

        Case $hLine
            $g_sChartType = "line"
            IniWrite($g_sIni, "Settings", "ChartType", $g_sChartType)
            _UpdateChartTypeChecks()
            _RedrawToWindow()

        Case $hBar
            $g_sChartType = "bar"
            IniWrite($g_sIni, "Settings", "ChartType", $g_sChartType)
            _UpdateChartTypeChecks()
            _RedrawToWindow()

        Case $hPie
            $g_sChartType = "pie"
            IniWrite($g_sIni, "Settings", "ChartType", $g_sChartType)
            _UpdateChartTypeChecks()
            _RedrawToWindow()

        Case $hLinear
            $g_sScale = "linear"
            IniWrite($g_sIni, "Settings", "Scale", $g_sScale)
            _UpdateScaleChecks()
            _RedrawToWindow()

        Case $hLog
            $g_sScale = "log"
            IniWrite($g_sIni, "Settings", "Scale", $g_sScale)
            _UpdateScaleChecks()
            _RedrawToWindow()

        Case $hZoomIn
            $g_fZoom *= 1.2
            _RedrawToWindow()

        Case $hZoomOut
            $g_fZoom /= 1.2
            _RedrawToWindow()

        Case $hTrend
            $g_bTrend = Not $g_bTrend
            IniWrite($g_sIni, "Settings", "Trend", $g_bTrend ? "1" : "0")
            _UpdateTrendCheck()
            _RedrawToWindow()

        Case $hManual
            MsgBox($MB_ICONINFORMATION, "User Manual", _
                "CSV format: Label,Value per line" & @CRLF & _
                "File → Open to load" & @CRLF & _
                "View → choose Line/Bar/Pie, scale, zoom, trend line.")

        Case $hAbout
            MsgBox($MB_ICONINFORMATION, "About", "CSV Chart Viewer (GDI)" & @CRLF & "Vector EMF/WMF export.")
    EndSwitch
WEnd

_GDIPlus_Shutdown()
_ReleaseMemDC()
Exit


; ============================================================
; MENU STATE HELPERS
; ============================================================
Func _UpdateChartTypeChecks()
    GUICtrlSetState($hLine, $GUI_UNCHECKED)
    GUICtrlSetState($hBar,  $GUI_UNCHECKED)
    GUICtrlSetState($hPie,  $GUI_UNCHECKED)
    Switch $g_sChartType
        Case "line"
            GUICtrlSetState($hLine, $GUI_CHECKED)
        Case "bar"
            GUICtrlSetState($hBar, $GUI_CHECKED)
        Case "pie"
            GUICtrlSetState($hPie, $GUI_CHECKED)
    EndSwitch
EndFunc

Func _UpdateScaleChecks()
    GUICtrlSetState($hLinear, $GUI_UNCHECKED)
    GUICtrlSetState($hLog,    $GUI_UNCHECKED)
    If $g_sScale = "linear" Then
        GUICtrlSetState($hLinear, $GUI_CHECKED)
    Else
        GUICtrlSetState($hLog, $GUI_CHECKED)
    EndIf
EndFunc

Func _UpdateTrendCheck()
    GUICtrlSetState($hTrend, $GUI_UNCHECKED)
    If $g_bTrend Then GUICtrlSetState($hTrend, $GUI_CHECKED)
EndFunc


; ============================================================
; RESIZE HANDLING
; ============================================================
Func _OnResize()
    Local $aSize = WinGetClientSize($hGUI)
    If @error Then Return

    Local $picW = $aSize[0] - 20
    Local $picH = $aSize[1] - 60
    If $picW < 50 Then $picW = 50
    If $picH < 50 Then $picH = 50

    GUICtrlSetPos($hPic, 10, 10, $picW, $picH)

    _ReleaseMemDC()
    _RedrawToWindow()
EndFunc


; ============================================================
; CSV LOADING
; ============================================================
Func _OpenCSV()
    Local $sFile = FileOpenDialog("Open CSV", "", "CSV Files (*.csv)", $FD_FILEMUSTEXIST)
    If @error Then Return

    Local $hFile = FileOpen($sFile, $FO_READ)
    If $hFile = -1 Then Return

    $g_sCurrentFile = $sFile
    WinSetTitle($hGUI, "", "CSV Chart Viewer (GDI) - " & _
        StringTrimLeft($sFile, StringInStr($sFile, "\", 0, -1)))

    ReDim $g_aValues[0]
    ReDim $g_aLabels[0]

    While 1
        Local $line = FileReadLine($hFile)
        If @error Then ExitLoop

        Local $parts = StringSplit($line, ",", 2)
        If UBound($parts) >= 2 Then
            Local $label = StringStripWS($parts[0], 7)
            Local $value = Number($parts[1])
            If Not @error Then
                Local $n = UBound($g_aValues)
                ReDim $g_aValues[$n + 1]
                ReDim $g_aLabels[$n + 1]
                $g_aValues[$n] = $value
                $g_aLabels[$n] = $label
            EndIf
        EndIf
    WEnd
    FileClose($hFile)

    _RedrawToWindow()
EndFunc

; ============================================================
; GDI BACKBUFFER
; ============================================================
Func _EnsureMemDC($w, $h)
    If $hMemDC <> 0 And $g_iBackW = $w And $g_iBackH = $h Then Return

    _ReleaseMemDC()

    Local $hWndPic = GUICtrlGetHandle($hPic)
    Local $hDC = _WinAPI_GetDC($hWndPic)

    $hMemDC = _WinAPI_CreateCompatibleDC($hDC)
    $hMemBmp = _WinAPI_CreateCompatibleBitmap($hDC, $w, $h)
    _WinAPI_SelectObject($hMemDC, $hMemBmp)

    _WinAPI_ReleaseDC($hWndPic, $hDC)

    $g_iBackW = $w
    $g_iBackH = $h
EndFunc


Func _ReleaseMemDC()
    If $hMemDC <> 0 Then
        _WinAPI_DeleteObject($hMemBmp)
        _WinAPI_DeleteDC($hMemDC)
        $hMemBmp = 0
        $hMemDC = 0
        $g_iBackW = 0
        $g_iBackH = 0
    EndIf
EndFunc


Func _RedrawToWindow()
    Local $aPos = ControlGetPos($hGUI, "", $hPic)
    If @error Then Return

    Local $w = $aPos[2]
    Local $h = $aPos[3]

    If $w < 10 Or $h < 10 Then Return

    _EnsureMemDC($w, $h)

    Local $tRect = DllStructCreate($tagRECT)
    DllStructSetData($tRect, "Left", 0)
    DllStructSetData($tRect, "Top", 0)
    DllStructSetData($tRect, "Right", $w)
    DllStructSetData($tRect, "Bottom", $h)

    Local $hBrushWhite = _WinAPI_CreateSolidBrush(0xFFFFFF)
    _WinAPI_FillRect($hMemDC, $tRect, $hBrushWhite)
    _WinAPI_DeleteObject($hBrushWhite)

    _DrawChartGDI($hMemDC, $w, $h)

    Local $hWndPic = GUICtrlGetHandle($hPic)
    Local $hDC = _WinAPI_GetDC($hWndPic)
    _WinAPI_BitBlt($hDC, 0, 0, $w, $h, $hMemDC, 0, 0, $SRCCOPY)
    _WinAPI_ReleaseDC($hWndPic, $hDC)
EndFunc


; ============================================================
; DRAWING CORE
; ============================================================
Func _DrawChartGDI($hDC, $w, $h)
    If UBound($g_aValues) = 0 Then Return

    Local $left = 70, $right = 150, $top = 20, $bottom = 60
    Local $plotW = Int(($w - $left - $right) * $g_fZoom)
    Local $plotH = Int(($h - $top - $bottom) * $g_fZoom)
    If $plotW <= 0 Or $plotH <= 0 Then Return

    ; compute autoscale min/max for non-pie charts
    Local $min = 0, $max = 0, $range = 0
    If $g_sChartType <> "pie" Then
        Local $n = UBound($g_aValues)
        $min = 1.0e+30
        $max = -1.0e+30
        For $i = 0 To $n - 1
            If $g_aValues[$i] < $min Then $min = $g_aValues[$i]
            If $g_aValues[$i] > $max Then $max = $g_aValues[$i]
        Next
        If $min = 1.0e+30 Then
            $min = 0
            $max = 1
        EndIf
        $range = $max - $min
        If $range = 0 Then $range = 1
        $min -= $range * 0.05
        $max += $range * 0.05
    EndIf

    If $g_sChartType <> "pie" Then
        _DrawGridAndAxesGDI($hDC, $left, $top, $plotW, $plotH)
        _DrawAxisNumericLabelsGDI($hDC, $left, $top, $plotW, $plotH, $min, $max)
        _DrawAxisTextLabelsGDI($hDC, $left, $top, $plotW, $plotH)
    EndIf

    Switch $g_sChartType
        Case "line"
            _DrawLineChartGDI($hDC, $left, $top, $plotW, $plotH, $min, $max)
            If $g_bTrend Then _DrawTrendLineGDI($hDC, $left, $top, $plotW, $plotH, $min, $max)

        Case "bar"
            _DrawBarChartGDI($hDC, $left, $top, $plotW, $plotH, $min, $max)
            If $g_bTrend Then _DrawTrendLineGDI($hDC, $left, $top, $plotW, $plotH, $min, $max)

        Case "pie"
            _DrawPieChartGDI($hDC, $left, $top, $plotW, $plotH, $w, $h)
    EndSwitch
EndFunc


; ============================================================
; GRID + AXES
; ============================================================
Func _DrawGridAndAxesGDI($hDC, $left, $top, $plotW, $plotH)
    Local $hPenGrid = _WinAPI_CreatePen($PS_SOLID, 1, 0xDDDDDD)
    Local $hPenAxis = _WinAPI_CreatePen($PS_SOLID, 2, 0x000000)
    Local $hOldPen = _WinAPI_SelectObject($hDC, $hPenGrid)

    Local $rows = 10
    For $i = 0 To $rows
        Local $y = $top + ($plotH * $i) / $rows
        _WinAPI_MoveToEx($hDC, $left, $y)
        _WinAPI_LineTo($hDC, $left + $plotW, $y)
    Next

    Local $count = UBound($g_aValues)
    Local $cols = $count
    If $cols > 20 Then $cols = 20
    If $cols < 1 Then $cols = 1
    For $i = 0 To $cols
        Local $x = $left + ($plotW * $i) / $cols
        _WinAPI_MoveToEx($hDC, $x, $top)
        _WinAPI_LineTo($hDC, $x, $top + $plotH)
    Next

    _WinAPI_SelectObject($hDC, $hPenAxis)
    _WinAPI_MoveToEx($hDC, $left, $top)
    _WinAPI_LineTo($hDC, $left, $top + $plotH)
    _WinAPI_MoveToEx($hDC, $left, $top + $plotH)
    _WinAPI_LineTo($hDC, $left + $plotW, $top + $plotH)

    _WinAPI_SelectObject($hDC, $hOldPen)
    _WinAPI_DeleteObject($hPenGrid)
    _WinAPI_DeleteObject($hPenAxis)
EndFunc


Func _DrawAxisNumericLabelsGDI($hDC, $left, $top, $plotW, $plotH, $min, $max)
    Local $hFont = _WinAPI_CreateFont(14, 0, 0, 0, 400, False, False, False, _
        $DEFAULT_CHARSET, $OUT_DEFAULT_PRECIS, $CLIP_DEFAULT_PRECIS, _
        $DEFAULT_QUALITY, $DEFAULT_PITCH, "Segoe UI")

    Local $hOldFont = _WinAPI_SelectObject($hDC, $hFont)

    Local $rows = 10
    Local $range = $max - $min
    If $range = 0 Then $range = 1

    For $i = 0 To $rows
        Local $t = 1 - ($i / $rows)
        Local $value = $min + $range * $t
        Local $y = $top + ($plotH * $i) / $rows
        Local $text = StringFormat("%.2f", $value)
        _WinAPI_TextOut($hDC, 10, $y - 7, $text)
    Next

    _WinAPI_SelectObject($hDC, $hOldFont)
    _WinAPI_DeleteObject($hFont)
EndFunc


Func _DrawAxisTextLabelsGDI($hDC, $left, $top, $plotW, $plotH)
    Local $hFont = _WinAPI_CreateFont(16, 0, 0, 0, 600, False, False, False, _
        $DEFAULT_CHARSET, $OUT_DEFAULT_PRECIS, $CLIP_DEFAULT_PRECIS, _
        $DEFAULT_QUALITY, $DEFAULT_PITCH, "Segoe UI")

    Local $hOldFont = _WinAPI_SelectObject($hDC, $hFont)

    Local $sX = "Index"
    Local $xCenter = $left + $plotW / 2
    _WinAPI_TextOut($hDC, $xCenter - (StringLen($sX) * 4), $top + $plotH + 25, $sX)

    Local $sY = "Value (" & $g_sScale & ")"
    _WinAPI_TextOut($hDC, 10, $top - 15, $sY)

    _WinAPI_SelectObject($hDC, $hOldFont)
    _WinAPI_DeleteObject($hFont)
EndFunc


; ============================================================
; VALUE SCALING
; ============================================================
Func _ScaleValueToY($value, $top, $plotH, $min, $max)
    Local $v = $value

    If $g_sScale = "log" Then
        If $v <= 0 Then $v = 0.0001
        If $min <= 0 Then $min = 0.0001

        Local $logv = Log($v) / Log(10)
        Local $logMin = Log($min) / Log(10)
        Local $logMax = Log($max) / Log(10)

        If $logMax = $logMin Then $logMax = $logMin + 1

        Local $norm = ($logv - $logMin) / ($logMax - $logMin)
        Return $top + $plotH - ($norm * $plotH)
    EndIf

    Local $range = $max - $min
    If $range = 0 Then $range = 1

    Local $norm = ($v - $min) / $range
    Return $top + $plotH - ($norm * $plotH)
EndFunc


; ============================================================
; LINE GRAPH
; ============================================================
Func _DrawLineChartGDI($hDC, $left, $top, $plotW, $plotH, $min, $max)
    Local $count = UBound($g_aValues)
    If $count < 2 Then Return

    Local $hPen = _WinAPI_CreatePen($PS_SOLID, 2, 0x0000FF)
    Local $hOldPen = _WinAPI_SelectObject($hDC, $hPen)

    For $i = 1 To $count - 1
        Local $x1 = $left + ($plotW * ($i - 1)) / ($count - 1)
        Local $y1 = _ScaleValueToY($g_aValues[$i - 1], $top, $plotH, $min, $max)

        Local $x2 = $left + ($plotW * $i) / ($count - 1)
        Local $y2 = _ScaleValueToY($g_aValues[$i], $top, $plotH, $min, $max)

        _WinAPI_MoveToEx($hDC, $x1, $y1)
        _WinAPI_LineTo($hDC, $x2, $y2)
    Next

    _WinAPI_SelectObject($hDC, $hOldPen)
    _WinAPI_DeleteObject($hPen)
EndFunc


; ============================================================
; BAR GRAPH
; ============================================================
Func _DrawBarChartGDI($hDC, $left, $top, $plotW, $plotH, $min, $max)
    Local $count = UBound($g_aValues)
    If $count = 0 Then Return

    Local $barW = $plotW / $count
    Local $hBrush = _WinAPI_CreateSolidBrush(0x00AA00)
    Local $hOldBrush = _WinAPI_SelectObject($hDC, $hBrush)

    For $i = 0 To $count - 1
        Local $x1 = $left + $i * $barW + 1
        Local $yTop = _ScaleValueToY($g_aValues[$i], $top, $plotH, $min, $max)
        Local $x2 = $left + ($i + 1) * $barW - 1
        Local $yBottom = $top + $plotH

        Local $tRect = DllStructCreate($tagRECT)
        DllStructSetData($tRect, "Left", $x1)
        DllStructSetData($tRect, "Top", $yTop)
        DllStructSetData($tRect, "Right", $x2)
        DllStructSetData($tRect, "Bottom", $yBottom)

        _WinAPI_FillRect($hDC, $tRect, $hBrush)
    Next

    _WinAPI_SelectObject($hDC, $hOldBrush)
    _WinAPI_DeleteObject($hBrush)
EndFunc


; ============================================================
; TREND LINE
; ============================================================
Func _DrawTrendLineGDI($hDC, $left, $top, $plotW, $plotH, $min, $max)
    Local $n = UBound($g_aValues)
    If $n < 2 Then Return

    Local $sumX = 0, $sumY = 0, $sumXY = 0, $sumX2 = 0

    For $i = 0 To $n - 1
        Local $x = $i
        Local $y = $g_aValues[$i]

        $sumX += $x
        $sumY += $y
        $sumXY += $x * $y
        $sumX2 += $x * $x
    Next

    Local $den = ($n * $sumX2 - $sumX * $sumX)
    If $den = 0 Then Return

    Local $m = ($n * $sumXY - $sumX * $sumY) / $den
    Local $b = ($sumY - $m * $sumX) / $n

    Local $hPen = _WinAPI_CreatePen($PS_SOLID, 2, 0x0000FF)
    Local $hOldPen = _WinAPI_SelectObject($hDC, $hPen)

    Local $x0 = 0, $x1 = $n - 1
    Local $y0 = $m * $x0 + $b
    Local $y1 = $m * $x1 + $b

    Local $px0 = $left
    Local $py0 = _ScaleValueToY($y0, $top, $plotH, $min, $max)

    Local $px1 = $left + $plotW
    Local $py1 = _ScaleValueToY($y1, $top, $plotH, $min, $max)

    _WinAPI_MoveToEx($hDC, $px0, $py0)
    _WinAPI_LineTo($hDC, $px1, $py1)

    _WinAPI_SelectObject($hDC, $hOldPen)
    _WinAPI_DeleteObject($hPen)
EndFunc

; ============================================================
; PIE CHART
; ============================================================
Func _DrawPieChartGDI($hDC, $left, $top, $plotW, $plotH, $w, $h)
    Local $n = UBound($g_aValues)
    If $n = 0 Then Return

    Local $sum = 0
    For $i = 0 To $n - 1
        $sum += $g_aValues[$i]
    Next
    If $sum = 0 Then Return

    Local $diam = _Min($plotW, $plotH)
    Local $cx = $left + ($plotW - $diam) / 2
    Local $cy = $top + ($plotH - $diam) / 2

    Local $start = 0
    Local $colors[$n]

    For $i = 0 To $n - 1
        Local $value = $g_aValues[$i]
        Local $sweep = ($value / $sum) * 360
        Local $color = BitOR(0x000000, Random(0x000000, 0xFFFFFF, 1))
        $colors[$i] = $color

        Local $hBrush = _WinAPI_CreateSolidBrush($color)
        Local $hOldBrush = _WinAPI_SelectObject($hDC, $hBrush)

        DllCall("gdi32.dll", "bool", "Pie", _
            "handle", $hDC, _
            "int", $cx, "int", $cy, "int", $cx + $diam, "int", $cy + $diam, _
            "int", _PiePointX($cx, $diam, $start), "int", _PiePointY($cy, $diam, $start), _
            "int", _PiePointX($cx, $diam, $start + $sweep), "int", _PiePointY($cy, $diam, $start + $sweep))

        _WinAPI_SelectObject($hDC, $hOldBrush)
        _WinAPI_DeleteObject($hBrush)

        $start += $sweep
    Next

    ; legend
    Local $hFont = _WinAPI_CreateFont(14, 0, 0, 0, 400, False, False, False, _
        $DEFAULT_CHARSET, $OUT_DEFAULT_PRECIS, $CLIP_DEFAULT_PRECIS, _
        $DEFAULT_QUALITY, $DEFAULT_PITCH, "Segoe UI")

    Local $hOldFont = _WinAPI_SelectObject($hDC, $hFont)

    Local $legendX = $left + $plotW + 10
    Local $legendY = $top + 10

    For $i = 0 To $n - 1
        Local $hBrush = _WinAPI_CreateSolidBrush($colors[$i])
        Local $hOldBrush = _WinAPI_SelectObject($hDC, $hBrush)

        Local $tRect = DllStructCreate($tagRECT)
        DllStructSetData($tRect, "Left", $legendX)
        DllStructSetData($tRect, "Top", $legendY + $i * 20)
        DllStructSetData($tRect, "Right", $legendX + 15)
        DllStructSetData($tRect, "Bottom", $legendY + $i * 20 + 15)

        _WinAPI_FillRect($hDC, $tRect, $hBrush)

        _WinAPI_SelectObject($hDC, $hOldBrush)
        _WinAPI_DeleteObject($hBrush)

        Local $text = $g_aLabels[$i] & " (" & $g_aValues[$i] & ")"
        _WinAPI_TextOut($hDC, $legendX + 20, $legendY + $i * 20, $text)
    Next

    _WinAPI_SelectObject($hDC, $hOldFont)
    _WinAPI_DeleteObject($hFont)
EndFunc


Func _PiePointX($cx, $diam, $angle)
    Local $rad = $angle * (3.14159265 / 180)
    Return $cx + $diam / 2 + Cos($rad) * ($diam / 2)
EndFunc

Func _PiePointY($cy, $diam, $angle)
    Local $rad = $angle * (3.14159265 / 180)
    Return $cy + $diam / 2 - Sin($rad) * ($diam / 2)
EndFunc


; ============================================================
; SAVE PNG (via GDI+ from HBITMAP)
; ============================================================
Func _SavePNG()
    If $hMemBmp = 0 Then Return
    Local $sFile = FileSaveDialog("Save PNG", "", "PNG (*.png)", 2)
    If @error Then Return

    Local $hBitmap = _GDIPlus_BitmapCreateFromHBITMAP($hMemBmp)
    _GDIPlus_ImageSaveToFile($hBitmap, $sFile)
    _GDIPlus_BitmapDispose($hBitmap)
EndFunc


; ============================================================
; SAVE WMF/EMF (vector)
; ============================================================
Func _SaveMetaFile($bEMF)
    If UBound($g_aValues) = 0 Then Return

    Local $filter = $bEMF ? "EMF (*.emf)" : "WMF (*.wmf)"
    Local $sFile = FileSaveDialog("Save Metafile", "", $filter, 2)
    If @error Then Return

    ; description uses input filename
    Local $desc = "CSV Chart"
    If $g_sCurrentFile <> "" Then
        $desc = StringTrimLeft($g_sCurrentFile, StringInStr($g_sCurrentFile, "\", 0, -1))
    EndIf

    Local $aPos = ControlGetPos($hGUI, "", $hPic)
    If @error Then Return
    Local $w = $aPos[2]
    Local $h = $aPos[3]

    Local $hWndPic = GUICtrlGetHandle($hPic)
    Local $hDCRef = _WinAPI_GetDC($hWndPic)

    Local $hMetaDC = _WinAPI_CreateEnhMetaFile($hDCRef, $sFile, 0, $desc)
    _WinAPI_ReleaseDC($hWndPic, $hDCRef)

    _DrawChartGDI($hMetaDC, $w, $h)

    Local $hEMF = _WinAPI_CloseEnhMetaFile($hMetaDC)
    _WinAPI_DeleteEnhMetaFile($hEMF)
EndFunc


; ============================================================
; UTILS
; ============================================================
Func _Min($a, $b)
    If $a < $b Then Return $a
    Return $b
EndFunc
