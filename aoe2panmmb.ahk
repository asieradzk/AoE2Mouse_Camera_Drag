#NoEnv
#SingleInstance Force
SetWorkingDir %A_ScriptDir%
SetBatchLines, -1
Process, Priority,, High

DllCall("winmm.dll\timeBeginPeriod", UInt, 1)

PanKey := "MButton"
BasePanSpeed := 0.0341
InvertX := 1
InvertY := 1
SmoothingSlow := 0.5
SmoothingFast := 1.2
SpeedThreshold := 15.0
BaseZoom := 1.0
ZoomCompensationStrength := 1.0
HorizontalMultiplier := 0.42
VerticalMultiplier := 0.86
DeadZonePixels := 1.5
MinWriteThreshold := 0.0000005
DiagonalBoost := 1.0
DiagonalDeadZone := 2.5

baseOffset := 0x03F17268
cameraXOffset := 0x2F8
cameraYOffset := 0x2FC
zoomOffset := 0x39E785C

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
    
    baseAddr := moduleBase + baseOffset
    cameraBase := ReadPointerCorrect(hProcess, baseAddr)
    cameraXAddr := cameraBase + cameraXOffset
    cameraYAddr := cameraBase + cameraYOffset
    
    zoomAddr := moduleBase + zoomOffset
    
    perfFreq := QPCInit()
    lastTime := QPCNow()
    
    MouseGetPos, lastX, lastY
    
    velX := 0
    velY := 0
    
    lastWrittenX := ReadFloat(hProcess, cameraXAddr)
    lastWrittenY := ReadFloat(hProcess, cameraYAddr)
    
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
        
        currentZoom := ReadFloat(hProcess, zoomAddr)
        
        if (currentZoom < 0.1 || currentZoom > 5.0)
        {
            currentZoom := lastGoodZoom
        }
        else
        {
            lastGoodZoom := currentZoom
        }
        
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
        
        isoDeltaX := (screenDeltaX - screenDeltaY) * 0.707 * diagonalMultiplier
        isoDeltaY := (screenDeltaX + screenDeltaY) * 0.707 * diagonalMultiplier
        
        if (InvertX)
            isoDeltaX := -isoDeltaX
        if (InvertY)
            isoDeltaY := -isoDeltaY
        
        movementSpeed := Sqrt(rawDeltaX**2 + rawDeltaY**2)
        
        if (movementSpeed < SpeedThreshold)
        {
            currentSmoothing := SmoothingSlow
        }
        else
        {
            speedRatio := (movementSpeed - SpeedThreshold) / (SpeedThreshold * 4)
            speedRatio := speedRatio > 1 ? 1 : speedRatio
            currentSmoothing := SmoothingSlow + (SmoothingFast - SmoothingSlow) * speedRatio
        }
        
        velX := velX * (1 - currentSmoothing) + isoDeltaX * currentSmoothing
        velY := velY * (1 - currentSmoothing) + isoDeltaY * currentSmoothing
        
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

^!r::Reload

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
    
    zoomAddr := moduleBase + zoomOffset
    currentZoom := ReadFloat(hProcess, zoomAddr)
    
    zoomMultiplier := BaseZoom / currentZoom
    adjustedSpeed := BasePanSpeed * zoomMultiplier
    
    ToolTip, % "Current Zoom: " . currentZoom . "`nZoom Multiplier: " . Round(zoomMultiplier, 2) . "`nEffective Speed: " . Round(adjustedSpeed, 4)
    Sleep, 3000
    ToolTip
    
    DllCall("CloseHandle", "Ptr", hProcess)
return

^!x::
    DllCall("winmm.dll\timeEndPeriod", UInt, 1)
    ExitApp
return

#IfWinActive
