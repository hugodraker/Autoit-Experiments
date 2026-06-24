; Autoit CSV Telnet Server + Minimal "DICOM" Worklist Server (CSV over TCP on port 1040)
; Telnet on port 23, CSV parsing, INI updates, plus a simple worklist & C-ECHO responder on port 1040.
; Extended to generate/store Accession Number (0008,0050), Requested Procedure ID (0040,1001),
; and Scheduled Procedure Step fields in the CSV and in the textual worklist output.
; CSV header is centralized in $CSV_HEADER to ensure it matches everywhere.

Opt("TrayAutoPause", 0)
Opt("TrayMenuMode", 3)

#RequireAdmin

#include <Array.au3>
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <EditConstants.au3>
#include <File.au3>
#include <Date.au3>

; -------------------------
; Configuration
; -------------------------
Global Const $MAIN_PORT   = 23
Global Const $DICOM_PORT  = 1040
Global Const $CSV_FILE    = @ScriptDir & "\patients.csv"
Global Const $INI_FILE    = @ScriptDir & "\server_config.ini"
Global Const $INACTIVITY_MS   = 15000
Global Const $APPEND_DELAY_MS = 2000
Global Const $MAX_CLIENTS     = 200

; Centralized CSV header
Global Const $CSV_HEADER = "Patient ID,Patient Name,Patient Birth Date,Sex,Modality,Referring Physician,Procedure Description,Start Date,Start Time,Status,AccessionNumber,RequestedProcedureID,SPS_ID,SPS_Desc"

; -------------------------
; Global state
; -------------------------
Global $g_bRunning = False
Global $g_listenSocket = -1
Global $g_listenPort = $MAIN_PORT
Global $g_dicomsock = -1

; Clients array: each row [Socket, SocketID_Log, Buffer, LastActivityTimer, PendingEntryObj, PendingSinceTimer]
Dim $g_aClients[0][6]

; GUI handles
Global $g_hStatusLabel = 0
Global $g_hClientsLabel = 0
Global $g_hLogEdit = 0

; Tray item IDs
Global $g_idStart = 0
Global $g_idStop = 0
Global $g_idSettings = 0
Global $g_idExit = 0

; Initialize TCP
TCPStartup()

; Ensure INI exists with broader default modalities
If Not FileExists($INI_FILE) Then
    IniWrite($INI_FILE, "Lists", "Modalities", "CR;DX;CT;MR;US")
    IniWrite($INI_FILE, "Lists", "AETitles", "")
    IniWrite($INI_FILE, "Lists", "ReferringPhysicians", "")
    IniWrite($INI_FILE, "Lists", "Procedures", "")
EndIf

; Create tray and GUI
CSVTS_TrayCreate()
CSVTS_CreateMainGUI()

; Hide GUI on start
CSVTS_HideMainGUI()

; Start servers automatically on script open
CSVTS_StartServer()
DICOM_StartServer()

; Main loop
While 1
    Local $msg = GUIGetMsg()
    Switch $msg
        Case $GUI_EVENT_CLOSE
            CSVTS_HideMainGUI()
    EndSwitch

    Local $tMsg = TrayGetMsg()
    Switch $tMsg
        Case $g_idStart
            CSVTS_StartServer()
            DICOM_StartServer()
        Case $g_idStop
            CSVTS_StopServer()
            DICOM_StopServer()
        Case $g_idSettings
            CSVTS_ShowSettings()
        Case $g_idExit
            CSVTS_StopServer()
            DICOM_StopServer()
            TCPShutdown()
            Exit
    EndSwitch

    If $g_bRunning Then CSVTS_ServerLoop()
    DICOM_ServerLoop()

    Sleep(20)
WEnd

; -------------------------
; Tray and GUI
; -------------------------
Func CSVTS_TrayCreate()
    $g_idStart    = TrayCreateItem("Start Server")
    $g_idStop     = TrayCreateItem("Stop Server")
    $g_idSettings = TrayCreateItem("Settings")
    TrayCreateItem("")
    $g_idExit     = TrayCreateItem("Exit")
    TraySetToolTip("Autoit CSV Telnet + Worklist Server")
    TraySetState()
EndFunc

