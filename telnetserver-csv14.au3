#cs
    NATIVE AUTOIT DICOM SERVER (Proof of Concept)
    ----------------------------------------------------
    Dynamically accepts requested Presentation Context IDs.
    Handles DULP handshake, C-ECHO (Ping), and C-FIND (MWL).
#ce

#include <MsgBoxConstants.au3>

; --- Configuration ---
Global $iPort = 1040
Global $sAETitle = "AUTOIT_SCP"

; Start TCP Services 
TCPStartup() 
Local $hMainSocket = TCPListen("0.0.0.0", $iPort) 

If $hMainSocket = -1 Then
    MsgBox($MB_ICONERROR, "Error", "Could not start native TCP server on port " & $iPort)
    Exit
EndIf

ConsoleWrite("--- Native AutoIt DICOM Server Started ---" & @CRLF)
ConsoleWrite("Listening on Port: " & $iPort & @CRLF) 
ConsoleWrite("Waiting for requests..." & @CRLF & @CRLF)

While 1
    ; Wait for an incoming connection 
    Local $hConnectedSocket = TCPAccept($hMainSocket)
    
    If $hConnectedSocket <> -1 Then
        ConsoleWrite("-> Client Connected!" & @CRLF)
        
        While 1
            ; Read incoming binary data from the client 
            Local $bRecv = TCPRecv($hConnectedSocket, 2048, 1) 
            
            If @error Then
                ConsoleWrite("<- Client Disconnected." & @CRLF & @CRLF)
                ExitLoop
            EndIf
            
            If BinaryLen($bRecv) > 0 Then 
                ; Extract the very first byte to determine the DICOM PDU Type [cite: 8]
                Local $iPDUType = Dec(Hex(BinaryMid($bRecv, 1, 1))) 
                
                Switch $iPDUType
                    Case 1 
                        ; PDU 0x01: A-ASSOCIATE-RQ (Association Request) [cite: 10]
                        ConsoleWrite("   [RECV] A-ASSOCIATE-RQ" & @CRLF) 
                        
                        ; 1. Dynamically find all proposed Context IDs using regex on the hex stream
                        Local $sHexReq = Hex($bRecv)
                        Local $sContextAccepts = ""
                        Local $iContextCount = 0
                        
                        ; Proposed contexts start with 0x20, 0x00, 4-char length, then the 2-char Context ID
                        Local $aContexts = StringRegExp($sHexReq, "2000[0-9A-F]{4}([0-9A-F]{2})", 3)
                        If IsArray($aContexts) Then
                            For $i = 0 To UBound($aContexts) - 1
                                Local $sCtxID = $aContexts[$i]
                                ; Construct an Accept Item (Type 0x21) for each requested Context ID
                                ; Accepting with Implicit VR Little Endian (1.2.840.10008.1.2)
                                $sContextAccepts &= "21000019" & $sCtxID & "00000040000011312E322E3834302E31303030382E312E32"
                                $iContextCount += 1
                                ConsoleWrite("          -> Accepting Context ID: " & Dec($sCtxID) & @CRLF)
                            Next
                        EndIf

                        ; 2. Calculate dynamic PDU Length based on how many contexts we accepted
                        ; Base Length: Protocol(2) + Res(2) + Called(16) + Calling(16) + Res(32) + AppContext(25) + UserInfo(12) = 105
                        Local $iBaseLen = 105
                        Local $iTotalLen = $iBaseLen + ($iContextCount * 29) ; Each accept item is 29 bytes
                        Local $sHexTotalLen = Hex($iTotalLen, 8)
                        
                        ; 3. Constructing A-ASSOCIATE-AC [cite: 11]
                        Local $bAssocAccept = Binary( _
                            "0x0200" & $sHexTotalLen & _                     ; PDU Type 02, Dynamic Length
                            "00010000" & _                                   ; Protocol Version 1 [cite: 13]
                            "4155544F49545F534350202020202020" & _           ; Called AE (AUTOIT_SCP padded) [cite: 14]
                            "414E592D534355202020202020202020" & _           ; Calling AE (ANY-SCU padded) [cite: 14]
                            "0000000000000000000000000000000000000000000000000000000000000000" & _ ; Reserved 32 bytes [cite: 14]
                            "10000015312E322E3834302E31303030382E332E312E312E31" & _ ; App Context (1.2.840.10008.3.1.1.1) [cite: 15]
                            $sContextAccepts & _                             ; Injected dynamic Context ID Accepts
                            "500000085100000400004000" _                     ; User Info: Max PDU Size 16384 [cite: 17]
                        )
                        TCPSend($hConnectedSocket, $bAssocAccept) 
                        ConsoleWrite("   [SEND] A-ASSOCIATE-AC (Connection Accepted)" & @CRLF) 

                    Case 4
                        ; PDU 0x04: P-DATA-TF (Data Transfer) 
                        
                        ; Extract the Context ID specifically used for this message (Byte 11)
                        Local $sContextID = Hex(BinaryMid($bRecv, 11, 1))
                        
                        ; Determine the Command Field: C-ECHO (0x0030) or C-FIND (0x0020)
                        Local $sHexStream = Hex($bRecv)
                        
                        If StringInStr($sHexStream, "00010000020000003000") Then
                            ConsoleWrite("   [RECV] P-DATA-TF (C-ECHO Request on Context " & Dec($sContextID) & ")" & @CRLF)
                            
                            ; Constructing C-ECHO-RSP (Success) 
                            Local $bCEchoRsp = Binary( _
                                "0x04000000003C" & _                         
                                "00000038" & $sContextID & "03" & _           
                                "00000000040000002E000000" & _                 
                                "0200000012000000312E322E3834302E31303030382E312E3100" & _ 
                                "00010000020000003080" & _                      
                                "20010000020000000100" & _                    
                                "00080000020000000101" & _                     
                                "00090000020000000000" _                       
                            )
                            TCPSend($hConnectedSocket, $bCEchoRsp) 
                            ConsoleWrite("   [SEND] P-DATA-TF (C-ECHO Response SUCCESS)" & @CRLF) 
                            
                        ElseIf StringInStr($sHexStream, "00010000020000002000") Then
                            ConsoleWrite("   [RECV] P-DATA-TF (C-FIND Request on Context " & Dec($sContextID) & ")" & @CRLF)
                            

                            Local $bCFindRsp = Binary( _
                                "0x040000000058" & _                            
                                "52000000" & $sContextID & "03" & _          
                                "000000000400000046000000" & _                  
                                "0200000016000000312E322E3834302E31303030382E352E312E342E3331" & _ 
                                "00010000020000002080" & _                
                                "20010000020000000000" & _                    
                                "00080000020000000101" & _                     
                                "00090000020000000000" _                         
                            )
                            TCPSend($hConnectedSocket, $bCFindRsp)
                            ConsoleWrite("   [SEND] P-DATA-TF (C-FIND Response SUCCESS - 0 Matches)" & @CRLF)
                            
                        Else
                            ConsoleWrite("   [RECV] P-DATA-TF (Unknown Command)" & @CRLF)
                        EndIf

                    Case 5
                        ; PDU 0x05: A-RELEASE-RQ (Release Request) 
                        ConsoleWrite("   [RECV] A-RELEASE-RQ (Client is dropping connection)" & @CRLF)
                        
                        ; Constructing A-RELEASE-RP (Release Response) 
                        Local $bReleaseRsp = Binary("0x06000000000400000000") 
                        TCPSend($hConnectedSocket, $bReleaseRsp)
                        ConsoleWrite("   [SEND] A-RELEASE-RP (Goodbye!)" & @CRLF)
                        
                    Case Else
                        ConsoleWrite("   [RECV] Unknown PDU Type: " & $iPDUType & @CRLF)
                EndSwitch
            EndIf
            
            Sleep(10) ; Prevent high CPU usage 
        WEnd
    EndIf
    Sleep(50) 
WEnd

; Cleanup 
TCPShutdown()