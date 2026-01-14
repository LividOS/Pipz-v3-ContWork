#Requires AutoHotkey >=2.0 <3.0
#Warn All

; =========================================================
; Pipz MAINTEMPLATE - Worker (AHK v2)
; Version: 1.0.7
; Last change: Refactored to Autohotkey v2
; =========================================================

; --- Global Variables ---
global g_SettingsLastWrite := ""
global g_GameTitle := ""
global g_ShowOverlay := 1
global g_OvershootEnabled := 1
global g_OvershootPercent := 5
global g_MicroDelayEnabled := 1
global g_MicroDelayMax := 60
global g_MicroDelayChance := 25
global g_BreaksEnabled := 0
global g_BreakChance := 0
global g_BreakCooldownMin := 3

secret := "PIPSECMAX_LIREGKEY_11711503721976861054928319"
keyFile := A_ScriptDir "\license.key"
settingsFile := A_ScriptDir "\settings"

; =========================
; LICENSE CHECK
; =========================

if !FileExist(keyFile) {
    MsgBox("Failed to locate License.`n`nScript Automatically Terminated.")
    ExitApp()
}

cipherB64 := FileRead(keyFile)
cipherB64 := RegExReplace(cipherB64, "\s+")

try {
    payload := License_Deobfuscate_FromBase64(cipherB64, secret)
} catch Any as e {
    MsgBox("Failed to decrypt License.`n`nError: " e.Message)
    ExitApp()
}

; Parse decrypted payload
expires := "", id := "", hash := ""
Loop Parse, payload, "`n", "`r" {
    if RegExMatch(A_LoopField, "(.+?)=(.+)", &m) {
        k := Trim(m[1]), v := Trim(m[2])
        if (k = "EXPIRES")
            expires := v
        else if (k = "ID")
            id := v
        else if (k = "HASH")
            hash := v
    }
}

if (expires = "" || id = "" || hash = "") {
    MsgBox("Failed to validate License file.`n`nScript Automatically Terminated.")
    ExitApp()
}

if !RegExMatch(id, "i)^[0-9a-f]{32}$") {
    MsgBox("Invalid License ID format.`n`nScript Automatically Terminated.")
    ExitApp()
}

expected := SHA256_HEX(expires "|" id "|" secret)
if (expected != hash) {
    MsgBox("License file has been modified or is invalid.`n`nScript Automatically Terminated.")
    ExitApp()
}

if (SubStr(A_NowUTC, 1, 8) > expires) {
    MsgBox("License has expired.`n`nScript Automatically Terminated.")
    ExitApp()
}

; License valid — script continues
SetTimer(WorkerHeartbeat, 1000)
WorkerHeartbeat() {
    ToolTip("Script online")
}

; =========================
; Settings Loader
; =========================

LoadSetting(section, key, default) {
    return IniRead(settingsFile, section, key, default)
}

SetTimer(RefreshSettings, 250)