Func CSVTS_CreateMainGUI()
    GUICreate("Autoit CSV Telnet + Worklist Server", 700, 380, -1, -1, BitOR($WS_SIZEBOX, $WS_SYSMENU))
    GUISetOnEvent($GUI_EVENT_CLOSE, "CSVTS_HideMainGUI")
    $g_hStatusLabel = GUICtrlCreateLabel("Server status: Stopped", 10, 10, 500, 20)
    $g_hClientsLabel = GUICtrlCreateLabel("Active clients: 0", 10, 35, 200, 20)
    GUICtrlCreateLabel("Log:", 10, 60, 50, 20)
    $g_hLogEdit = GUICtrlCreateEdit("", 10, 85, 680, 280, BitOR($ES_AUTOVSCROLL, $ES_READONLY, $WS_VSCROLL))
    GUISetState(@SW_SHOW)
EndFunc

Func CSVTS_HideMainGUI()
    GUISetState(@SW_HIDE)
EndFunc

Func CSVTS_ShowSettings()
    Local $h = GUICreate("Settings", 420, 260)
    GUICtrlCreateLabel("Settings (stub)", 10, 10, 200, 20)
    GUICtrlCreateLabel("INI file: " & $INI_FILE, 10, 40, 400, 20)
    Local $btnClose = GUICtrlCreateButton("Close", 170, 200, 80, 30)
    GUISetState(@SW_SHOW, $h)
    While 1
        Local $m = GUIGetMsg()
        If $m = $GUI_EVENT_CLOSE Or $m = $btnClose Then ExitLoop
        Sleep(50)
    WEnd
    GUIDelete($h)
EndFunc

; -------------------------
; Server control (Telnet)
; -------------------------
Func CSVTS_StartServer()
    If $g_bRunning Then
        CSVTS_Log("StartServer called but server already running on port " & $g_listenPort)
        Return
    EndIf

    $g_listenSocket = TCPListen("0.0.0.0", $g_listenPort)
    If $g_listenSocket = -1 Then
        CSVTS_Log("ERROR: Failed to listen on port " & $g_listenPort & ".")
        CSVTS_Log(" - @error = " & @error)
        GUICtrlSetData($g_hStatusLabel, "Server status: Failed to bind port " & $g_listenPort)
        $g_bRunning = False
        Return
    EndIf

    $g_bRunning = True
    CSVTS_Log("Telnet server started and listening on port " & $g_listenPort & " (socket " & $g_listenSocket & ")")
    GUICtrlSetData($g_hStatusLabel, "Server status: Running on port " & $g_listenPort)
EndFunc

Func CSVTS_StopServer()
    If Not $g_bRunning Then Return
    For $i = 0 To UBound($g_aClients) - 1
        If $g_aClients[$i][0] <> 0 Then TCPCloseSocket($g_aClients[$i][0])
    Next
    If $g_listenSocket <> -1 Then
        TCPCloseSocket($g_listenSocket)
        $g_listenSocket = -1
    EndIf
    ReDim $g_aClients[0][6]
    $g_bRunning = False
    CSVTS_Log("Telnet server stopped")
    GUICtrlSetData($g_hStatusLabel, "Server status: Stopped")
    GUICtrlSetData($g_hClientsLabel, "Active clients: 0")
EndFunc

; -------------------------
; DICOM-like Worklist server control (port 1040) with C-ECHO support
; -------------------------
Func DICOM_StartServer()
    If $g_dicomsock <> -1 Then
        CSVTS_Log("DICOM Worklist server already listening on port " & $DICOM_PORT)
        Return
    EndIf

    $g_dicomsock = TCPListen("0.0.0.0", $DICOM_PORT)
    If $g_dicomsock = -1 Then
        CSVTS_Log("ERROR: Failed to listen on DICOM Worklist port " & $DICOM_PORT & ".")
        Return
    EndIf

    CSVTS_Log("DICOM Worklist server listening on port " & $DICOM_PORT & " (socket " & $g_dicomsock & ")")
EndFunc

Func DICOM_StopServer()
    If $g_dicomsock <> -1 Then
        TCPCloseSocket($g_dicomsock)
        $g_dicomsock = -1
        CSVTS_Log("DICOM Worklist server stopped")
    EndIf
EndFunc

