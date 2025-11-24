#NoEnv
#SingleInstance Force
SetWorkingDir %A_ScriptDir%
SetBatchLines, -1
Process, Priority,, High

DllCall("winmm.dll\timeBeginPeriod", UInt, 1)

; ========== USER CONFIGURATION ==========
; Main Settings
PanKey := "MButton"                ; Mouse button to hold for camera drag

; Speed and Responsiveness
BasePanSpeed := 0.0341              ; Base pan speed (calibrated for zoom 1.0)
InvertX := 1                        ; Invert X axis (1 = yes, 0 = no)
InvertY := 1                        ; Invert Y axis (1 = yes, 0 = no)

; Adaptive Smoothing
SmoothingSlow := 0.5               ; Smoothing for slow/precise movements
SmoothingFast := 1.2                ; Smoothing for fast movements (>1 creates snappy acceleration)
SpeedThreshold := 15.0               ; Speed threshold to transition between smooth values

; Zoom Compensation
BaseZoom := 1.0                     ; Zoom level where movement is 1:1
ZoomCompensationStrength := 1.0     ; 0 = no zoom compensation, 1.0 = full compensation

; Isometric View Compensation
HorizontalMultiplier := 0.42        ; Adjusts left-right movement speed
VerticalMultiplier := 0.86          ; Adjusts up-down movement speed

; Dead Zones
DeadZonePixels := 1.5               ; Ignore mouse movements smaller than this (reduces jitter)
MinWriteThreshold := 0.0000005       ; Minimum change before updating camera position

; Anti-Stairstepping for Diagonal Movement
DiagonalBoost := 1.0                ; Boost diagonal movement (1.0 = no boost)
DiagonalDeadZone := 2.5             ; Threshold for detecting diagonal movement

; ========== MEMORY ADDRESSES ==========
baseOffset := 0x03F0DD38
offset1 := 0x28
cameraXOffset := 0x2F8
cameraYOffset := 0x2FC
zoomBaseOffset := 0x03F07C28
zoomOffset := 0xB8C

; ========== MODULE BASE ADDRESS FUNCTION ==========
GetModuleBaseAlt(moduleName)
{
    Process, Exist, %moduleName%
    if (ErrorLevel = 0)
        return 0
    pid := ErrorLevel
    
    hProcess := DllCall("OpenProcess", "UInt", 0x0410, "Int", false, "UInt", pid, "Ptr")
    if (!hProcess)
        return 0
    
    VarSetCapacity(hMods, 8000, 0)
    cbNeeded := 0
    
    result := DllCall("Psapi.dll\EnumProcessModulesEx", "Ptr", hProcess, "Ptr", &hMods, "UInt", 8000, "UInt*", cbNeeded, "UInt", 0x03)
    
    if (!result)
    {
        DllCall("CloseHandle", "Ptr", hProcess)
        return 0
    }
    
    firstModule := NumGet(hMods, 0, "Ptr")
    
    VarSetCapacity(MODULEINFO, 24, 0)
    DllCall("Psapi.dll\GetModuleInformation", "Ptr", hProcess, "Ptr", firstModule, "Ptr", &MODULEINFO, "UInt", 24)
    
    baseAddress := NumGet(MODULEINFO, 0, "Ptr")
    
    DllCall("CloseHandle", "Ptr", hProcess)
    
    return baseAddress
}

; ========== MEMORY FUNCTIONS ==========
GetProcessHandle()
{
    Process, Exist, AoE2DE_s.exe
    if (ErrorLevel = 0)
        return 0
    pid := ErrorLevel
    return DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", false, "UInt", pid, "Ptr")
}

ReadFloat(hProcess, address)
{
    VarSetCapacity(buffer, 4, 0)
    DllCall("ReadProcessMemory", "Ptr", hProcess, "Ptr", address, "Ptr", &buffer, "UInt", 4, "Ptr", 0)
    return NumGet(buffer, 0, "Float")
}

WriteFloat(hProcess, address, value)
{
    VarSetCapacity(buffer, 4, 0)
    NumPut(value, buffer, 0, "Float")
    DllCall("WriteProcessMemory", "Ptr", hProcess, "Ptr", address, "Ptr", &buffer, "UInt", 4, "Ptr", 0)
}