RefreshSettings() {
    global ; Allow modification of all global vars
    if !FileExist(settingsFile)
        return

    curWrite := FileGetTime(settingsFile, "M")
    if (curWrite = g_SettingsLastWrite)
        return
    g_SettingsLastWrite := curWrite

    ; General
    g_GameTitle := Trim(LoadSetting("General", "GameTitle", ""))
    if (g_GameTitle = "C:")
        g_GameTitle := ""
    g_ShowOverlay := (LoadSetting("General", "ShowOverlay", 1) != 0) ? 1 : 0

    ; AntiBan - MicroDelay
    tmp := LoadSetting("AntiBan", "MicroDelayEnabled", "")
    if (tmp = "")
        tmp := LoadSetting("AntiBan", "RandSleepEnabled", g_MicroDelayEnabled)
    g_MicroDelayEnabled := (tmp != 0) ? 1 : 0

    tmp := LoadSetting("AntiBan", "MicroDelayMax", "")
    if (tmp = "")
        tmp := LoadSetting("AntiBan", "RandSleepMax", 60)
    g_MicroDelayMax := IsInteger(tmp) ? Integer(tmp) : 60
    g_MicroDelayMax := Clamp(g_MicroDelayMax, 0, 5000)

    tmp := LoadSetting("AntiBan", "MicroDelayChance", "")
    if (tmp = "")
        tmp := LoadSetting("AntiBan", "RandSleepChance", 25)
    g_MicroDelayChance := IsInteger(tmp) ? Integer(tmp) : 25
    g_MicroDelayChance := Clamp(g_MicroDelayChance, 0, 100)

    ; AntiBan - Breaks
    g_BreaksEnabled := (LoadSetting("AntiBan", "BreaksEnabled", 0) != 0) ? 1 : 0
    
    tmp := LoadSetting("AntiBan", "BreakChance", 0)
    g_BreakChance := IsInteger(tmp) ? Integer(tmp) : 0
    g_BreakChance := Clamp(g_BreakChance, 0, 100)

    tmp := LoadSetting("AntiBan", "BreakCooldownMin", 3)
    g_BreakCooldownMin := IsInteger(tmp) ? Integer(tmp) : 3
    g_BreakCooldownMin := Clamp(g_BreakCooldownMin, 0, 120)

    ; AntiBan - Overshoot
    g_OvershootEnabled := (LoadSetting("AntiBan", "OvershootEnabled", 1) != 0) ? 1 : 0
    tmp := LoadSetting("AntiBan", "Overshoot", 5)
    g_OvershootPercent := IsNumber(tmp) ? Float(tmp) : 5.0
    g_OvershootPercent := Clamp(g_OvershootPercent, 0, 100)
}

Clamp(val, min, max) => (val < min) ? min : (val > max ? max : val)

; =========================
; AntiBan Functions
; =========================

AB_Checkpoint() {
    AB_MaybeBreak()
    AB_MicroDelay()
}

AB_MicroDelay() {
    if (!g_MicroDelayEnabled || g_MicroDelayMax <= 0 || g_MicroDelayChance <= 0)
        return

    if (Random(1, 100) > g_MicroDelayChance)
        return

    extra := Random(0, g_MicroDelayMax)
    if (extra > 0)
        Sleep(extra)
}

AB_MaybeBreak() {
    static lastEvalTick := 0
    static lastBreakTick := 0

    if (!g_BreaksEnabled || g_BreakChance <= 0)
        return

    now := A_TickCount
    if (now - lastEvalTick < 10000)
        return
    lastEvalTick := now

    minBetweenBreaksMs := g_BreakCooldownMin * 60000
    if (lastBreakTick && (now - lastBreakTick < minBetweenBreaksMs))
        return

    if (Random(1, 100) > g_BreakChance)
        return

    pick := Random(1, 100)
    if (pick <= 80)
        AB_DoBreak(1000, 5000)
    else if (pick <= 95)
        AB_DoBreak(10000, 30000)
    else if (pick <= 99)
        AB_DoBreak(60000, 180000)
    else
        AB_DoBreak(300000, 900000)

    lastBreakTick := A_TickCount
}

AB_DoBreak(minMs, maxMs) {
    Sleep(Random(minMs, Max(minMs, maxMs)))
}

AB_Sleep(baseMs) {
    AB_Checkpoint()
    Sleep(Max(0, baseMs))
}

; =========================
; CRYPTO / BINARY HELPERS
; =========================