; -------------------------
; Main server loop (Telnet)
; -------------------------
Func CSVTS_ServerLoop()
    If $g_listenSocket = -1 Then
        If $g_bRunning Then
            CSVTS_Log("Warning: listen socket invalid; stopping server state.")
            $g_bRunning = False
            GUICtrlSetData($g_hStatusLabel, "Server status: Stopped (listen socket lost)")
        EndIf
        Return
    EndIf

    Local $newSock = TCPAccept($g_listenSocket)
    If $newSock <> -1 Then
        CSVTS_AddClient($newSock)
        TCPSend($newSock, "Connected to CSV Telnet Server. Waiting for data..." & @CRLF)
    EndIf

    For $i = UBound($g_aClients) - 1 To 0 Step -1
        Local $sock = $g_aClients[$i][0]
        If $sock = 0 Or $sock = -1 Then ContinueLoop
        Local $data = TCPRecv($sock, 4096)
        
        If @error = 0 And $data <> "" Then
            $g_aClients[$i][3] = TimerInit()
            $g_aClients[$i][2] &= $data
            While StringInStr($g_aClients[$i][2], @CRLF) Or StringInStr($g_aClients[$i][2], @LF)
                Local $line, $pos
                If StringInStr($g_aClients[$i][2], @CRLF) Then
                    $pos = StringInStr($g_aClients[$i][2], @CRLF)
                    $line = StringLeft($g_aClients[$i][2], $pos - 1)
                    $g_aClients[$i][2] = StringTrimLeft($g_aClients[$i][2], $pos + StringLen(@CRLF) - 1)
                Else
                    $pos = StringInStr($g_aClients[$i][2], @LF)
                    $line = StringLeft($g_aClients[$i][2], $pos - 1)
                    $g_aClients[$i][2] = StringTrimLeft($g_aClients[$i][2], $pos + 1 - 1)
                EndIf
                CSVTS_ProcessClientLine($i, $line)
            WEnd
        EndIf

        If IsObj($g_aClients[$i][4]) Then
            If TimerDiff($g_aClients[$i][5]) >= $APPEND_DELAY_MS Then
                CSVTS_CommitPendingEntry($i)
                $g_aClients[$i][3] = TimerInit()
            EndIf
        EndIf

        If TimerDiff($g_aClients[$i][3]) >= $INACTIVITY_MS Then
            CSVTS_Log("Client on socket " & $g_aClients[$i][1] & " timed out")
            TCPCloseSocket($g_aClients[$i][0])
            CSVTS_RemoveClient($i)
        EndIf
    Next

    GUICtrlSetData($g_hClientsLabel, "Active clients: " & UBound($g_aClients))
EndFunc

; -------------------------
; DICOM-like Worklist server loop (CSV over TCP) with C-ECHO handling
; -------------------------
Func DICOM_ServerLoop()
    If $g_dicomsock = -1 Then Return

    Local $sock = TCPAccept($g_dicomsock)
    If $sock = -1 Then Return

    CSVTS_Log("DICOM client connected on socket " & $sock)

    ; =========================
    ; STEP 1: RECEIVE ASSOCIATE REQUEST
    ; =========================
    Local $rq = TCPRecv($sock, 16384, 1) ; binary mode

    If @error Or BinaryLen($rq) < 6 Then
        CSVTS_Log("Invalid or empty DICOM request")
        TCPCloseSocket($sock)
        Return
    EndIf

    Local $pduType = Dec(Hex(BinaryMid($rq, 1, 1)))

    ; 0x01 = A-ASSOCIATE-RQ
    If $pduType <> 1 Then
        CSVTS_Log("Unexpected PDU type: " & $pduType)
        TCPCloseSocket($sock)
        Return
    EndIf

    CSVTS_Log("Received A-ASSOCIATE-RQ")

    ; =========================
    ; STEP 2: SEND ASSOCIATE ACCEPT
    ; =========================
    Local $assocAC = Binary( _
        "0x02" & _            ; PDU Type = A-ASSOCIATE-AC
        "00" & _
        "0000005A" & _        ; length
        "0001" & _
        "0000" & _
        "534552564552202020202020202020" & _ ; Called AE = SERVER
        "434C49454E54202020202020202020" & _ ; Calling AE = CLIENT
        "0000000000000000000000000000000000000000000000000000000000000000" _
    )

    TCPSend($sock, $assocAC)
    CSVTS_Log("Sent A-ASSOCIATE-AC")

    ; =========================
    ; STEP 3: WAIT FOR COMMAND
    ; =========================
    Local $cmd = TCPRecv($sock, 16384, 1)

    If @error Or BinaryLen($cmd) < 6 Then
        CSVTS_Log("No DIMSE command received")
        TCPCloseSocket($sock)
        Return
    EndIf

    ; Quick detection of C-ECHO-RQ
    ; Usually Command Field (0000,0100) = 0x0030
    Local $cmdHex = Hex($cmd)

    If StringInStr($cmdHex, "0000010000000030") Or StringInStr($cmdHex, "0030") Then
        CSVTS_Log("Detected C-ECHO-RQ")

        ; =========================
        ; STEP 4: SEND C-ECHO-RSP SUCCESS
        ; =========================

        ; Very minimal DIMSE-C-ECHO-RSP wrapped in P-DATA-TF
        Local $echoRsp = Binary( _
            "0x04" & _                ; P-DATA-TF
            "00" & _
            "00000028" & _            ; length
            "0000001A" & _
            "03" & _                  ; PDV flags
            "00000100" & _            ; Command Group Length
            "00000010" & _
            "00000100" & _
            "00000000" _              ; Status SUCCESS
        )

        TCPSend($sock, $echoRsp)
        CSVTS_Log("Sent C-ECHO-RSP SUCCESS")
    Else
        CSVTS_Log("Unknown DIMSE command - returning worklist text (NON STANDARD)")
        DICOM_SendWorklistFromCSV($sock)
    EndIf

    ; =========================
    ; DONE
    ; =========================
    TCPCloseSocket($sock)
    CSVTS_Log("DICOM client disconnected " & $sock)
