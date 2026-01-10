#Requires AutoHotkey >=1.1.33 <2.0 Unicode
#Warn

; =========================================================
; Pipz MAINTEMPLATE - Worker (AHK v1)
; Version: 1.0.2
; Last change: Added AntiBan RandSleep support (controller-driven sleep randomization)
; =========================================================

; =========================
; LICENSE CHECK (AHK v1) - Obfuscated license.key (Base64 + Salt/XOR)
; =========================

secret := "PIPSECMAX_LIREGKEY_11711503721976861054928319"
keyFile := A_ScriptDir "\license.key"

If !FileExist(keyFile)
{
    MsgBox, Failed to locate License.`n`nScript Automatically Terminated.
    ExitApp
}

FileRead, cipherB64, %keyFile%
cipherB64 := RegExReplace(cipherB64, "\s+")  ; remove whitespace/newlines

Try {
    payload := License_Deobfuscate_FromBase64(cipherB64, secret)
} Catch e {
    MsgBox % "Failed to decrypt License.`n`nError: " e.Message
    ExitApp
}

; Parse decrypted payload (plaintext)
expires := ""
id := ""
hash := ""

Loop, Parse, payload, `n, `r
{
    if RegExMatch(A_LoopField, "(.+?)=(.+)", m)
    {
        k := Trim(m1)
        v := Trim(m2)

        if (k = "EXPIRES")
            expires := v
        else if (k = "ID")
            id := v
        else if (k = "HASH")
            hash := v
    }
}

if (expires = "" || id = "" || hash = "")
{
    MsgBox, Failed to validate License file.`n`nScript Automatically Terminated.
    ExitApp
}

; Hardening: ID must be exactly 32 hex chars
if !RegExMatch(id, "i)^[0-9a-f]{32}$")
{
    MsgBox, Invalid License ID format.`n`nScript Automatically Terminated.
    ExitApp
}

expected := SHA256_HEX(expires . "|" . id . "|" . secret)
if (expected != hash)
{
    MsgBox, License file has been modified or is invalid.`n`nScript Automatically Terminated.
    ExitApp
}

if (SubStr(A_NowUTC, 1, 8) > expires)
{
    MsgBox, License has expired.`n`nScript Automatically Terminated.
    ExitApp
}

; ✅ License valid — script continues

; =========================
; TEMP TEST: Keep worker alive + show it's running
; =========================
 #Persistent
 #SingleInstance Force
 SetTimer, WorkerHeartbeat, 1000

 WorkerHeartbeat:
     ToolTip, Script online

; =========================
; Settings file
; =========================
settingsFile := A_ScriptDir "\settings"

g_SettingsLastWrite := ""

LoadSetting(section, key, default) {
    global settingsFile
    IniRead, val, %settingsFile%, %section%, %key%, %default%
    return val
}

; =========================
; AntiBan Sleep Wrapper (AHK v1)
; Use this instead of raw Sleep to apply controller-driven antiban timing.
; =========================
AB_Sleep(baseMs) {
    global g_RandSleepEnabled, g_RandSleepMax, g_RandSleepChance

    ; Apply randomized extra delay (occasionally)
    if (g_RandSleepEnabled && g_RandSleepMax > 0 && g_RandSleepChance > 0) {
        Random, roll, 1, 100
        if (roll <= g_RandSleepChance) {
            Random, extra, 1, %g_RandSleepMax%
            Sleep, %extra%
        }
    }

    ; Always do the intended sleep
    if (baseMs < 0)
        baseMs := 0
    Sleep, %baseMs%
}

; =========================
; Mirrored settings from v2 tool
; =========================

; General (mirrored; v1 can use later if needed)
g_GameTitle := LoadSetting("General", "GameTitle", "C:")
g_ShowOverlay := LoadSetting("General", "ShowOverlay", 1)
g_ShowOverlay := (g_ShowOverlay != 0) ? 1 : 0

