#Requires AutoHotkey v2.0
#SingleInstance Force
CoordMode "Mouse", "Screen"
SetMouseDelay -1
SetDefaultMouseSpeed 0

global FADER_X := [270, 608, 920, 1270, 1600, 1940, 2270]

global FADER_TOP_Y      := 1955
global FADER_BOTTOM_Y   := 2049
global MQ_TITLE         := "MagicQ"
global MIDI_DEVICE_NAME := "LPD8"
global DEBOUNCE_MS      := 120
global POLL_MS          := 50

global pNewVal       := DllCall("GlobalAlloc", "UInt", 0x0040, "UPtr", 8, "Ptr")
global pProcessedVal := DllCall("GlobalAlloc", "UInt", 0x0040, "UPtr", 8, "Ptr")
Loop 8 {
    NumPut "UChar", 255, pNewVal       + A_Index - 1
    NumPut "UChar", 255, pProcessedVal + A_Index - 1
}

global ActiveFader := 0
global MouseDown   := false
global hMidiIn     := 0
global MIDI_CB     := CallbackCreate(OnMidiMessage, "F", 5)

global LogFile := A_Desktop "\ahk_midi_log.txt"
FileAppend "=== Started " A_Now " ===`n", LogFile

OnError(CrashLog)
CrashLog(e, mode) {
    FileAppend "CRASH " A_Now " line=" e.Line " msg=" e.Message "`n", LogFile
    return 1
}

deviceCount := DllCall("winmm\midiInGetNumDevs", "UInt")
deviceIndex := -1

Loop deviceCount {
    idx  := A_Index - 1
    caps := Buffer(76, 0)
    DllCall("winmm\midiInGetDevCapsW", "UInt", idx, "Ptr", caps, "UInt", caps.Size)
    devName := StrGet(caps.Ptr + 8, 32, "UTF-16")
    if InStr(devName, MIDI_DEVICE_NAME)
        deviceIndex := idx
}

if deviceIndex = -1 {
    MsgBox "Could not find " MIDI_DEVICE_NAME, "Device Not Found", "Icon!"
    ExitApp
}

hPtr := Buffer(A_PtrSize, 0)
DllCall("winmm\midiInOpen", "Ptr", hPtr, "UInt", deviceIndex, "Ptr", MIDI_CB, "Ptr", pNewVal, "UInt", 0x30000, "UInt")
global hMidiIn := NumGet(hPtr, 0, "Ptr")

if hMidiIn = 0 {
    MsgBox "midiInOpen failed", "Open Failed", "Icon!"
    ExitApp
}

DllCall("winmm\midiInStart", "Ptr", hMidiIn)
SetTimer PollMidi, POLL_MS
TrayTip "LPD8 active", "MagicQ LPD8", 1

OnMidiMessage(hMidi, wMsg, dwInstance, dwParam1, dwParam2) {
    if wMsg != 0x3C3
        return
    status := dwParam1 & 0xFF
    data1  := (dwParam1 >> 8)  & 0xFF
    data2  := (dwParam1 >> 16) & 0xFF
    if status != 0xB0 or data1 < 1 or data1 > 7
        return
    NumPut "UChar", data2, dwInstance + data1
}

PollMidi() {
    global pNewVal, pProcessedVal, ActiveFader, MouseDown
    global FADER_X, FADER_TOP_Y, FADER_BOTTOM_Y, DEBOUNCE_MS

    Loop 7 {
        cc  := A_Index
        val := NumGet(pNewVal + cc, "UChar")
        if val = 255
            continue
        if val = NumGet(pProcessedVal + cc, "UChar")
            continue
        NumPut "UChar", val, pProcessedVal + cc
        faderRange := FADER_BOTTOM_Y - FADER_TOP_Y
        targetY    := FADER_BOTTOM_Y - Round((val / 127.0) * faderRange)
        targetX    := FADER_X[cc]
        if MouseDown and ActiveFader != cc {
            SendInput "{LButton up}"
            MouseDown := false
        }
        MouseMove targetX, targetY, 0
        if !MouseDown {
            SendInput "{LButton down}"
            MouseDown   := true
            ActiveFader := cc
        }
        SetTimer ReleaseMouseButton, -DEBOUNCE_MS
        break
    }
}

ReleaseMouseButton() {
    global MouseDown, ActiveFader
    if MouseDown {
        SendInput "{LButton up}"
        MouseDown   := false
        ActiveFader := 0
    }
}

Esc:: {
    global hMidiIn, MouseDown, pNewVal, pProcessedVal
    SetTimer PollMidi, 0
    if MouseDown
        SendInput "{LButton up}"
    DllCall("winmm\midiInStop",  "Ptr", hMidiIn)
    DllCall("winmm\midiInClose", "Ptr", hMidiIn)
    DllCall("GlobalFree", "Ptr", pNewVal)
    DllCall("GlobalFree", "Ptr", pProcessedVal)
    ExitApp
}

F1:: {
    global pNewVal, DEBOUNCE_MS, POLL_MS, LogFile
    info := "=== Knob Values ===`n`n"
    Loop 7 {
        val := NumGet(pNewVal + A_Index, "UChar")
        info .= "  Knob " A_Index " -> PB" A_Index "  :  " (val = 255 ? "---" : val) "`n"
    }
    info .= "`n  Debounce: " DEBOUNCE_MS "ms  |  Poll: " POLL_MS "ms`n  ESC quit  |  F1 this window"
    MsgBox info, "MagicQ LPD8 Status", 0
}