EndFunc

; -------------------------
; Client management
; -------------------------
Func CSVTS_AddClient($sock)
    Local $n = UBound($g_aClients)
    ReDim $g_aClients[$n + 1][6]
    $g_aClients[$n][0] = $sock
    $g_aClients[$n][1] = $sock
    $g_aClients[$n][2] = ""
    $g_aClients[$n][3] = TimerInit()
    $g_aClients[$n][4] = 0
    $g_aClients[$n][5] = 0
    CSVTS_Log("Client connected on socket " & $sock)
EndFunc

Func CSVTS_RemoveClient($index)
    Local $n = UBound($g_aClients) - 1
    For $j = $index To $n - 1
        $g_aClients[$j][0] = $g_aClients[$j + 1][0]
        $g_aClients[$j][1] = $g_aClients[$j + 1][1]
        $g_aClients[$j][2] = $g_aClients[$j + 1][2]
        $g_aClients[$j][3] = $g_aClients[$j + 1][3]
        $g_aClients[$j][4] = $g_aClients[$j + 1][4]
        $g_aClients[$j][5] = $g_aClients[$j + 1][5]
    Next
    ReDim $g_aClients[$n][6]
EndFunc

; -------------------------
; Robust CSV splitter (handles quoted fields)
; -------------------------
Func CSVTS_SplitCSV($s)
    Local $out[0]
    Local $len = StringLen($s)
    Local $inQuote = False
    Local $cur = ""
    For $p = 1 To $len
        Local $ch = StringMid($s, $p, 1)
        If $ch = '"' Then
            ; If next char is also quote, treat as escaped quote
            If $inQuote And $p < $len And StringMid($s, $p+1, 1) = '"' Then
                $cur &= '"'
                $p += 1
                ContinueLoop
            EndIf
            $inQuote = Not $inQuote
            ContinueLoop
        EndIf
        If $ch = "," And Not $inQuote Then
            _ArrayAdd($out, $cur)
            $cur = ""
        Else
            $cur &= $ch
        EndIf
    Next
    _ArrayAdd($out, $cur)
    Return $out
EndFunc

