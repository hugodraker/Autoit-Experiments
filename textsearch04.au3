; Include necessary libraries and declare GUI-related variables
#include <GUIConstants.au3>
#include <FileConstants.au3>

Global $searchText = "" ; Search text input field
Global $outputListView = 0 ; Output listview control

; Create the main window with a resizable border
Local $mainWindow = GUICreate("Search and Display", 900, 600)
;GUISetResizable()

; Set up GUI elements
$searchTextBox = GUICtrlCreateEdit("", 10, 10, 770, 20) ; Search text input field
$findButton = GUICtrlCreateButton("Find", 790, 9, 80, 25) ; Find button
$outputListView = GUICtrlCreateListView("Line Number", "Line Content", 100, 100, 200, 150) ; Output listview control

; Set up event handlers for GUI elements
GUISetOnEvent($searchTextBox, "_Search")
;GUICtrlSetResizing($searchTextBox)

GUISetOnEvent($findButton, "_Find")

GUISetState(@SW_SHOW, $mainWindow)

; Main script loop
While 1
    Sleep(100)
WEnd

; Event handler functions
Func _Search()
    ; No-op for now, will be used to update the search text input field
EndFunc

Func _Find()
    Local $searchText = GUICtrlRead($searchTextBox)

    If $searchText <> "" Then
        Local $fileList = FileListToArray(@ScriptDir() & "\Xtron-8tb.txt", "*") ; Assuming the file is in the same directory as the script
        Local $lineNumbers = [] ; Array to store line numbers and content

        For $i = 0 To UBound($fileList) - 1
            If FileOpen($fileList[$i], 16) Then
                Local $fileHandle = FileOpen($fileList[$i], 16)
                While 1
                    Local $line = FileReadLine($fileHandle)
                    If @error Then ExitLoop

                    ; Search for the specified text in each line
                    If StringInStr($line, $searchText) Then
                        ; Extract the file name and line number from the file path
                        Local $filePath = $fileList[$i]
                        Local $lineNumber = 1 + FileCountLines($fileList[$i]) - 1

                        ; Add to output listview control
                        GUICtrlListView_AddItem($outputListView, $lineNumber & " | " & $line)
                    EndIf
                WEnd
                FileClose($fileHandle)
            EndIf
        Next

        ; Update the GUI with the new results
        GUICtrlSetData($outputListView, "")
    EndIf
EndFunc