ReadPointerCorrect(hProcess, baseAddr)
{
    VarSetCapacity(buffer, 8, 0)
    DllCall("ReadProcessMemory", "Ptr", hProcess, "Ptr", baseAddr, "Ptr", &buffer, "UInt", 8, "Ptr", 0)
    addr := NumGet(buffer, 0, "Int64")
    
    addr := addr + 0x28
    
    VarSetCapacity(buffer2, 8, 0)
    DllCall("ReadProcessMemory", "Ptr", hProcess, "Ptr", addr, "Ptr", &buffer2, "UInt", 8, "Ptr", 0)
    addr := NumGet(buffer2, 0, "Int64")
    
    return addr
}

ReadZoomPointer(hProcess, baseAddr)
{
    VarSetCapacity(buffer, 8, 0)
    DllCall("ReadProcessMemory", "Ptr", hProcess, "Ptr", baseAddr, "Ptr", &buffer, "UInt", 8, "Ptr", 0)
    addr := NumGet(buffer, 0, "Int64")
    return addr
}

; ========== PERFORMANCE COUNTER ==========
QPCInit()
{
    DllCall("QueryPerformanceFrequency", "Int64*", freq)
    return freq
}

QPCNow()
{
    DllCall("QueryPerformanceCounter", "Int64*", counter)
    return counter
}

; ========== MAIN SCRIPT ==========
#IfWinActive, ahk_exe AoE2DE_s.exe

Hotkey, %PanKey%, StartPan
return

StartPan:
    hProcess := GetProcessHandle()
    if (!hProcess)
    {
        ToolTip, Cannot find AoE2DE_s.exe!
        Sleep, 1000
        ToolTip
        return
    }
    
    moduleBase := GetModuleBaseAlt("AoE2DE_s.exe")
    
    if (!moduleBase)
    {
        ToolTip, Cannot find module base!
        Sleep, 1000
        ToolTip
        DllCall("CloseHandle", "Ptr", hProcess)
        return
    }
    
    ; Get camera addresses
    baseAddr := moduleBase + baseOffset
    cameraBase := ReadPointerCorrect(hProcess, baseAddr)
    cameraXAddr := cameraBase + cameraXOffset
    cameraYAddr := cameraBase + cameraYOffset
    
    ; Get zoom address
    zoomBaseAddr := moduleBase + zoomBaseOffset
    zoomBase := ReadZoomPointer(hProcess, zoomBaseAddr)
    zoomAddr := zoomBase + zoomOffset
    
    ; Initialize timing
    perfFreq := QPCInit()
    lastTime := QPCNow()
    
    MouseGetPos, lastX, lastY
    
    velX := 0
    velY := 0
    
    lastWrittenX := ReadFloat(hProcess, cameraXAddr)
    lastWrittenY := ReadFloat(hProcess, cameraYAddr)
    
    ; Default zoom value in case reading fails
    lastGoodZoom := 1.0
    
    While GetKeyState(PanKey, "P")
    {
        currentTime := QPCNow()
        deltaTime := (currentTime - lastTime) / perfFreq * 1000
        
        if (deltaTime > 50)
            deltaTime := 50
        if (deltaTime < 1)
            deltaTime := 1
            
        timeMultiplier := deltaTime / 16.0
        lastTime := currentTime
        
        ; Read current zoom level
        currentZoom := ReadFloat(hProcess, zoomAddr)
        
        ; Validate zoom value
        if (currentZoom < 0.1 || currentZoom > 5.0)
        {
            currentZoom := lastGoodZoom
        }
        else
        {
            lastGoodZoom := currentZoom
        }
        
        ; Apply inverse zoom compensation
        if (ZoomCompensationStrength > 0)
        {
            zoomMultiplier := BaseZoom / currentZoom
            zoomMultiplier := 1.0 + (zoomMultiplier - 1.0) * ZoomCompensationStrength
            PanSpeed := BasePanSpeed * zoomMultiplier
        }
        else
        {
            PanSpeed := BasePanSpeed
        }
        
        MouseGetPos, currentX, currentY
        
        rawDeltaX := currentX - lastX
        rawDeltaY := currentY - lastY
        
        if (Abs(rawDeltaX) < DeadZonePixels)
            rawDeltaX := 0
        if (Abs(rawDeltaY) < DeadZonePixels)
            rawDeltaY := 0
        
        if (rawDeltaX = 0 && rawDeltaY = 0)
        {
            Sleep, 3
            continue
        }
        
        lastX := currentX
        lastY := currentY
        
        screenDeltaX := rawDeltaX * PanSpeed * timeMultiplier
        screenDeltaY := rawDeltaY * PanSpeed * timeMultiplier
        
        isDiagonal := (Abs(rawDeltaX) > DiagonalDeadZone) && (Abs(rawDeltaY) > DiagonalDeadZone)
        diagonalMultiplier := isDiagonal ? DiagonalBoost : 1.0
        
        screenDeltaX *= HorizontalMultiplier
        screenDeltaY *= VerticalMultiplier
        
        ; Direct isometric conversion
        isoDeltaX := (screenDeltaX - screenDeltaY) * 0.707 * diagonalMultiplier
        isoDeltaY := (screenDeltaX + screenDeltaY) * 0.707 * diagonalMultiplier
        
        if (InvertX)
            isoDeltaX := -isoDeltaX
        if (InvertY)
            isoDeltaY := -isoDeltaY
        
        ; Calculate movement speed for adaptive smoothing
        movementSpeed := Sqrt(rawDeltaX**2 + rawDeltaY**2)
        
        ; Interpolate smoothing based on movement speed
        ; Slow movements get 0.85, fast movements get 1.4
        if (movementSpeed < SpeedThreshold)
        {
            ; For slow movements, use more smoothing
            currentSmoothing := SmoothingSlow
        }
        else
        {
            ; Linearly interpolate between slow and fast smoothing
            ; Speed range: SpeedThreshold to SpeedThreshold*5
            speedRatio := (movementSpeed - SpeedThreshold) / (SpeedThreshold * 4)
            speedRatio := speedRatio > 1 ? 1 : speedRatio  ; Clamp to 1
            currentSmoothing := SmoothingSlow + (SmoothingFast - SmoothingSlow) * speedRatio
        }
        
        ; Apply velocity smoothing
        velX := velX * (1 - currentSmoothing) + isoDeltaX * currentSmoothing
        velY := velY * (1 - currentSmoothing) + isoDeltaY * currentSmoothing
        
        ; Update camera position with smoothed velocity
        if (Abs(velX) > MinWriteThreshold || Abs(velY) > MinWriteThreshold)
        {
            camX := ReadFloat(hProcess, cameraXAddr)
            camY := ReadFloat(hProcess, cameraYAddr)
            
            newX := camX + velX
            newY := camY + velY
            
            newX := (newX < 0) ? 0 : (newX > 360) ? 360 : newX
            newY := (newY < 0) ? 0 : (newY > 360) ? 360 : newY
            
            if (Abs(newX - lastWrittenX) > MinWriteThreshold || Abs(newY - lastWrittenY) > MinWriteThreshold)
            {
                WriteFloat(hProcess, cameraXAddr, newX)
                WriteFloat(hProcess, cameraYAddr, newY)
                lastWrittenX := newX
                lastWrittenY := newY
            }
        }
        
        Sleep, 3
    }
    
    ToolTip
    DllCall("CloseHandle", "Ptr", hProcess)
    DllCall("winmm.dll\timeEndPeriod", UInt, 1)