; -------------------------
; Process a single client CSV line (accepts header and 10+ fields)
; -------------------------
Func CSVTS_ProcessClientLine($clientIndex, $line)
    $line = StringReplace($line, "~", '"')
    $line = StringStripWS($line, 3)
    If $line = "" Then Return

    ; --- Header detection and handling (uses centralized $CSV_HEADER) ---
    If StringLeft($line, StringLen($CSV_HEADER)) = $CSV_HEADER Then
        ; Ensure CSV exists with exact header
        If Not FileExists($CSV_FILE) Then
            Local $h = FileOpen($CSV_FILE, 2)
            If $h <> -1 Then
                FileWriteLine($h, $CSV_HEADER)
                FileClose($h)
                Local $sock = $g_aClients[$clientIndex][0]
                If $sock <> 0 And $sock <> -1 Then TCPSend($sock, "HEADER WRITTEN" & @CRLF)
                CSVTS_Log("CSV header written by client on socket " & $g_aClients[$clientIndex][1])
            Else
                Local $sock = $g_aClients[$clientIndex][0]
                If $sock <> 0 And $sock <> -1 Then TCPSend($sock, "HEADER WRITE FAILED" & @CRLF)
                CSVTS_Log("Failed to create CSV header file")
            EndIf
        Else
            ; File exists: ensure header line present; if not, prepend header
            Local $lines = CSVTS_FileReadToArray($CSV_FILE)
            If @error Or UBound($lines) = 0 Or StringLeft($lines[0], StringLen($CSV_HEADER)) <> $CSV_HEADER Then
                ; Prepend header
                Local $new[UBound($lines) + 1]
                $new[0] = $CSV_HEADER
                For $j = 0 To UBound($lines) - 1
                    $new[$j + 1] = $lines[$j]
                Next
                Local $h = FileOpen($CSV_FILE, 2)
                If $h <> -1 Then
                    For $j = 0 To UBound($new) - 1
                        FileWriteLine($h, $new[$j])
                    Next
                    FileClose($h)
                    Local $sock = $g_aClients[$clientIndex][0]
                    If $sock <> 0 And $sock <> -1 Then TCPSend($sock, "HEADER PREPENDED" & @CRLF)
                    CSVTS_Log("CSV header prepended by client on socket " & $g_aClients[$clientIndex][1])
                Else
                    Local $sock = $g_aClients[$clientIndex][0]
                    If $sock <> 0 And $sock <> -1 Then TCPSend($sock, "HEADER WRITE FAILED" & @CRLF)
                    CSVTS_Log("Failed to prepend CSV header")
                EndIf
            Else
                Local $sock = $g_aClients[$clientIndex][0]
                If $sock <> 0 And $sock <> -1 Then TCPSend($sock, "HEADER EXISTS" & @CRLF)
                CSVTS_Log("Client on socket " & $g_aClients[$clientIndex][1] & " sent header; header already exists")
            EndIf
        EndIf
        Return
    EndIf

    ; --- Normal data line processing ---
    Local $fields = CSVTS_SplitCSV($line)
    If Not IsArray($fields) Then Return
    ; Require at least the 10 core fields
    If UBound($fields) < 10 Then
        CSVTS_Log("Validation failed: Row has fewer than 10 required fields.")
        Return
    EndIf

    ; Map required fields (0-based)
    Local $patientID = StringStripWS($fields[0], 3)
    Local $patientName = StringStripWS($fields[1], 3)
    Local $birthDate = StringStripWS($fields[2], 3)
    Local $sex = StringUpper(StringStripWS($fields[3], 3))
    Local $modality = StringUpper(StringStripWS($fields[4], 3))
    Local $refPhys = StringStripWS($fields[5], 3)
    Local $procDesc = StringStripWS($fields[6], 3)
    Local $startDate = StringStripWS($fields[7], 3)
    Local $startTime = StringStripWS($fields[8], 3)
    Local $status = StringStripWS($fields[9], 3)

    ; Optional extended fields (if present)
    Local $accession = ""
    Local $reqProcID = ""
    Local $spsID = ""
    Local $spsDesc = ""
    If UBound($fields) >= 11 Then $accession = StringStripWS($fields[10], 3)
    If UBound($fields) >= 12 Then $reqProcID = StringStripWS($fields[11], 3)
    If UBound($fields) >= 13 Then $spsID = StringStripWS($fields[12], 3)
    If UBound($fields) >= 14 Then $spsDesc = StringStripWS($fields[13], 3)

    ; Basic validation with explicit error logging
    If $patientID = "" Then
        CSVTS_Log("Validation failed: PatientID is empty.")
        Return
    EndIf
    If Not CSVTS_IsValidDateYYYYMMDD($birthDate) Then
        CSVTS_Log("Validation failed: Invalid BirthDate -> " & $birthDate)
        Return
    EndIf
    If Not StringInStr("MFO", $sex) Then
        CSVTS_Log("Validation failed: Invalid Sex -> " & $sex)
        Return
    EndIf
    If Not CSVTS_IsValidDateYYYYMMDD($startDate) Then
        CSVTS_Log("Validation failed: Invalid StartDate -> " & $startDate)
        Return
    EndIf
    If Not CSVTS_IsValidTimeHHMM($startTime) Then
        CSVTS_Log("Validation failed: Invalid StartTime -> " & $startTime)
        Return
    EndIf
    If Not StringRegExp($status, "^[1-4]$") Then
        CSVTS_Log("Validation failed: Invalid Status -> " & $status)
        Return
    EndIf

    ; Build entry dictionary
    Local $entry = ObjCreate("Scripting.Dictionary")
    $entry.Add("PatientID", $patientID)
    $entry.Add("PatientName", $patientName)
    $entry.Add("BirthDate", $birthDate)
    $entry.Add("Sex", $sex)
    $entry.Add("Modality", $modality)
    $entry.Add("RefPhys", $refPhys)
    $entry.Add("ProcDesc", $procDesc)
    $entry.Add("StartDate", $startDate)
    $entry.Add("StartTime", $startTime)
    $entry.Add("Status", $status)

    ; Add optional fields if provided
    If $accession <> "" Then $entry.Add("AccessionNumber", $accession)
    If $reqProcID <> "" Then $entry.Add("RequestedProcedureID", $reqProcID)
    If $spsID <> "" Then $entry.Add("ScheduledProcedureStepID", $spsID)
    If $spsDesc <> "" Then $entry.Add("ScheduledProcedureStepDesc", $spsDesc)

    ; Queue pending entry and start commit timer
    $g_aClients[$clientIndex][4] = $entry
    $g_aClients[$clientIndex][5] = TimerInit()
    CSVTS_Log("Valid entry queued for PatientID " & $patientID & " (will commit in 2s)")