SHA256_HEX(str) {
    static PROV_RSA_AES := 24, CRYPT_VERIFYCONTEXT := 0xF0000000, CALG_SHA_256 := 0x0000800C, HP_HASHVAL := 0x0002
    hProv := 0, hHash := 0
    
    if !DllCall("Advapi32\CryptAcquireContextW", "Ptr*", &hProv, "Ptr", 0, "Ptr", 0, "UInt", PROV_RSA_AES, "UInt", CRYPT_VERIFYCONTEXT)
        throw Error("CryptAcquireContext failed")

    if !DllCall("Advapi32\CryptCreateHash", "Ptr", hProv, "UInt", CALG_SHA_256, "Ptr", 0, "UInt", 0, "Ptr*", &hHash) {
        DllCall("Advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)
        throw Error("CryptCreateHash failed")
    }

    ; Convert str to ANSI (AStr) to match v1 behavior
    if !DllCall("Advapi32\CryptHashData", "Ptr", hHash, "AStr", str, "UInt", StrLen(str), "UInt", 0) {
        DllCall("Advapi32\CryptDestroyHash", "Ptr", hHash)
        DllCall("Advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)
        throw Error("CryptHashData failed")
    }

    hashBuf := Buffer(32)
    cbHash := 32
    if !DllCall("Advapi32\CryptGetHashParam", "Ptr", hHash, "UInt", HP_HASHVAL, "Ptr", hashBuf, "UInt*", &cbHash, "UInt", 0) {
        DllCall("Advapi32\CryptDestroyHash", "Ptr", hHash)
        DllCall("Advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)
        throw Error("CryptGetHashParam failed")
    }

    DllCall("Advapi32\CryptDestroyHash", "Ptr", hHash)
    DllCall("Advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)
    
    return BytesToLowerHex(hashBuf)
}

BytesToLowerHex(buf) {
    hex := ""
    Loop buf.Size {
        hex .= Format("{:02x}", NumGet(buf, A_Index-1, "UChar"))
    }
    return hex
}

Base64_Decode(b64, &outBin) {
    static CRYPT_STRING_BASE64_ANY := 0x6
    binLen := 0
    DllCall("Crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", CRYPT_STRING_BASE64_ANY, "Ptr", 0, "UInt*", &binLen, "Ptr", 0, "Ptr", 0)
    outBin := Buffer(binLen)
    DllCall("Crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", CRYPT_STRING_BASE64_ANY, "Ptr", outBin, "UInt*", &binLen, "Ptr", 0, "Ptr", 0)
    return binLen
}

License_Deobfuscate_FromBase64(b64Text, secret) {
    decodedLen := Base64_Decode(b64Text, &blob)
    if (decodedLen < 17)
        throw Error("License blob too short")

    salt := Buffer(16)
    DllCall("RtlMoveMemory", "Ptr", salt, "Ptr", blob, "UPtr", 16)

    ctLen := decodedLen - 16
    ct := Buffer(ctLen)
    DllCall("RtlMoveMemory", "Ptr", ct, "Ptr", blob.Ptr + 16, "UPtr", ctLen)

    saltHex := BytesToLowerHex(salt)
    
    ; Create keystream bytes
    hProv := 0, hHash := 0
    DllCall("Advapi32\CryptAcquireContextW", "Ptr*", &hProv, "Ptr", 0, "Ptr", 0, "UInt", 24, "UInt", 0xF0000000)
    DllCall("Advapi32\CryptCreateHash", "Ptr", hProv, "UInt", 0x800C, "Ptr", 0, "UInt", 0, "Ptr*", &hHash)
    ksKey := saltHex "|" secret
    DllCall("Advapi32\CryptHashData", "Ptr", hHash, "AStr", ksKey, "UInt", StrLen(ksKey), "UInt", 0)
    keyBytes := Buffer(32)
    cbHash := 32
    DllCall("Advapi32\CryptGetHashParam", "Ptr", hHash, "UInt", 2, "Ptr", keyBytes, "UInt*", &cbHash, "UInt", 0)
    DllCall("Advapi32\CryptDestroyHash", "Ptr", hHash)
    DllCall("Advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)

    pt := Buffer(ctLen)
    Loop ctLen {
        b := NumGet(ct, A_Index-1, "UChar")
        kk := NumGet(keyBytes, Mod(A_Index-1, 32), "UChar")
        NumPut("UChar", b ^ kk, pt, A_Index-1)
    }

    return StrGet(pt, "UTF-8")
}

;--------------------------------------------------------------------------------;
;********************************************************************************;

; Code below controls the humanlike mousemovements, added at end of the script so we can use the
; MoveMouse function

;********************************************************************************;
;--------------------------------------------------------------------------------;
;  v1.7										 ;
;  Original script by: Flight in Pascal					         ;
;  Link: https://github.com/SRL/SRL/blob/master/shared/mouse.simba               ;
;  More Flight's mouse moves: https://paste.villavu.com/show/3279/       	 ;
;  ModIfied script with simpler method MoveMouse() by: dexon in C#           	 ;
;  Conversion from C# into AHK by: HowDoIStayInDreams, with the help of Arekusei ;
;  Refactor & Rewrite v1.6+ by Pipz ;
;--------------------------------------------------------------------------------;
;--------------------------------------------------------------------------------;
;  Changelog:									 ;
;  v1.3 added dynamic mouse speed					 	 ;
;  v1.4 added acceleration and brake, shout-out to kl and Lazy			 ;
;  v1.5 fixed jiggle at the destination (pointed out by Sound)                   ;
;	added smoother Sleep function		   			 	 ;
; 	maxStep is now more dynamic, using GlitchedSoul's weighted Random	 ;
;  v1.6 added dynamic path weaving and smoothing 
;       added randomised destination overshoot and correction
;       changed from square randomization to circular 
;       added muscle memory simulation and decay
;  v1.7 refactored and updated compatibility to autohotkey v2+
;--------------------------------------------------------------------------------;
;*********************************************************************************

;--------------------------------------------------------------------------------;
; Human-like Mouse Movements for AHK v2
;--------------------------------------------------------------------------------;

MoveMouse(x, y, speed := "", RD := "") {
    if (speed == "") {
        speed := Random(25, 30) / 10.0
    }

    angleDeg := Random(0, 360)
    angleRad := angleDeg * (3.14159 / 180)
    distance := Sqrt(Random(0, 100) / 100.0) * 15  ; 15px radius 

    offsetX := Cos(angleRad) * distance
    offsetY := Sin(angleRad) * distance

    targetX := x + offsetX
    targetY := y + offsetY

    ;-----------------------------
    ; overshoot / muscle memory
    ;-----------------------------
    static MuscleMemory := Map()  ; key = "x|y", value = {val: reduction, lastTime: A_TickCount}
    MEMORY_DECAY_INTERVAL := 10000
    MEMORY_DECAY_RATE := 0.01

    MouseGetPos(&startX, &startY)
    distX := targetX - startX
    distY := targetY - startY
    distanceTotal := Hypot(distX, distY)

    ; Accessing global settings (Assumed these are defined elsewhere in your script)
    global g_OvershootEnabled, g_OvershootPercent
    
    ; --- Corrected Global Variable Check ---
    try {
        overshootEnabled := g_OvershootEnabled
    } catch {
        overshootEnabled := false
    }

    try {
        baseOvershoot := g_OvershootPercent / 100.0
    } catch {
        baseOvershoot := 0
    }

    overshootOccurred := false
    overshootX := targetX
    overshootY := targetY

    if (overshootEnabled && baseOvershoot > 0) {
        targetKey := Round(targetX) "|" Round(targetY)
        reduction := 0
        
        if (MuscleMemory.Has(targetKey)) {
            mem := MuscleMemory[targetKey]
            elapsed := A_TickCount - mem.lastTime
            decaySteps := Floor(elapsed / MEMORY_DECAY_INTERVAL)
            mem.val := Max(mem.val - (decaySteps * MEMORY_DECAY_RATE), 0)
            MuscleMemory[targetKey] := mem
            reduction := mem.val
        }

        overshootChance := Max(baseOvershoot - reduction, 0)
        
        if (Random(0, 100) < overshootChance * 100) {
            factor := Min(Max(distanceTotal / 500 * 0.03, 0.02), 0.05)
            overshootFactor := Random(factor * 50, factor * 150) / 100
            overshootX := targetX + (distX * overshootFactor)
            overshootY := targetY + (distY * overshootFactor)
            overshootOccurred := true
        }
    }

    if (RD == "RD") {
        goRelative(overshootX, overshootY, speed)
    } else {
        goStandard(overshootX, overshootY, speed)
    }

    if (overshootOccurred) {
        PreciseSleep(6)
        if (RD == "RD") {
            goRelative(targetX - overshootX, targetY - overshootY, speed * 1.5)
        } else {
            goStandard(targetX, targetY, speed * 1.5)
        }

        ; Muscle memory increment
        reductionAmount := 0.01 + (Random(0, 100) / 100) * 0.01
        targetKey := Round(targetX) "|" Round(targetY)

        if (MuscleMemory.Has(targetKey)) {
            mem := MuscleMemory[targetKey]
            mem.val := Min(mem.val + reductionAmount, 0.03)
            mem.lastTime := A_TickCount
            MuscleMemory[targetKey] := mem
        } else {
            MuscleMemory[targetKey] := {val: Min(reductionAmount, 0.03), lastTime: A_TickCount}
        }
    }
}

WindMouse(xs, ys, xe, ye, gravity, wind, minWait, maxWait, maxStep, targetArea, SleepsArray) {
    windX := 0, windY := 0, veloX := 0, veloY := 0
    newX := Round(xs), newY := Round(ys)
    sqrt2 := Sqrt(2), sqrt3 := Sqrt(3), sqrt5 := Sqrt(5)
    dist := Hypot(xe - xs, ye - ys)
    i := 1
    stepVar := maxStep

    Loop {
        wind := Min(wind, dist)
        if (dist >= targetArea) {
            windX := windX / sqrt3 + (Random(0, Round(wind) * 2) - wind) / sqrt5
            windY := windY / sqrt3 + (Random(0, Round(wind) * 2) - wind) / sqrt5
            maxStep := RandomWeight(stepVar / 2, (stepVar + (stepVar / 2)) / 2, stepVar)
        } else {
            windX := windX / sqrt2
            windY := windY / sqrt2
            maxStep := (maxStep < 3) ? 1 : maxStep / 3
        }

        veloX += windX + gravity * (xe - xs) / dist
        veloY += windY + gravity * (ye - ys) / dist

        if (Hypot(veloX, veloY) > maxStep) {
            RandomDist := maxStep / 2 + (Random(0, Round(maxStep)) / 2)
            veloMag := Hypot(veloX, veloY)
            veloX := (veloX / veloMag) * RandomDist
            veloY := (veloY / veloMag) * RandomDist
        }

        oldX := Round(xs), oldY := Round(ys)
        xs += veloX, ys += veloY
        dist := Hypot(xe - xs, ye - ys)

        if (dist <= 1)
            break

        newX := Round(xs), newY := Round(ys)
        if (oldX != newX || oldY != newY)
            MouseMove(newX, newY)

        ; --- FIXED INDEX LOGIC ---
        c := SleepsArray.Length
        if (c > 0) {
            ; If i exceeds array length, stay at the last valid index (c)
            idx := (i > c) ? c : i
            waitSleep := SleepsArray[idx]
            wait := Max(Round(Abs(Random(Float(waitSleep), Float(waitSleep) + 1))), 1)
            PreciseSleep(wait)
        } else {
            PreciseSleep(1) ; Fallback if array is somehow empty
        }
        
        i++
    }

    if (Round(xe) != newX || Round(ye) != newY)
        MouseMove(Round(xe), Round(ye))
}

WindMouse2(xs, ys, xe, ye, gravity, wind, minWait, maxWait, maxStep, targetArea) {
    windX := 0, windY := 0, veloX := 0, veloY := 0
    newX := Round(xs), newY := Round(ys)
    waitDiff := maxWait - minWait
    sqrt2 := Sqrt(2), sqrt3 := Sqrt(3), sqrt5 := Sqrt(5)
    dist := Hypot(xe - xs, ye - ys)
    newArr := []
    stepVar := maxStep

    Loop {
        wind := Min(wind, dist)
        if (dist >= targetArea) {
            windX := windX / sqrt3 + (Random(0, Round(wind) * 2) - wind) / sqrt5
            windY := windY / sqrt3 + (Random(0, Round(wind) * 2) - wind) / sqrt5
            maxStep := RandomWeight(stepVar / 2, (stepVar + (stepVar / 2)) / 2, stepVar)
        } else {
            windX /= sqrt2
            windY /= sqrt2
            maxStep := (maxStep < 3) ? 1 : maxStep / 3
        }
        
        veloX += windX + gravity * (xe - xs) / dist
        veloY += windY + gravity * (ye - ys) / dist

        if (Hypot(veloX, veloY) > maxStep) {
            veloMag := Hypot(veloX, veloY)
            RandomDist := maxStep / 2 + (Random(0, Round(maxStep)) / 2)
            veloX := (veloX / veloMag) * RandomDist
            veloY := (veloY / veloMag) * RandomDist
        }

        oldX := Round(xs), oldY := Round(ys)
        xs += veloX, ys += veloY
        dist := Hypot(xe - xs, ye - ys)

        if (dist <= 1)
            break

        newX := Round(xs), newY := Round(ys)
        step := Hypot(xs - oldX, ys - oldY)
        mean := Round(waitDiff * (step / maxStep) + minWait) / 7
        wait := Muller((mean) / 2, (mean) / 2.718281)
        newArr.Push(wait)
    }
    return newArr
}

Hypot(dx, dy) => Sqrt(dx * dx + dy * dy)

PreciseSleep(ms) {
    DllCall("QueryPerformanceFrequency", "Int64*", &freq := 0)
    DllCall("QueryPerformanceCounter", "Int64*", &CounterBefore := 0)
    CounterAfter := CounterBefore
    while (((CounterAfter - CounterBefore) / freq * 1000) < ms) {
        DllCall("QueryPerformanceCounter", "Int64*", &CounterAfter)
    }
}

Muller(m, s) {
    static i := 0, Y := 0
    if (i := !i) {
        U := Sqrt(-2 * Ln(Random(0.0, 1.0))) * s
        VV := Random(0.0, 6.2831853071795862)
        Y := m + U * Sin(VV)
        return m + U * Cos(VV)
    }
    return Y
}

SortArray(arr, order := "A") {
    ; Simple Bubble Sort for v2 Array compliance
    Loop arr.Length {
        idx := A_Index
        Loop arr.Length - idx {
            j := A_Index
            if (order = "A" ? (arr[j] > arr[j+1]) : (arr[j] < arr[j+1])) {
                temp := arr[j]
                arr[j] := arr[j+1]
                arr[j+1] := temp
            }
        }
    }
}

RandomWeight(minVal, target, maxVal) {
    Rmin := Random(minVal, target)
    Rmax := Random(target, maxVal)
    return Random(Rmin, Rmax)
}

goStandard(x, y, speed) {
    MouseGetPos(&xpos, &ypos)
    distance := (Sqrt(Hypot(x - xpos, y - ypos))) * speed
    dynamicSpeed := (1 / Max(distance, 1)) * 60
    finalSpeed := Random(dynamicSpeed, dynamicSpeed + 0.8)
    stepArea := Max((finalSpeed / 2 + distance) / 10, 0.1)
    
    newArr := WindMouse2(xpos, ypos, x, y, 10, 3, finalSpeed * 10, finalSpeed * 12, stepArea * 11, stepArea * 7)
    SortArray(newArr, "D")
    
    half := Floor(newArr.Length / 2)
    while (newArr.Length > half)
        newArr.Pop()

    newClone := newArr.Clone()
    SortArray(newClone, "A")
    for val in newClone
        newArr.Push(val)

    WindMouse(xpos, ypos, x, y, 10, 3, finalSpeed * 10, finalSpeed * 12, stepArea * 11, stepArea * 7, newArr)
}

goRelative(x, y, speed) {
    MouseGetPos(&xpos, &ypos)
    targetX := xpos + x
    targetY := ypos + y
    distance := (Sqrt(Hypot(targetX - xpos, targetY - ypos))) * speed
    dynamicSpeed := (1 / Max(distance, 1)) * 60
    finalSpeed := Random(dynamicSpeed, dynamicSpeed + 0.8)
    stepArea := Max((finalSpeed / 2 + distance) / 10, 0.1)

    newArr := WindMouse2(xpos, ypos, targetX, targetY, 10, 3, finalSpeed * 10, finalSpeed * 12, stepArea * 11, stepArea * 7)
    SortArray(newArr, "D")
    
    half := Floor(newArr.Length / 2)
    while (newArr.Length > half)
        newArr.Pop()

    newClone := newArr.Clone()
    SortArray(newClone, "A")
    for val in newClone
        newArr.Push(val)

    WindMouse(xpos, ypos, targetX, targetY, 10, 3, finalSpeed * 10, finalSpeed * 12, stepArea * 11, stepArea * 7, newArr)
}