; AntiBan - Overshoot (mirrored)
g_OvershootEnabled := LoadSetting("AntiBan", "OvershootEnabled", 1)
g_OvershootEnabled := (g_OvershootEnabled != 0) ? 1 : 0

g_OvershootPercent := LoadSetting("AntiBan", "Overshoot", 5)
if !RegExMatch(g_OvershootPercent, "^\d+(\.\d+)?$")
    g_OvershootPercent := 5
if (g_OvershootPercent < 0)
    g_OvershootPercent := 0
if (g_OvershootPercent > 100)
    g_OvershootPercent := 100
	
; AntiBan - RandSleep (mirrored)
g_RandSleepEnabled := LoadSetting("AntiBan", "RandSleepEnabled", 1)
g_RandSleepEnabled := (g_RandSleepEnabled != 0) ? 1 : 0

g_RandSleepMax := LoadSetting("AntiBan", "RandSleepMax", 60)
if !RegExMatch(g_RandSleepMax, "^\d+$")
    g_RandSleepMax := 60
if (g_RandSleepMax < 0)
    g_RandSleepMax := 0
if (g_RandSleepMax > 5000)
    g_RandSleepMax := 5000  ; safety clamp

g_RandSleepChance := LoadSetting("AntiBan", "RandSleepChance", 25)
if !RegExMatch(g_RandSleepChance, "^\d+(\.\d+)?$")
    g_RandSleepChance := 25
if (g_RandSleepChance < 0)
    g_RandSleepChance := 0
if (g_RandSleepChance > 100)
    g_RandSleepChance := 100
	
; =========================
; Cache settings file modified time
; =========================
g_SettingsLastWrite := ""
if FileExist(settingsFile) {
    FileGetTime, g_SettingsLastWrite, %settingsFile%, M
}

; =========================
; Live settings refresh (every 250ms)
; =========================
SetTimer, RefreshSettings, 250