EndFunc

; -------------------------
; Commit pending entry (append/update CSV) and reply to client
; -------------------------
Func CSVTS_CommitPendingEntry($clientIndex)
    Local $entry = $g_aClients[$clientIndex][4]
    If Not IsObj($entry) Then Return

    Local $patientID = $entry.Item("PatientID")

    ; Ensure CSV exists with centralized header
    If Not FileExists($CSV_FILE) Then
        Local $h = FileOpen($CSV_FILE, 2)
        FileWriteLine($h, $CSV_HEADER)
        FileClose($h)
    EndIf

    ; Read existing lines
    Local $lines = CSVTS_FileReadToArray($CSV_FILE)
    If @error Or UBound($lines) = 0 Then
        Local $arrInit[1] = [$CSV_HEADER]
        $lines = $arrInit
    EndIf

    ; Ensure required DICOM fields exist; generate if missing
    If Not $entry.Exists("AccessionNumber") Then $entry.Add("AccessionNumber", DICOM_GenerateAccession($entry))
    If Not $entry.Exists("RequestedProcedureID") Then $entry.Add("RequestedProcedureID", DICOM_GenerateRequestedProcedureID($entry))
    If Not $entry.Exists("ScheduledProcedureStepID") Then $entry.Add("ScheduledProcedureStepID", "SPS-" & $patientID & "-" & Random(100,999,1))
    If Not $entry.Exists("ScheduledProcedureStepDesc") Then $entry.Add("ScheduledProcedureStepDesc", $entry.Item("ProcDesc"))

    ; Search for existing Patient ID (skip header)
    Local $found = False
    For $i = 1 To UBound($lines) - 1
        Local $row = $lines[$i]
        Local $cols = CSVTS_SplitCSV($row)
        If UBound($cols) >= 1 Then
            If StringStripWS($cols[0], 3) = $patientID Then
                $lines[$i] = CSVTS_EntryToCSVLine($entry)
                $found = True
                ExitLoop
            EndIf
        EndIf
    Next

    If Not $found Then _ArrayAdd($lines, CSVTS_EntryToCSVLine($entry))

    ; Write back file (atomic-ish: write all lines)
    Local $h = FileOpen($CSV_FILE, 2)
    If $h = -1 Then
        CSVTS_Log("Failed to open CSV for writing")
        Return
    EndIf
    For $i = 0 To UBound($lines) - 1
        FileWriteLine($h, $lines[$i])
    Next
    FileClose($h)

    ; Update INI lists
    CSVTS_UpdateIniList("Modalities", $entry.Item("Modality"))
    CSVTS_UpdateIniList("AETitles", "")
    CSVTS_UpdateIniList("ReferringPhysicians", $entry.Item("RefPhys"))
    CSVTS_UpdateIniList("Procedures", $entry.Item("ProcDesc"))

    ; Reply to client socket (if still connected)
    Local $sock = $g_aClients[$clientIndex][0]
    If $sock <> 0 And $sock <> -1 Then
        If $found Then
            TCPSend($sock, "UPDATED" & @CRLF)
            CSVTS_Log("UPDATED PatientID " & $patientID)
        Else
            TCPSend($sock, "INSERTED" & @CRLF)
            CSVTS_Log("INSERTED PatientID " & $patientID)
        EndIf
    Else
        If $found Then
            CSVTS_Log("UPDATED PatientID " & $patientID & " (socket closed)")
        Else
            CSVTS_Log("INSERTED PatientID " & $patientID & " (socket closed)")
        EndIf
    EndIf

    ; Clear pending
    $g_aClients[$clientIndex][4] = 0
    $g_aClients[$clientIndex][5] = 0