return

; ========== HOTKEYS ==========

; Reload script for testing
^!r::Reload

; Show current zoom level
^!z::
    hProcess := GetProcessHandle()
    if (!hProcess)
    {
        ToolTip, Cannot find AoE2DE_s.exe!
        Sleep, 2000
        ToolTip
        return
    }
    
    moduleBase := GetModuleBaseAlt("AoE2DE_s.exe")
    if (!moduleBase)
    {
        ToolTip, Cannot find module base!
        Sleep, 2000
        ToolTip
        DllCall("CloseHandle", "Ptr", hProcess)
        return
    }
    
    zoomBaseAddr := moduleBase + zoomBaseOffset
    zoomBase := ReadZoomPointer(hProcess, zoomBaseAddr)
    zoomAddr := zoomBase + zoomOffset
    currentZoom := ReadFloat(hProcess, zoomAddr)
    
    zoomMultiplier := BaseZoom / currentZoom
    adjustedSpeed := BasePanSpeed * zoomMultiplier
    
    ToolTip, % "Current Zoom: " . currentZoom . "`nZoom Multiplier: " . Round(zoomMultiplier, 2) . "`nEffective Speed: " . Round(adjustedSpeed, 4)
    Sleep, 3000
    ToolTip
    
    DllCall("CloseHandle", "Ptr", hProcess)
return

; Exit script
^!x::
    DllCall("winmm.dll\timeEndPeriod", UInt, 1)
    ExitApp
return


#IfWinActive