; =========================
; SHA-256 (AHK v1) - bytes + hex
; Hashes ANSI bytes (AStr) to match v2 generator usage
; =========================
SHA256_BYTES(str, ByRef outBuf) {
    static PROV_RSA_AES := 24
    static CRYPT_VERIFYCONTEXT := 0xF0000000
    static CALG_SHA_256 := 0x0000800C
    static HP_HASHVAL := 0x0002

    hProv := 0, hHash := 0

    if !DllCall("Advapi32\CryptAcquireContextW"
        , "Ptr*", hProv
        , "Ptr", 0
        , "Ptr", 0
        , "UInt", PROV_RSA_AES
        , "UInt", CRYPT_VERIFYCONTEXT)
        throw Exception("CryptAcquireContext failed")

    if !DllCall("Advapi32\CryptCreateHash"
        , "Ptr", hProv
        , "UInt", CALG_SHA_256
        , "Ptr", 0
        , "UInt", 0
        , "Ptr*", hHash) {
        DllCall("Advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)
        throw Exception("CryptCreateHash failed")
    }

    if !DllCall("Advapi32\CryptHashData"
        , "Ptr", hHash
        , "AStr", str
        , "UInt", StrLen(str)
        , "UInt", 0) {
        DllCall("Advapi32\CryptDestroyHash", "Ptr", hHash)
        DllCall("Advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)
        throw Exception("CryptHashData failed")
    }

    VarSetCapacity(outBuf, 32, 0)
    cbHash := 32
    if !DllCall("Advapi32\CryptGetHashParam"
        , "Ptr", hHash
        , "UInt", HP_HASHVAL
        , "Ptr", &outBuf
        , "UIntP", cbHash
        , "UInt", 0) {
        DllCall("Advapi32\CryptDestroyHash", "Ptr", hHash)
        DllCall("Advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)
        throw Exception("CryptGetHashParam failed")
    }

    DllCall("Advapi32\CryptDestroyHash", "Ptr", hHash)
    DllCall("Advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)
    return 32
}

SHA256_HEX(str) {
    SHA256_BYTES(str, hashBuf)
    return BytesToLowerHex(hashBuf, 32)
}

BytesToLowerHex(ByRef buf, len) {
    hex := ""
    Loop, %len%
    {
        b := NumGet(buf, A_Index-1, "UChar")
        hex .= SubStr("0123456789abcdef", (b >> 4) + 1, 1)
        hex .= SubStr("0123456789abcdef", (b & 0xF) + 1, 1)
    }
    return hex
}


; =========================
; Base64 decode (Windows API) AHK v1 -> returns binary in outBin (ByRef)
; Returns decoded byte length
; =========================
Base64_Decode(ByRef b64, ByRef outBin) {
    ; CRYPT_STRING_BASE64_ANY = 0x6
    static CRYPT_STRING_BASE64_ANY := 0x6

    b64 := RegExReplace(b64, "\s+")  ; remove whitespace/newlines
    if (b64 = "")
        throw Exception("Empty Base64 input")

    binLen := 0
    if !DllCall("Crypt32\CryptStringToBinaryW"
        , "WStr", b64
        , "UInt", 0
        , "UInt", CRYPT_STRING_BASE64_ANY
        , "Ptr", 0
        , "UIntP", binLen
        , "Ptr", 0
        , "Ptr", 0)
        throw Exception("CryptStringToBinaryW length failed")

    VarSetCapacity(outBin, binLen, 0)
    if !DllCall("Crypt32\CryptStringToBinaryW"
        , "WStr", b64
        , "UInt", 0
        , "UInt", CRYPT_STRING_BASE64_ANY
        , "Ptr", &outBin
        , "UIntP", binLen
        , "Ptr", 0
        , "Ptr", 0)
        throw Exception("CryptStringToBinaryW data failed")

    return binLen
}

; =========================
; Deobfuscation (Salt + XOR + Base64) -> returns plaintext string (UTF-8)
; Format: Base64( SALT(16) || CIPHERTEXT )
; keystream: SHA256_BYTES( saltHex "|" secret )
; =========================
License_Deobfuscate_FromBase64(b64Text, secret) {
    decodedLen := Base64_Decode(b64Text, blob)
    if (decodedLen < 17)
        throw Exception("License blob too short")

    ; salt = first 16 bytes
    VarSetCapacity(salt, 16, 0)
    DllCall("RtlMoveMemory", "Ptr", &salt, "Ptr", &blob, "UPtr", 16)

    ctLen := decodedLen - 16
    VarSetCapacity(ct, ctLen, 0)
    DllCall("RtlMoveMemory", "Ptr", &ct, "Ptr", &blob + 16, "UPtr", ctLen)

    saltHex := BytesToLowerHex(salt, 16)

    SHA256_BYTES(saltHex . "|" . secret, keyBytes) ; 32 raw bytes

    VarSetCapacity(pt, ctLen, 0)
    Loop, %ctLen%
    {
        b := NumGet(ct, A_Index-1, "UChar")
        kk := NumGet(keyBytes, Mod(A_Index-1, 32), "UChar")
        NumPut(b ^ kk, pt, A_Index-1, "UChar")
    }

    return StrGet(&pt, ctLen, "UTF-8")
}

RefreshSettings:
    global settingsFile, g_SettingsLastWrite
    global g_GameTitle, g_ShowOverlay
    global g_OvershootEnabled, g_OvershootPercent

    ; If file missing, nothing to refresh
    if !FileExist(settingsFile)
        return

    ; Check if settings file changed since last read
    FileGetTime, curWrite, %settingsFile%, M
    if (curWrite = g_SettingsLastWrite)
        return
    g_SettingsLastWrite := curWrite

    ; General
    g_GameTitle := LoadSetting("General", "GameTitle", "C:")
    g_ShowOverlay := LoadSetting("General", "ShowOverlay", 1)
    g_ShowOverlay := (g_ShowOverlay != 0) ? 1 : 0
	
	; --- AntiBan - RandSleep (refresh) ---
	g_RandSleepEnabled := LoadSetting("AntiBan", "RandSleepEnabled", g_RandSleepEnabled)
	g_RandSleepEnabled := (g_RandSleepEnabled != 0) ? 1 : 0

	g_RandSleepMax := LoadSetting("AntiBan", "RandSleepMax", g_RandSleepMax)
	if !RegExMatch(g_RandSleepMax, "^\d+$")
		g_RandSleepMax := 60
	if (g_RandSleepMax < 0)
		g_RandSleepMax := 0
	if (g_RandSleepMax > 5000)
		g_RandSleepMax := 5000

	g_RandSleepChance := LoadSetting("AntiBan", "RandSleepChance", g_RandSleepChance)
	if !RegExMatch(g_RandSleepChance, "^\d+(\.\d+)?$")
		g_RandSleepChance := 25
	if (g_RandSleepChance < 0)
		g_RandSleepChance := 0
	if (g_RandSleepChance > 100)
		g_RandSleepChance := 100

    ; AntiBan - Overshoot (refresh)
    g_OvershootEnabled := LoadSetting("AntiBan", "OvershootEnabled", 1)
    g_OvershootEnabled := (g_OvershootEnabled != 0) ? 1 : 0

    g_OvershootPercent := LoadSetting("AntiBan", "Overshoot", 5)
    if !RegExMatch(g_OvershootPercent, "^\d+(\.\d+)?$")
        g_OvershootPercent := 5
    if (g_OvershootPercent < 0)
        g_OvershootPercent := 0
    if (g_OvershootPercent > 100)
        g_OvershootPercent := 100
return

;--------------------------------------------------------------------------------;
;********************************************************************************;

; Code below controls the humanlike mousemovements, added at end of the script so we can use the
; MoveMouse function

;********************************************************************************;
;--------------------------------------------------------------------------------;
;  v1.6										 ;
;  Original script by: Flight in Pascal					         ;
;  Link: https://github.com/SRL/SRL/blob/master/shared/mouse.simba               ;
;  More Flight's mouse moves: https://paste.villavu.com/show/3279/       	 ;
;  ModIfied script with simpler method MoveMouse() by: dexon in C#           	 ;
;  Conversion from C# into AHK by: HowDoIStayInDreams, with the help of Arekusei ;
;  Refactor & Rewrite by Pipz ;
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
;--------------------------------------------------------------------------------;
;*********************************************************************************

MoveMouse(x, y, speed := "", RD := "") {
    If (speed == "") {
        Random, s, 25, 30
        speed := s / 10.0
    }

    Random, angleDeg, 0, 360
    angleRad := angleDeg * (3.14159 / 180)
    Random, distance, 0, 100
    distance := Sqrt(distance / 100.0) * 15  ; 15px radius (adjust as needed)

    offsetX := Cos(angleRad) * distance
    offsetY := Sin(angleRad) * distance

    x := x + offsetX
    y := y + offsetY

    ;-----------------------------
    ; overshoot / muscle memory
    ;-----------------------------
    static MuscleMemory := {}  ; key = "x|y", value = {val:=reduction, lastTime:=A_TickCount}
    MEMORY_DECAY_INTERVAL := 10000
    MEMORY_DECAY_RATE := 0.01

    MouseGetPos, startX, startY
    distX := x - startX
    distY := y - startY
    distanceTotal := Hypot(distX, distY)

    global g_OvershootEnabled, g_OvershootPercent

if (g_OvershootEnabled)
    baseOvershoot := g_OvershootPercent / 100.0
else
    baseOvershoot := 0

overshootOccurred := false
overshootX := x
overshootY := y

; If disabled (or 0%), skip all memory logic + overshoot calc
if (baseOvershoot <= 0) {
    overshootChance := 0
} else {
    targetKey := Round(x) "|" Round(y)

    reduction := 0
    if (MuscleMemory.HasKey(targetKey)) {
        mem := MuscleMemory[targetKey]
        elapsed := A_TickCount - mem.lastTime
        decaySteps := Floor(elapsed / MEMORY_DECAY_INTERVAL)
        mem.val := Max(mem.val - decaySteps * MEMORY_DECAY_RATE, 0)
        MuscleMemory[targetKey] := mem
        reduction := mem.val
    }

    overshootChance := Max(baseOvershoot - reduction, 0)
}

Random, r, 0, 100
if (r < overshootChance * 100) {
    factor := Min(Max(distanceTotal / 500 * 0.03, 0.02), 0.05)
    Random, overshootFactor, factor * 50, factor * 150
    overshootFactor := overshootFactor / 100
    overshootX := x + distX * overshootFactor
    overshootY := y + distY * overshootFactor
    overshootOccurred := true
}
    ;-----------------------------
    
    If (RD == "RD") {
        goRelative(overshootX, overshootY, speed)
    } Else {
        goStandard(overshootX, overshootY, speed)
    }

    if overshootOccurred {
        PreciseSleep(6)  ; human-like reaction is quick
        If (RD == "RD") {
            goRelative(x - overshootX, y - overshootY, speed * 1.5)
        } Else {
            goStandard(x, y, speed * 1.5)
        }

        ; Muscle memory increment
        Random, randMem, 0, 100
        reductionAmount := 0.01 + (randMem / 100) * 0.01  ; small memory increase

        if (MuscleMemory.HasKey(targetKey)) {
            mem := MuscleMemory[targetKey]
            mem.val := Min(mem.val + reductionAmount, 0.03)
            mem.lastTime := A_TickCount
            MuscleMemory[targetKey] := mem
        } else {
            MuscleMemory[targetKey] := {val:Min(reductionAmount, 0.03), lastTime:A_TickCount}
        }
    }
}

;---------------------- no need to change anything below ------------------------;

WindMouse(xs, ys, xe, ye, gravity, wind, minWait, maxWait, maxStep, targetArea, SleepsArray) {
	windX := 0, windY := 0
	veloX := 0, veloY := 0
	newX := Round(xs)
	newY := Round(ys)
	waitDIff := maxWait - minWait
	sqrt2 := Sqrt(2)
	sqrt3 := Sqrt(3)
	sqrt5 := Sqrt(5)
	dist := Hypot(xe - xs, ye - ys)
	i := 1
	stepVar := maxStep
	Loop{
		wind := Min(wind, dist)
		If (dist >= targetArea) {
			windX := windX / sqrt3 + (Random(round(wind) * 2 + 1) - wind) / sqrt5
			windY := windY / sqrt3 + (Random(round(wind) * 2 + 1) - wind) / sqrt5
			maxStep := RandomWeight(stepVar / 2, (stepVar + (stepVar / 2)) / 2, stepVar)
		} Else {
			windX := windX / sqrt2
			windY := windY / sqrt2
			If(maxStep < 3) {
				maxStep := 1
			} Else {
				maxStep := maxStep / 3
			}
		}
		veloX += windX
		veloY += windY
		veloX := veloX + gravity * ( xe - xs ) / dist
		veloY := veloY + gravity * ( ye - ys ) / dist
		If (Hypot(veloX, veloY) > maxStep) {
			RandomDist := maxStep / 2 + (Round(Random(maxStep)) / 2)
			veloMag := Hypot(veloX, veloY)
			veloX := ( veloX / veloMag ) * RandomDist
			veloY := ( veloY / veloMag ) * RandomDist
		}
		oldX := Round(xs)
		oldY := Round(ys)
		xs := xs + veloX
		ys := ys + veloY
		dist := Hypot(xe - xs, ye - ys)
		If (dist <= 1) {
			Break
		}
		newX := Round(xs)
		newY := Round(ys)
		If (oldX != newX) or (oldY != newY) {
			MouseMove, newX, newY
		}
		step := Hypot(xs - oldX, ys - oldY)
		c := SleepsArray.Count()
		If (i > c) {
			lastSleeps := Round(SleepsArray[c])
			Random, w, lastSleeps, lastSleeps + 1
			wait := Max(Round(abs(w)), 1)
			PreciseSleep(wait)
		} Else {
			waitSleep := Round(SleepsArray[i])
			Random, w, waitSleep, waitSleep + 1
			wait := Max(Round(abs(w)), 1)
			PreciseSleep(wait)
			i++
		}
	}
	endX := Round(xe)
	endY := Round(ye)
	If (endX != newX) or (endY != newY) {
		MouseMove, endX, endY
    }
	i := 1
}


WindMouse2(xs, ys, xe, ye, gravity, wind, minWait, maxWait, maxStep, targetArea) {
	windX := 0, windY := 0
	veloX := 0, veloY := 0
	newX := Round(xs)
	newY := Round(ys)
	waitDIff := maxWait - minWait
	sqrt2 := Sqrt(2)
	sqrt3 := Sqrt(3)
	sqrt5 := Sqrt(5)
	dist := Hypot(xe - xs, ye - ys)
	newArr := []
	stepVar := maxStep
	Loop {
		wind := Min(wind, dist)
		If (dist >= targetArea) {
			windX := windX / sqrt3 + (Random(round(wind) * 2 + 1) - wind) / sqrt5
			windY := windY / sqrt3 + (Random(round(wind) * 2 + 1) - wind) / sqrt5
			maxStep := RandomWeight(stepVar / 2, (stepVar + (stepVar / 2)) / 2, stepVar)
        } Else {
            windX := windX / sqrt2
            windY := windY / sqrt2
            If (maxStep < 3) {
                maxStep := 1
            } Else {
                maxStep := maxStep / 3
            }
        }
        veloX += windX
        veloY += windY
        veloX := veloX + gravity * ( xe - xs ) / dist
        veloY := veloY + gravity * ( ye - ys ) / dist
        If (Hypot(veloX, veloY) > maxStep) {
            RandomDist := maxStep / 2 + (Round(Random(maxStep)) / 2)
            veloMag := Hypot(veloX, veloY)
            veloX := ( veloX / veloMag ) * RandomDist
            veloY := ( veloY / veloMag ) * RandomDist
        }
        oldX := Round(xs)
        oldY := Round(ys)
        xs := xs + veloX
        ys := ys + veloY
        dist := Hypot(xe - xs, ye - ys)
		If (dist <= 1) {
			Break
		}
        newX := Round(xs)
        newY := Round(ys)
        If (oldX != newX) or (oldY != newY) {
            p := 0
        }
        step := Hypot(xs - oldX, ys - oldY)
		mean := Round(waitDIff * (step / maxStep) + minWait) / 7
		wait := Muller((mean) / 2, (mean) /2.718281)
		newArr.Push(wait)
    }
	endX := Round(xe)
	endY := Round(ye)
    If (endX != newX) or (endY != newY) {
        p := 0
    }
	Return newArr
}

Hypot(dx, dy) {
    Return Sqrt(dx * dx + dy * dy)
}

Random(n) {
	Random, out, 0, n
	Return % out
}

PreciseSleep(ms) {
    SetBatchLines, -1
    DllCall("QueryPerformanceFrequency", "Int64*", freq)
    DllCall("QueryPerformanceCounter", "Int64*", CounterBefore)
    While (((counterAfter - CounterBefore) / freq * 1000) < ms) {
        DllCall("QueryPerformanceCounter", "Int64*", CounterAfter)
	}
    Return ((counterAfter - CounterBefore) / freq * 1000)
}

Muller(m,s) {
   Static i, Y
   If (i := !i) {
      Random U, 0, 1.0
      Random VV, 0, 6.2831853071795862
      U := sqrt(-2 * ln(U)) * s
      Y := m + U * sin(VV)
      Return m + U * cos(VV)
   }
   Return Y
}

SortArray(Array, Order = "A") {
    MaxIndex := ObjMaxIndex(Array)
    If (Order = "R") {
        count := 0
        Loop, % MaxIndex
            ObjInsert(Array, ObjRemove(Array, MaxIndex - count++))
        Return
    }
    Partitions := "|" ObjMinIndex(Array) "," MaxIndex
    Loop{
        comma := InStr(this_partition := SubStr(Partitions, InStr(Partitions, "|", False, 0) + 1), ",")
        spos := pivot := SubStr(this_partition, 1, comma - 1) , epos := SubStr(this_partition, comma + 1)
        If (Order = "A") {
            Loop, % epos - spos {
                If (Array[pivot] > Array[A_Index+spos])
                    ObjInsert(Array, pivot++, ObjRemove(Array, A_Index+spos))
            }
        } Else {
            Loop, % epos - spos {
                If (Array[pivot] < Array[A_Index+spos])
                    ObjInsert(Array, pivot++, ObjRemove(Array, A_Index+spos))
            }
        }
        Partitions := SubStr(Partitions, 1, InStr(Partitions, "|", False, 0) - 1)
        If (pivot - spos) > 1
            Partitions .= "|" spos "," pivot - 1
        If (epos - pivot) > 1
            Partitions .= "|" pivot + 1 "," epos
    } Until !Partitions
}

RandomWeight(min, target, max) {
	Random, Rmin, min, target
	Random, Rmax, target, max
	Random, weighted, Rmin, Rmax
	Return, weighted
}

goStandard(x, y, speed) {
	MouseGetPos, xpos, ypos
	distance := (Sqrt(Hypot(x - xpos, y - ypos))) * speed
	dynamicSpeed := (1 / distance) * 60
	Random, finalSpeed, dynamicSpeed, dynamicSpeed + 0.8
	stepArea := Max(( finalSpeed / 2 + distance ) / 10, 0.1)
	newArr := []
	newArr := WindMouse2(xpos, ypos, x, y, 10, 3, finalSpeed * 10, finalSpeed * 12, stepArea * 11, stepArea * 7)
	SortArray(newArr, "D")
	c := newArr.Count()
	g := c / 2
	Loop, %g% {
		newArr.RemoveAt(c)
		c--
	}
	newClone := []
	newClone := newArr.Clone()
	SortArray(newClone, "A")
	newArr.Push(newClone*)
	WindMouse(xpos, ypos, x, y, 10, 3, finalSpeed * 10, finalSpeed * 12, stepArea * 11, stepArea * 7, newArr)
	newArr := []
}

goRelative(x, y, speed) {
	MouseGetPos, xpos, ypos
	distance := (Sqrt(Hypot((xpos + abs(x)) - xpos, (ypos + abs(y)) - ypos))) * speed
	dynamicSpeed := (1 / distance) * 60
	Random, finalSpeed, dynamicSpeed, dynamicSpeed + 0.8
	stepArea := Max(( finalSpeed / 2 + distance ) / 10, 0.1)
	newArr := []
	newArr := WindMouse2(xpos, ypos, xpos + x, ypos + y, 10, 3, finalSpeed * 10, finalSpeed * 12, stepArea * 11, stepArea * 7)
	SortArray(newArr, "D")
	c := newArr.Count()
	g := c / 2
	Loop, %g% {
		newArr.RemoveAt(c)
		c--
	}
	newClone := []
	newClone := newArr.Clone()
	SortArray(newClone, "A")
	WindMouse(xpos, ypos, xpos + x, ypos + y, 10, 3, finalSpeed * 10, finalSpeed * 12, stepArea * 11, stepArea * 7, newArr)
	newArr := []
}