EndFunc

; Build CSV line from entry (includes extended fields)
Func CSVTS_EntryToCSVLine($entry)
    Local $arr[14]
    $arr[0]  = $entry.Item("PatientID")
    $arr[1]  = $entry.Item("PatientName")
    $arr[2]  = $entry.Item("BirthDate")
    $arr[3]  = $entry.Item("Sex")
    $arr[4]  = $entry.Item("Modality")
    $arr[5]  = $entry.Item("RefPhys")
    $arr[6]  = $entry.Item("ProcDesc")
    $arr[7]  = $entry.Item("StartDate")
    $arr[8]  = $entry.Item("StartTime")
    $arr[9]  = $entry.Item("Status")
    $arr[10] = $entry.Item("AccessionNumber")
    $arr[11] = $entry.Item("RequestedProcedureID")
    $arr[12] = $entry.Item("ScheduledProcedureStepID")
    $arr[13] = $entry.Item("ScheduledProcedureStepDesc")
    Local $s = ""
    For $i = 0 To 13
        Local $f = $arr[$i]
        If Not IsString($f) Then $f = String($f)
        If StringInStr($f, ",") Or StringInStr($f, '"') Then
            $f = StringReplace($f, '"', '""')
            $f = '"' & $f & '"'
        EndIf
        If $i > 0 Then $s &= ","
        $s &= $f
    Next
    Return $s
EndFunc

; -------------------------
; DICOM helpers: generate accession and requested procedure ID
; -------------------------
Func DICOM_GenerateAccession($entryOrCols)
    Local $patientID = ""
    If IsObj($entryOrCols) Then
        If $entryOrCols.Exists("PatientID") Then $patientID = $entryOrCols.Item("PatientID")
    ElseIf IsArray($entryOrCols) Then
        $patientID = $entryOrCols[0]
    EndIf
    If $patientID = "" Then $patientID = "UNKNOWN"
    Return "ACC-" & $patientID & "-" & @YEAR & @MON & @MDAY & @HOUR & @MIN & @SEC
EndFunc

Func DICOM_GenerateRequestedProcedureID($entryOrCols)
    Local $patientID = ""
    If IsObj($entryOrCols) Then
        If $entryOrCols.Exists("PatientID") Then $patientID = $entryOrCols.Item("PatientID")
    ElseIf IsArray($entryOrCols) Then
        $patientID = $entryOrCols[0]
    EndIf
    If $patientID = "" Then $patientID = "UNKNOWN"
    Return "RPID-" & $patientID & "-" & Random(1000,9999,1)
EndFunc

; -------------------------
; DICOM worklist sender (reads extended CSV columns)
; -------------------------
Func DICOM_SendWorklistFromCSV($sock)
    If Not FileExists($CSV_FILE) Then
        CSVTS_Log("DICOM worklist: CSV file not found, nothing to send")
        Return
    EndIf

    Local $lines = CSVTS_FileReadToArray($CSV_FILE)
    If @error Or UBound($lines) = 0 Then
        CSVTS_Log("DICOM worklist: CSV file empty or unreadable")
        Return
    EndIf

    TCPSend($sock, "# DICOM WORKLIST (textual representation)" & @CRLF)
    TCPSend($sock, "# Header: " & $lines[0] & @CRLF)

    For $i = 1 To UBound($lines) - 1
        Local $row = $lines[$i]
        If StringStripWS($row, 3) = "" Then ContinueLoop

        Local $cols = CSVTS_SplitCSV($row)
        If UBound($cols) >= 10 Then
            Local $patientID = StringStripWS($cols[0],3)
            Local $patientName = StringStripWS($cols[1],3)
            Local $birthDate = StringStripWS($cols[2],3)
            Local $sex = StringStripWS($cols[3],3)
            Local $modality = StringStripWS($cols[4],3)
            Local $refPhys = StringStripWS($cols[5],3)
            Local $procDesc = StringStripWS($cols[6],3)
            Local $startDate = StringStripWS($cols[7],3)
            Local $startTime = StringStripWS($cols[8],3)
            Local $status = StringStripWS($cols[9],3)

            Local $accession = ""
            Local $reqProcID = ""
            Local $spsID = ""
            Local $spsDesc = ""
            If UBound($cols) >= 11 Then $accession = StringStripWS($cols[10],3)
            If UBound($cols) >= 12 Then $reqProcID = StringStripWS($cols[11],3)
            If UBound($cols) >= 13 Then $spsID = StringStripWS($cols[12],3)
            If UBound($cols) >= 14 Then $spsDesc = StringStripWS($cols[13],3)

            If $accession = "" Then $accession = "ACC-" & $patientID & "-" & @YEAR & @MON & @MDAY
            If $reqProcID = "" Then $reqProcID = "RPID-" & $patientID & "-" & Random(1000,9999,1)
            If $spsID = "" Then $spsID = "SPS-" & $patientID & "-" & Random(100,999,1)
            If $spsDesc = "" Then $spsDesc = $procDesc

            Local $out = "PatientID=" & $patientID & "|PatientName=" & $patientName & _
                         "|BirthDate=" & $birthDate & "|Sex=" & $sex & _
                         "|AccessionNumber=" & $accession & " (0008,0050)" & _
                         "|RequestedProcedureID=" & $reqProcID & " (0040,1001)" & _
                         "|SPS_ID=" & $spsID & "|SPS_Desc=" & $spsDesc & _
                         "|SPS_Date=" & $startDate & "|SPS_Time=" & $startTime & "|SPS_Mod=" & $modality & _
                         "|RefPhys=" & $refPhys & "|Status=" & $status

            TCPSend($sock, $out & @CRLF)
        Else
            TCPSend($sock, $row & @CRLF)
        EndIf
    Next

    CSVTS_Log("DICOM worklist: sent " & (UBound($lines) - 1) & " items from CSV (including accession and requested procedure IDs).")
EndFunc

Func CSVTS_IsValidDateYYYYMMDD($d)
    If Not StringRegExp($d, "^\d{8}$") Then Return False
    Local $y = Number(StringLeft($d, 4))
    Local $m = Number(StringMid($d, 5, 2))
    Local $day = Number(StringRight($d, 2))
    If $m < 1 Or $m > 12 Then Return False
    Local $mdays = CSVTS_GetDaysInMonth($m, $y)
    If $day < 1 Or $day > $mdays Then Return False
    Return True
EndFunc

Func CSVTS_GetDaysInMonth($m, $y)
    Switch $m
        Case 1,3,5,7,8,10,12
            Return 31
        Case 4,6,9,11
            Return 30
        Case 2
            If CSVTS_IsLeapYear($y) Then Return 29 Else Return 28
    EndSwitch
    Return 31
EndFunc

Func CSVTS_IsLeapYear($y)
    If Mod($y, 400) = 0 Then Return True
    If Mod($y, 100) = 0 Then Return False
    If Mod($y, 4) = 0 Then Return True
    Return False
EndFunc

Func CSVTS_IsValidTimeHHMM($t)
    Local $hh, $mm
    If StringRegExp($t, "^\d{4}$") Then
        $hh = Number(StringLeft($t, 2))
        $mm = Number(StringRight($t, 2))
    ElseIf StringRegExp($t, "^\d{2}:\d{2}$") Then
        $hh = Number(StringLeft($t, 2))
        $mm = Number(StringRight($t, 2))
    Else
        Return False
    EndIf
    If $hh < 0 Or $hh > 23 Then Return False
    If $mm < 0 Or $mm > 59 Then Return False
    Return True
EndFunc

Func CSVTS_UpdateIniList($key, $value)
    If $value = "" Then Return
    Local $cur = IniRead($INI_FILE, "Lists", $key, "")
    If $cur <> "" Then
        Local $arr = StringSplit($cur, ";")
        For $i = 1 To $arr[0]
            If $arr[$i] = $value Then Return
        Next
    EndIf
    
    ; Fixed block to prevent the single-line Else syntax error
    If $cur = "" Then
        $cur = $value
    Else
        $cur &= ";" & $value
    EndIf
    
    IniWrite($INI_FILE, "Lists", $key, $cur)
EndFunc

; -------------------------
; File helpers and logging
; -------------------------
Func CSVTS_FileReadToArray($file)
    Local $arr[0]
    Local $h = FileOpen($file, 0)
    If $h = -1 Then Return SetError(1, 0, $arr)
    While 1
        Local $line = FileReadLine($h)
        If @error Then ExitLoop
        _ArrayAdd($arr, $line)
    WEnd
    FileClose($h)
    Return $arr
EndFunc

Func CSVTS_Log($s)
    If $g_hLogEdit Then
        Local $text = GUICtrlRead($g_hLogEdit)
        $text &= "[" & @HOUR & ":" & @MIN & ":" & @SEC & "] " & $s & @CRLF
        GUICtrlSetData($g_hLogEdit, $text)
    EndIf
    ConsoleWrite($s & @CRLF)
EndFunc