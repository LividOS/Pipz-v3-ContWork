﻿#Requires AutoHotkey >=2.0 <3.0
#Warn All

; =========================================================
; Pipz MAINTEMPLATE - Controller (AHK v2)
; Version: 1.0.17
; Last change: GameTitle now uses cue placeholder instead of hardcoded default
; =========================================================

; =========================
; License Check (Obfuscated license.key)
; =========================
secret := "PIPSECMAX_LIREGKEY_11711503721976861054928319"
keyFile := A_ScriptDir "\license.key"

if !FileExist(keyFile) {
    MsgBox("Failed to locate License.`n`nScript Automatically Terminated.")
    ExitApp
}

cipherB64 := RegExReplace(FileRead(keyFile), "\s+")

try payload := License_Deobfuscate_FromBase64(cipherB64, secret)
catch as e {
    MsgBox(
        "Failed to decrypt License.`n`n"
        "Error: " e.Message "`n"
        "What: " e.What "`n"
        "Line: " e.Line
    )
    ExitApp
}

data := Map()
for line in StrSplit(payload, "`n") {
    if RegExMatch(line, "(.+?)=(.+)", &m)
        data[Trim(m[1])] := Trim(m[2])
}

if !data.Has("EXPIRES") || !data.Has("ID") || !data.Has("HASH") {
    MsgBox("Failed to validate License file.`n`nScript Automatically Terminated.")
    ExitApp
}

expires := data["EXPIRES"]
id      := data["ID"]
hash    := data["HASH"]

; Hardening: ID must be exactly 32 hex chars
if !RegExMatch(id, "i)^[0-9a-f]{32}$") {
    MsgBox("Invalid License ID format.`n`nScript Automatically Terminated.")
    ExitApp
}

expected := SHA256(expires "|" id "|" secret)
if (expected != hash) {
    MsgBox("License file has been modified or is invalid.`n`nScript Automatically Terminated.")
    ExitApp
}

if (SubStr(A_NowUTC, 1, 8) > expires) {
    MsgBox("License has expired.`n`nScript Automatically Terminated.")
    ExitApp
}

; ✅ License valid — script continues

; =========================
; License display strings (masked)
; =========================
maskedId := (StrLen(id) >= 10) ? (SubStr(id, 1, 6) "..." SubStr(id, -4)) : id
expY := SubStr(expires, 1, 4)
expM := SubStr(expires, 5, 2)
expD := SubStr(expires, 7, 2)
expiresPretty := expY "-" expM "-" expD

; =========================
; Feature metadata (defaults + tooltips + settings keys)
; =========================
FEATURE_META := Map(
    "Overshoot", Map(
        "section", "AntiBan",
        "enabledKey", "OvershootEnabled",
        "valueKey", "Overshoot",
        "enabledDefault", 1,
        "valueDefault", 5,
        "featureTip", "Chance for mouse to slightly miss target destination and correct.",
        "tuningTip", "Base overshoot chance (%). Higher = more likely to overshoot."
    ),
    "RandSleep", Map(
        "section", "AntiBan",
        "enabledKey", "RandSleepEnabled",
        "durationKey", "RandSleepMax",
        "chanceKey", "RandSleepChance",
        "enabledDefault", 1,
        "durationDefault", 60,
        "chanceDefault", 25,
        "featureTip", "Occasionally adds a short randomized delay while the script is active.",
        "durationTip", "Max randomized sleep in ms. Actual sleep is randomized between 10ms and this value.",
        "chanceTip", "Chance (%) that a randomized sleep occurs when ManSleep() is called."
    )
)

; =========================
; Settings file
; =========================
settingsFile := A_ScriptDir "\settings"
InitSettings()

; =========================
; Global State
; =========================
isRunning := false
runState := "stopped"   ; "running" | "paused" | "stopped"
startTick := 0
elapsedMs := 0
gameTitle := Trim(LoadSetting("General", "GameTitle", ""))      ; Window Title to snap overlay to

; Migrate old default "C:" to unset
if (gameTitle = "C:")
    gameTitle := ""
overlayOffsetY := 20
overlayPaddingX := 12
overlayPaddingY := 12
SetTitleMatchMode(2)
A_IconTip := "Mastering Mixology"
TraySetIcon "ScriptLogo.png"
showOverlay := (LoadSetting("General", "ShowOverlay", 1) != 0)
isDragging := false
lastGX := 0
lastGY := 0
dragTick := 0

; =========================
; Hidden script PID
; =========================
v1PID := 0

; =========================
; Inline status override flag + Call
; =========================
inlineOverride := false

; =========================
; Overlay spring state
; =========================
overlayCurX := 0.0
overlayCurY := 0.0
overlayVelX := 0.0
overlayVelY := 0.0

springStrength := 0.45
springDamping  := 0.75
springSnapDist := 250

overlayPrevX := 0
overlayPrevY := 0
overlayPrevTimeStr := ""
overlayPrevStatus := ""
overlayPrevColor := ""
overlayPrevStatusColor := ""

; =========================
; CONTROL GUI
; =========================
ctrlGui := Gui("+AlwaysOnTop", "Pipz NAMEPLACEHOLDER")
ctrlGui.SetFont("s10", "Segoe UI")

GUI_W := 420
GUI_H := 340

tabs := ctrlGui.AddTab3("x10 y10 w" GUI_W " h" GUI_H, ["General", "Settings", "Anti-Ban", "About"])

tabs.UseTab(1)

ctrlGui.SetFont("s12 Bold")
ctrlGui.AddText("x20 y45 w" (GUI_W-40) " Center", "Overlay Settings")

ctrlGui.SetFont("s10")
chkShowOverlay := ctrlGui.AddCheckBox("x30 y80 w250 " (showOverlay ? "Checked" : ""), "Show Overlay")
chkShowOverlay.OnEvent("Click", ToggleOverlay)

ctrlGui.SetFont("s12 Bold")
ctrlGui.AddText("x20 y120 w" (GUI_W-40) " Center", "Game Window Title")

ctrlGui.SetFont("s10")
editGameTitle := ctrlGui.AddEdit("x60 y150 w" (GUI_W-100), gameTitle)
editGameTitle.OnEvent("Change", UpdateGameTitle)

; Grey placeholder when unset (no actual text placed in the field)
if (Trim(editGameTitle.Value) = "")
    SetCueBanner(editGameTitle.Hwnd, "RuneLite - CHARACTERNAME", true)

; Bottom buttons
BTN_Y := 255
BTN_W := 90
BTN_GAP := 10
CENTER_X := (GUI_W // 2) - (BTN_W * 3 + BTN_GAP * 2) // 2

btnStart := ctrlGui.AddButton("x" CENTER_X " y" BTN_Y " w" BTN_W, "Start")
btnStop  := ctrlGui.AddButton("x" (CENTER_X + BTN_W + BTN_GAP) " y" BTN_Y " w" BTN_W, "Stop")
btnReset := ctrlGui.AddButton("x" (CENTER_X + (BTN_W + BTN_GAP) * 2) " y" BTN_Y " w" BTN_W, "Reset")

btnStart.OnEvent("Click", StartScript)
btnStop.OnEvent("Click", StopScript)
btnReset.OnEvent("Click", ResetScript)
UpdateRunButtons()

; Restore Defaults button (centered under Start/Stop/Reset)
RESTORE_Y := BTN_Y + 40
RESTORE_W := 170
restoreX := (GUI_W // 2) - (RESTORE_W // 2)

btnRestore := ctrlGui.AddButton("x" restoreX " y" RESTORE_Y " w" RESTORE_W, "Restore Defaults")
btnRestore.OnEvent("Click", RestoreDefaults)

; Small status text under Restore Defaults (always visible on all tabs)
statusY := RESTORE_Y + 32
tabs.UseTab()  ; <-- IMPORTANT: no tab assignment
lblRestoreStatus := ctrlGui.AddText("x20 y" statusY " w" (GUI_W - 40) " Center cGray", "")
UpdateInlineStatus()

tabs.UseTab(1)  ; restore normal tab assignment

SetTimer(WatchWorkerHealth, 500)

; =========================
; ANTI-BAN TAB (Features / Tuning panels)
; =========================
tabs.UseTab(3)  ; Anti-Ban tab

ctrlGui.SetFont("s12 Bold")
ctrlGui.AddText("x20 y45 w" (GUI_W - 40) " Center", "Anti-Ban Settings")

; ---- Sub-tab buttons (fake tabs) ----
subBtnY := 75
btnSubW := 120
btnGap := 10

pairW := (btnSubW * 2) + btnGap
subBtnX := 20 + ((GUI_W - 40 - pairW) // 2)  ; center within Anti-Ban content area (x20..x20+GUI_W-40)

btnAntiFeatures := ctrlGui.AddButton("x" subBtnX " y" subBtnY " w" btnSubW, "Features")
btnAntiTuning   := ctrlGui.AddButton("x" (subBtnX + btnSubW + btnGap) " y" subBtnY " w" btnSubW, "Tuning")

btnAntiFeatures.OnEvent("Click", (*) => SetAntiBanSubTab("features"))
btnAntiTuning.OnEvent("Click",   (*) => SetAntiBanSubTab("tuning"))

; ---- Panels ----
panelX := 20
panelY := 125
panelW := GUI_W - 40
panelH := 170

gbFeatures := ctrlGui.AddGroupBox("x" panelX " y" panelY " w" panelW " h" panelH, "Features")
gbTuning   := ctrlGui.AddGroupBox("x" panelX " y" panelY " w" panelW " h" panelH, "Tuning")

; -------------------------
; Load settings
; -------------------------
overshootEnabled := (LoadSetting("AntiBan", "OvershootEnabled", 1) != 0)
overshootValue   := LoadSetting("AntiBan", "Overshoot", 5) + 0

randSleepEnabled := (LoadSetting("AntiBan", "RandSleepEnabled", 1) != 0)
randSleepMax     := LoadSetting("AntiBan", "RandSleepMax", 60) + 0
randSleepChance  := LoadSetting("AntiBan", "RandSleepChance", 25) + 0


; =========================
; FEATURES PANEL (checkboxes)
; =========================
ctrlGui.SetFont("s10")

fx := panelX + 20
fy := panelY + 35

chkOvershoot := ctrlGui.AddCheckBox("x" fx " y" fy " w260 " (overshootEnabled ? "Checked" : ""), "Overshoot")
AddCtrlToolTip(ctrlGui, chkOvershoot, FEATURE_META["Overshoot"]["featureTip"])
chkOvershoot.OnEvent("Click", OnOvershootToggle)

fy += 30
chkRandSleep := ctrlGui.AddCheckBox("x" fx " y" fy " w260 " (randSleepEnabled ? "Checked" : ""), "Randomized Sleep")
AddCtrlToolTip(ctrlGui, chkRandSleep, FEATURE_META["RandSleep"]["featureTip"])
chkRandSleep.OnEvent("Click", OnRandSleepToggle)


; =========================
; TUNING PANEL (spinboxes)
; =========================
tx := panelX + 20
ty := panelY + 35

labelW := panelW - 140
editX  := panelX + panelW - 95
upX    := panelX + panelW - 35

; Overshoot tuning
lblOvershootTune := ctrlGui.AddText("x" tx " y" ty+2 " w" labelW, "Overshoot (%)")
editOvershoot := ctrlGui.AddEdit("x" editX " y" (ty-2) " w55", overshootValue)
upDown := ctrlGui.AddUpDown("x" upX " y" (ty-2) " w20 Range0-100")
upDown.Value := overshootValue
upDown.OnEvent("Change", (*) => (editOvershoot.Text := upDown.Value, UpdateOvershoot()))
AddCtrlToolTip(ctrlGui, lblOvershootTune, FEATURE_META["Overshoot"]["tuningTip"])
AddCtrlToolTip(ctrlGui, editOvershoot,    FEATURE_META["Overshoot"]["tuningTip"])
AddCtrlToolTip(ctrlGui, upDown,           FEATURE_META["Overshoot"]["tuningTip"])
editOvershoot.OnEvent("Change", UpdateOvershoot)

ty += 35

; Randomized Sleep Duration tuning
lblRandSleepDur := ctrlGui.AddText("x" tx " y" ty+2 " w" labelW, "Randomized Sleep Duration (ms)")
editRandSleep := ctrlGui.AddEdit("x" editX " y" (ty-2) " w55", randSleepMax)
upDownRandSleep := ctrlGui.AddUpDown("x" upX " y" (ty-2) " w20 Range10-5000")
upDownRandSleep.Value := randSleepMax
upDownRandSleep.OnEvent("Change", (*) => (editRandSleep.Text := upDownRandSleep.Value, UpdateRandSleep()))
AddCtrlToolTip(ctrlGui, lblRandSleepDur,  FEATURE_META["RandSleep"]["durationTip"])
AddCtrlToolTip(ctrlGui, editRandSleep,    FEATURE_META["RandSleep"]["durationTip"])
AddCtrlToolTip(ctrlGui, upDownRandSleep,  FEATURE_META["RandSleep"]["durationTip"])
editRandSleep.OnEvent("Change", UpdateRandSleep)

ty += 35

; Randomized Sleep Chance tuning
lblRandSleepChance := ctrlGui.AddText("x" tx " y" ty+2 " w" labelW, "Randomized Sleep Chance (%)")
editRandSleepChance := ctrlGui.AddEdit("x" editX " y" (ty-2) " w55", randSleepChance)
upDownRandSleepChance := ctrlGui.AddUpDown("x" upX " y" (ty-2) " w20 Range0-100")
upDownRandSleepChance.Value := randSleepChance
upDownRandSleepChance.OnEvent("Change", (*) => (editRandSleepChance.Text := upDownRandSleepChance.Value, UpdateRandSleepChance()))
AddCtrlToolTip(ctrlGui, lblRandSleepChance, FEATURE_META["RandSleep"]["chanceTip"])
AddCtrlToolTip(ctrlGui, editRandSleepChance, FEATURE_META["RandSleep"]["chanceTip"])
AddCtrlToolTip(ctrlGui, upDownRandSleepChance, FEATURE_META["RandSleep"]["chanceTip"])
editRandSleepChance.OnEvent("Change", UpdateRandSleepChance)

; Apply enabled/disabled states once
SetOvershootControlsEnabled(overshootEnabled)
SetRandSleepControlsEnabled(randSleepEnabled)

; Default sub-tab on open
SetAntiBanSubTab("features")

tabs.UseTab()  ; reset outer tab assignment

; =========================
; SCRIPT SETTINGS TAB HEADER
; =========================

tabs.UseTab(2)  ; switch to Settings tab

ctrlGui.SetFont("s12 Bold")
ctrlGui.AddText("x20 y45 w" (GUI_W - 40) " Center", "Script Settings")

tabs.UseTab()  ; reset tab assignment

; =========================
; ABOUT TAB (License Info)
; =========================
tabs.UseTab(4)  ; switch to About tab

ctrlGui.SetFont("s14 Bold")
ctrlGui.AddText("x20 y45 w" (GUI_W - 40) " Center", "Author")
ctrlGui.SetFont("s12")
ctrlGui.AddText("x20 y65 w" (GUI_W - 40) " Center", "Pipz")

ctrlGui.SetFont("s14 Bold")
ctrlGui.AddText("x20 y95 w" (GUI_W - 40) " Center", "Contributions")
ctrlGui.SetFont("s12")
ctrlGui.AddText("x20 y115 w" (GUI_W - 40) " Center", "N/A")

; Centered license info
ctrlGui.SetFont("s14 Bold")
ctrlGui.AddText("x20 y225 w" (GUI_W - 40) " Center", "License Information")

ctrlGui.SetFont("s10")
ctrlGui.AddText("x20 y265 w" (GUI_W - 40) " Center", "License ID: " maskedId)
ctrlGui.AddText("x20 y290 w" (GUI_W - 40) " Center", "Expires: " expiresPretty)

tabs.UseTab()  ; reset tab assignment
ctrlGui.Show("w" (GUI_W+20) " h" (GUI_H+20))

; =========================
; OVERLAY GUI (single, flicker-free)
; =========================
overlayWidth := 360
overlayHeight := 108

overlayGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
overlayGui.BackColor := "Black"
overlayGui.MarginX := 0
overlayGui.MarginY := 0

y := 0

; Title
overlayGui.SetFont("s18 Bold cYellow", "Segoe UI")
overlayTitle := overlayGui.AddText("x0 y" y " w" overlayWidth " h42 Center +0x200", "Pipz NAMEPLACEHOLDER")
y += 40

; Status
overlayGui.SetFont("s12 Bold cWhite", "Segoe UI")
overlayStatus := overlayGui.AddText("x0 y" y " w" overlayWidth " h28 Center +0x200", "Status - Inactive")
y += 28

; Timer
overlayGui.SetFont("s12 cRed", "Segoe UI")
overlayTime := overlayGui.AddText("x0 y" y " w" overlayWidth " h28 Center +0x200", "Time Spent ACTIONPLACEHOLDER - 00:00:00")

; Track previous position & text
overlayPrevX := 0
overlayPrevY := 0
overlayPrevTimeStr := ""
overlayPrevStatus := ""
overlayPrevColor := ""
overlayPrevStatusColor := ""

overlayGui.Show("Hide w" overlayWidth " h" overlayHeight " x" (A_ScreenWidth//2 - overlayWidth//2) " y30")
WinSetTransparent(210, overlayGui)

SetTimer(UpdateOverlayAndPosition, 10)

; =========================
; FUNCTIONS
; =========================
StartScript(*) {
    global isRunning, startTick, ctrlGui, v1PID, runState

    v1ScriptName := "MainTemplate[Worker[SCRIPT]v1].ahk"
    v1ScriptPath := A_ScriptDir "\" v1ScriptName

    if !FileExist(v1ScriptPath) {
        MsgBox(
            "The required v1 script was not found:`n`n"
            v1ScriptName "`n`n"
            "It must be in the same folder as this tool."
        )
        return
    }

    if isRunning
        return

    isRunning := true
    startTick := A_TickCount

    ctrlGui.Minimize()
    UpdateOverlayAndPosition()

    ; Launch or resume
    if (!v1PID || !ProcessExist(v1PID)) {
        if !LaunchV1ScriptWithFallback(v1ScriptPath, &v1PID) {
            isRunning := false
            runState := "stopped"
            UpdateRunButtons()
            UpdateInlineStatus()
            return
        }
    } else {
        ProcessResume(v1PID)
    }

    ; Confirm worker exists; if yes, mark running
    if (v1PID && ProcessExist(v1PID)) {
        runState := "running"
    } else {
        isRunning := false
        runState := "stopped"
    }

    UpdateRunButtons()
    UpdateInlineStatus()
}

StopScript(*) {
    global isRunning, elapsedMs, startTick, ctrlGui, v1PID, runState

    if !isRunning
        return

    isRunning := false
    elapsedMs += A_TickCount - startTick

    ctrlGui.Restore()
    UpdateOverlayAndPosition()

    if (v1PID && ProcessExist(v1PID))
        ProcessSuspend(v1PID)

    runState := (v1PID && ProcessExist(v1PID)) ? "paused" : "stopped"
    UpdateRunButtons()
    UpdateInlineStatus()
}

ResetScript(*) {
    global isRunning, elapsedMs, startTick, ctrlGui, v1PID, runState
    isRunning := false
	runState := "stopped"
	UpdateRunButtons()
    elapsedMs := 0
    startTick := 0

    ctrlGui.Restore()
    UpdateOverlayAndPosition()

    if ProcessExist(v1PID) {
        ProcessClose(v1PID)
        v1PID := 0
    }
	UpdateInlineStatus()
}

ProcessSuspend(PID) {
    if !ProcessExist(PID)
        return false

    hProc := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", 0, "UInt", PID, "Ptr")
    if !hProc
        return false

    DllCall("ntdll\NtSuspendProcess", "Ptr", hProc)
    DllCall("CloseHandle", "Ptr", hProc)
    return true
}

ProcessResume(PID) {
    if !ProcessExist(PID)
        return false

    hProc := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", 0, "UInt", PID, "Ptr")
    if !hProc
        return false

    DllCall("ntdll\NtResumeProcess", "Ptr", hProc)
    DllCall("CloseHandle", "Ptr", hProc)
    return true
}

UpdateOverlayAndPosition() {
    global isRunning, runState, startTick, elapsedMs
    global overlayGui, overlayStatus, overlayTime
    global gameTitle, overlayPaddingX, overlayPaddingY, overlayWidth, overlayHeight
    global showOverlay
    global overlayCurX, overlayCurY
    global overlayVelX, overlayVelY
    global springStrength, springDamping, springSnapDist
    global lastGX, lastGY, isDragging, dragTick
    global overlayPrevX, overlayPrevY, overlayPrevTimeStr, overlayPrevStatus, overlayPrevColor, overlayPrevStatusColor

    if !showOverlay {
        overlayGui.Hide()
        return
    }

    hwnd := WinExist(gameTitle)
    if !hwnd {
        overlayGui.Hide()
        return
    }

    WinGetPos(&gx, &gy, &gw, &gh, hwnd)

    if (gx != lastGX || gy != lastGY) {
        isDragging := true
        dragTick := A_TickCount
    } else if (A_TickCount - dragTick > 60) {
        isDragging := false
    }
    lastGX := gx
    lastGY := gy

    rc := Buffer(16, 0)
    DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
    clientW := NumGet(rc, 8, "Int")
    clientH := NumGet(rc, 12, "Int")

    pt := Buffer(8, 0)
    DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", pt)
    clientX := NumGet(pt, 0, "Int")
    clientY := NumGet(pt, 4, "Int")

    ox := clientX + overlayPaddingX
    oy := clientY + clientH - overlayHeight - overlayPaddingY

    if (isDragging) {
        overlayCurX := ox
        overlayCurY := oy
        overlayVelX := 0
        overlayVelY := 0
    } else {
        dx := ox - overlayCurX
        dy := oy - overlayCurY
        dist := Sqrt(dx*dx + dy*dy)

        if (dist > springSnapDist) {
            overlayCurX := ox
            overlayCurY := oy
            overlayVelX := 0
            overlayVelY := 0
        } else {
            overlayVelX += dx * springStrength
            overlayVelY += dy * springStrength
            overlayVelX *= springDamping
            overlayVelY *= springDamping
            overlayCurX += overlayVelX
            overlayCurY += overlayVelY
        }
    }

    minX := clientX + overlayPaddingX
    maxX := clientX + clientW - overlayWidth - overlayPaddingX
    minY := clientY + overlayPaddingY
    maxY := clientY + clientH - overlayHeight - overlayPaddingY

    overlayCurX := Clamp(overlayCurX, minX, maxX)
    overlayCurY := Clamp(overlayCurY, minY, maxY)

    newX := Round(overlayCurX)
    newY := Round(overlayCurY)
    if (newX != overlayPrevX || newY != overlayPrevY) {
        overlayGui.Show("NoActivate x" newX " y" newY)
        overlayPrevX := newX
        overlayPrevY := newY
    }

    total := elapsedMs
    if isRunning
        total += A_TickCount - startTick

    seconds := Floor(total / 1000)
    hrs := Floor(seconds / 3600)
    mins := Floor(Mod(seconds, 3600) / 60)
    secs := Mod(seconds, 60)
    timeStr := Format("{:02}:{:02}:{:02}", hrs, mins, secs)
	
	; Overlay status + colors reflect runState
	if (runState = "running") {
		statusStr := "Status - Active"
		timeColorStr := "cLime"
		statusColorStr := "cWhite"
	} else if (runState = "paused") {
		statusStr := "Status - Paused"
		timeColorStr := "cYellow"
		statusColorStr := "cYellow"
	} else {
		statusStr := "Status - Inactive"
		timeColorStr := "cRed"
		statusColorStr := "cWhite"
}

    if (overlayPrevTimeStr != timeStr) {
        overlayTime.Text := "Time Spent ACTIONPLACEHOLDER - " timeStr
        overlayPrevTimeStr := timeStr
    }

    if (overlayPrevStatus != statusStr) {
        overlayStatus.Text := statusStr
        overlayPrevStatus := statusStr
    }

	if (overlayPrevColor != timeColorStr) {
		overlayTime.SetFont("s12 " timeColorStr, "Segoe UI")
		overlayPrevColor := timeColorStr
	}

	if (overlayPrevStatusColor != statusColorStr) {
		overlayStatus.SetFont("s12 Bold " statusColorStr, "Segoe UI")
		overlayPrevStatusColor := statusColorStr
	}

}

ToggleOverlay(*) {
    global showOverlay, chkShowOverlay, overlayGui
    showOverlay := chkShowOverlay.Value

    ; ✅ save
    SaveSetting("General", "ShowOverlay", showOverlay ? 1 : 0)

    if showOverlay {
        overlayGui.Show("NoActivate")
        UpdateOverlayAndPosition()
    } else {
        overlayGui.Hide()
    }
}

UpdateGameTitle(*) {
    global editGameTitle, gameTitle
    newTitle := Trim(editGameTitle.Value)
    if newTitle != "" {
        gameTitle := newTitle

        ; ✅ save
        SaveSetting("General", "GameTitle", gameTitle)
		
		SetCueBanner(editGameTitle.Hwnd, "", true)

        UpdateOverlayAndPosition()
    }
}

Clamp(val, min, max) {
    return val < min ? min : (val > max ? max : val)
}

SetCueBanner(hwnd, text, showWhenFocused := true) {
    ; EM_SETCUEBANNER = 0x1501
    ; wParam: showWhenFocused (1/0)
    ; lParam: pointer to unicode string
    DllCall("SendMessageW"
        , "ptr", hwnd
        , "uint", 0x1501
        , "ptr", showWhenFocused ? 1 : 0
        , "ptr", StrPtr(text))
}

LoadSetting(section, key, default := "") {
    global settingsFile
    try return IniRead(settingsFile, section, key, default)
    catch
        return default
}

SaveSetting(section, key, value) {
    global settingsFile
    try IniWrite(value, settingsFile, section, key)
    catch
        ; optional: MsgBox("Failed to write settings.")
        return
}

OnOvershootToggle(*) {
    global chkOvershoot, overshootEnabled
    overshootEnabled := chkOvershoot.Value

    SaveSetting("AntiBan", "OvershootEnabled", overshootEnabled ? 1 : 0)
    SetOvershootControlsEnabled(overshootEnabled)
}

SetOvershootControlsEnabled(enabled) {
    global editOvershoot, upDown
    if IsSet(editOvershoot)
        editOvershoot.Enabled := enabled
    if IsSet(upDown)
        upDown.Enabled := enabled
}

UpdateOvershoot(*) {
    global editOvershoot, upDown, overshootValue

    val := editOvershoot.Text
    if !RegExMatch(val, "^\d+(\.\d+)?$")
        val := 0

    val := Clamp(val, 0, 100)

    overshootValue := val
    editOvershoot.Text := val
    upDown.Value := val

    SaveSetting("AntiBan", "Overshoot", val)
}

OnRandSleepToggle(*) {
    global chkRandSleep, randSleepEnabled
    randSleepEnabled := (chkRandSleep.Value != 0)

    SaveSetting("AntiBan", "RandSleepEnabled", randSleepEnabled ? 1 : 0)
    SetRandSleepControlsEnabled(randSleepEnabled)
}

SetRandSleepControlsEnabled(enabled) {
    global editRandSleep, upDownRandSleep
    global editRandSleepChance, upDownRandSleepChance

    if IsSet(editRandSleep)
        editRandSleep.Enabled := enabled
    if IsSet(upDownRandSleep)
        upDownRandSleep.Enabled := enabled

    if IsSet(editRandSleepChance)
        editRandSleepChance.Enabled := enabled
    if IsSet(upDownRandSleepChance)
        upDownRandSleepChance.Enabled := enabled
}

UpdateRandSleep(*) {
    global editRandSleep, upDownRandSleep, randSleepMax

    val := editRandSleep.Text
    if !RegExMatch(val, "^\d+$")  ; integer-only
        val := 10

    val := Clamp(val, 10, 5000)

    randSleepMax := val
    editRandSleep.Text := val
    upDownRandSleep.Value := val

    SaveSetting("AntiBan", "RandSleepMax", val)
}

InitSettings() {
    SaveSetting("General", "ShowOverlay", LoadSetting("General","ShowOverlay",1))
	; Do NOT force-write GameTitle default.
	; Keep it unset so the cue banner can show until user sets it.
	gt := Trim(LoadSetting("General", "GameTitle", ""))

	; migrate old default "C:" to unset
	if (gt = "C:") {
		try IniDelete(settingsFile, "General", "GameTitle")
	} else if (gt != "") {
		SaveSetting("General", "GameTitle", gt)
	}
	for _, meta in FEATURE_META {
		sec := meta["section"]

		if meta.Has("enabledKey")
			SaveSetting(sec, meta["enabledKey"], LoadSetting(sec, meta["enabledKey"], meta["enabledDefault"]))

		if meta.Has("valueKey")
			SaveSetting(sec, meta["valueKey"], LoadSetting(sec, meta["valueKey"], meta["valueDefault"]))

		if meta.Has("durationKey")
			SaveSetting(sec, meta["durationKey"], LoadSetting(sec, meta["durationKey"], meta["durationDefault"]))

		if meta.Has("chanceKey")
			SaveSetting(sec, meta["chanceKey"], LoadSetting(sec, meta["chanceKey"], meta["chanceDefault"]))
	}
}

LaunchV1ScriptWithFallback(v1ScriptPath, &pid) {
    ; 1) Try Windows association first
    try {
        Run('"' v1ScriptPath '"', "", "Hide", &pid)
        Sleep 250

        if ProcessExist(pid) {
            exePath := ""
            try exePath := ProcessGetPath(pid)

            if (exePath != "" && !IsAhkV1Exe(exePath)) {
                ; Wrong interpreter (likely AHK v2) -> kill and fall back
                try ProcessClose(pid)
                pid := 0
            } else if (exePath != "") {
                ; Good (v1)
                return true
            }
            ; If exePath is empty, we can't verify -> fall back below
        } else {
            pid := 0
        }
    } catch {
        pid := 0
    }

    ; 2) Explicitly locate AHK v1 and run it
    v1Exe := FindAhkV1Exe()
    if !v1Exe {
        MsgBox(
            "AutoHotkey v1 was not found.`n`n"
            "Please install AutoHotkey v1.1.x (Unicode), or associate .ahk files with v1."
        )
        return false
    }

    Run('"' v1Exe '" "' v1ScriptPath '"', "", "Hide", &pid)
    return (pid != 0)
}

IsAhkV1Exe(exePath) {
    ; Checks file version major number (v1 = 1.x, v2 = 2.x)
    ver := ""
    try ver := FileGetVersion(exePath)

    if (ver = "")
        return false

    major := StrSplit(ver, ".")[1] + 0
    return (major = 1)
}

FindAhkV1Exe() {
    ; 1) Cached path
    cached := ""
    try cached := LoadSetting("General", "AhkV1Exe", "")
    if (cached && FileExist(cached) && IsAhkV1Exe(cached))
        return cached

    ; Helper: check a base directory for v1 exes, including one level of subfolders
    findInDir(baseDir) {
        if !baseDir
            return ""
        baseDir := RTrim(baseDir, "\/")

        for exeName in ["AutoHotkeyU64.exe", "AutoHotkey64.exe", "AutoHotkey.exe"] {
            p := baseDir "\" exeName
            if FileExist(p) && IsAhkV1Exe(p)
                return p
        }

        for exeName in ["AutoHotkeyU64.exe", "AutoHotkey64.exe", "AutoHotkey.exe"] {
            Loop Files, baseDir "\*", "D" {
                p := A_LoopFileFullPath "\" exeName
                if FileExist(p) && IsAhkV1Exe(p)
                    return p
            }
        }

        return ""
    }

    ; 2) Registry InstallDir keys
    candidates := [
        ["HKLM\SOFTWARE\AutoHotkey", "InstallDir"],
        ["HKLM\SOFTWARE\WOW6432Node\AutoHotkey", "InstallDir"],
        ["HKCU\SOFTWARE\AutoHotkey", "InstallDir"]
    ]

    for item in candidates {
        key := item[1], val := item[2]
        try {
            dir := RegRead(key, val)
            found := findInDir(dir)
            if found {
                SaveSetting("General", "AhkV1Exe", found)
                return found
            }
        }
    }

    ; 3) Common Program Files locations
    for dir in [A_ProgramFiles "\AutoHotkey", A_ProgramFiles " (x86)\AutoHotkey"] {
        found := findInDir(dir)
        if found {
            SaveSetting("General", "AhkV1Exe", found)
            return found
        }
    }

    ; 4) Prompt user as last resort
    MsgBox(
    "AutoHotkey v1 could not be found automatically.`n`n"
    "On the next window, please select AutoHotkeyU64.exe (or AutoHotkey.exe).`n"
    "Common locations include:`n"
    "  C:\Program Files\AutoHotkey\`n"
    "  C:\Program Files\AutoHotkey\v1.*\`n"
    "  C:\Program Files (x86)\AutoHotkey\"
)

    chosen := PromptForAhkV1Exe()
    if chosen {
        SaveSetting("General", "AhkV1Exe", chosen)
        return chosen
    }

    return ""
}

PromptForAhkV1Exe() {
    ; Determine a good starting folder
    startDir := ""
    try {
        cached := LoadSetting("General", "AhkV1Exe", "")
        if (cached && FileExist(cached)) {
            SplitPath(cached, , &dir)
            startDir := dir
        }
    }

    if (startDir = "") {
        pf := A_ProgramFiles "\AutoHotkey"
        pf86 := A_ProgramFiles " (x86)\AutoHotkey"
        startDir := FileExist(pf) ? pf : (FileExist(pf86) ? pf86 : A_ProgramFiles)
    }

    filter := "AutoHotkey Executable (AutoHotkey*.exe)|AutoHotkey*.exe|Executable (*.exe)|*.exe"

    Loop {
        exe := FileSelect(1, startDir, "Select AutoHotkey v1 executable", filter)
        if !exe
            return ""  ; user cancelled

        ; Update startDir so retry opens where they were browsing
        SplitPath(exe, , &startDir)

        if !FileExist(exe) {
            MsgBox("That file does not exist. Please select a valid file.")
            continue
        }

        if !IsAhkV1Exe(exe) {
            MsgBox(
                "That executable is not AutoHotkey v1.`n`n"
                "Please select AutoHotkey v1.1.x (Unicode)."
            )
            continue
        }

        return exe
    }
}

RestoreDefaults(*) {
    global
    ; --- Define your defaults ---
    defaultGameTitle := ""  ; unset => cue banner placeholder
    defaultShowOverlay := 1

    ; --- Anti-Ban defaults from centralized metadata ---
    defaultOvershootEnabled := FEATURE_META["Overshoot"]["enabledDefault"]
    defaultOvershoot        := FEATURE_META["Overshoot"]["valueDefault"]

    defaultRandSleepEnabled := FEATURE_META["RandSleep"]["enabledDefault"]
    defaultRandSleepMax     := FEATURE_META["RandSleep"]["durationDefault"]
    defaultRandSleepChance  := FEATURE_META["RandSleep"]["chanceDefault"]

    ; --- Persist defaults to settings file ---
    SaveSetting("General", "GameTitle", defaultGameTitle)
    SaveSetting("General", "ShowOverlay", defaultShowOverlay)

    SaveSetting("AntiBan", "OvershootEnabled", defaultOvershootEnabled)
    SaveSetting("AntiBan", "Overshoot", defaultOvershoot)
	
	SaveSetting("AntiBan", "RandSleepEnabled", defaultRandSleepEnabled)
	SaveSetting("AntiBan", "RandSleepMax", defaultRandSleepMax)
	SaveSetting("AntiBan", "RandSleepChance", defaultRandSleepChance)

    ; Clear cached AHK v1 exe path so user can re-pick if needed
    SaveSetting("General", "AhkV1Exe", "")

    ; --- Update Runtime variables & General defaults ---
	gameTitle := defaultGameTitle
	editGameTitle.Value := ""

	; Remove persisted title so it returns to cue placeholder
	try IniDelete(settingsFile, "General", "GameTitle")

	; Re-apply cue banner
	SetCueBanner(editGameTitle.Hwnd, "RuneLite - CHARACTERNAME", true)

    showOverlay := (defaultShowOverlay != 0)

    overshootEnabled := (defaultOvershootEnabled != 0)
    overshootValue := defaultOvershoot
	
	randSleepEnabled := (defaultRandSleepEnabled != 0)
	randSleepMax := defaultRandSleepMax
	randSleepChance := defaultRandSleepChance

    ; --- Update General tab controls ---
    try chkShowOverlay.Value := defaultShowOverlay
    try editGameTitle.Value := defaultGameTitle

    ; --- Update AntiBan controls ---
    try chkOvershoot.Value := defaultOvershootEnabled
    try editOvershoot.Text := defaultOvershoot
    try upDown.Value := defaultOvershoot
    try SetOvershootControlsEnabled(overshootEnabled)
	
	try chkRandSleep.Value := defaultRandSleepEnabled
	try editRandSleep.Text := defaultRandSleepMax
	try upDownRandSleep.Value := defaultRandSleepMax

	try editRandSleepChance.Text := defaultRandSleepChance
	try upDownRandSleepChance.Value := defaultRandSleepChance

	try SetRandSleepControlsEnabled(randSleepEnabled)

    ; --- Apply overlay changes immediately ---
    if showOverlay {
        overlayGui.Show("NoActivate")
        UpdateOverlayAndPosition()
    } else {
        overlayGui.Hide()
    }

    ; --- Brief UI confirmation (overrides the normal status temporarily) ---
    inlineOverride := true
    SetInlineStatus("All settings set to Default.", "Gray")

    SetTimer(ClearInlineOverride, -2500)
}

UpdateRandSleepChance(*) {
    global editRandSleepChance, upDownRandSleepChance, randSleepChance

    val := editRandSleepChance.Text
    if !RegExMatch(val, "^\d+$")
        val := 0

    val := Clamp(val, 0, 100)

    randSleepChance := val
    editRandSleepChance.Text := val
    upDownRandSleepChance.Value := val

    SaveSetting("AntiBan", "RandSleepChance", val)
}

UpdateRunButtons() {
    global runState, btnStart, btnStop

    ; --- Start button text ---
    if (runState = "running") {
        btnStart.Text := "Running"
    } else if (runState = "paused") {
        btnStart.Text := "Resume"
    } else {
        btnStart.Text := "Start"
    }

    ; --- Stop button text ---
    if (runState = "running") {
        btnStop.Text := "Pause"
    } else if (runState = "paused") {
        btnStop.Text := "Paused"
    } else {
        btnStop.Text := "Stop"
    }

    ; --- Enabled states (disabled buttons auto-grey in Windows) ---
    btnStart.Enabled := (runState != "running")   ; Start/Resume enabled when stopped/paused
    btnStop.Enabled  := (runState = "running")    ; Pause enabled only when running
}

GetRunState() {
    global runState, v1PID

    ; Only force stopped if we have a PID and it's gone.
    ; (If v1PID=0 during startup, don't overwrite the state.)
    if (runState != "stopped" && v1PID && !ProcessExist(v1PID))
        runState := "stopped"

    return runState
}

SetInlineStatus(text, colorName) {
    global lblRestoreStatus
    try {
        ; SetFont on the control updates the text color
        lblRestoreStatus.SetFont("c" colorName)
        lblRestoreStatus.Text := text
    }
}

UpdateInlineStatus() {
    global inlineOverride
    if inlineOverride
        return

    state := GetRunState()
    if (state = "running") {
        SetInlineStatus("Script Status - Active", "Green")
    } else if (state = "paused") {
        SetInlineStatus("Script Status - Paused", "Red")
    } else {
        SetInlineStatus("Script Status - Inactive", "Gray")
    }
}

ClearInlineOverride(*) {
    global inlineOverride
    inlineOverride := false
    UpdateInlineStatus()
}

WatchWorkerHealth(*) {
    global v1PID, runState, isRunning, inlineOverride

    ; If RestoreDefaults override is showing, don't fight it.
    ; We'll correct status on the next tick after override clears.
    if inlineOverride
        return

    ; If we have a PID but the process is gone, reset state
    if (v1PID && !ProcessExist(v1PID)) {
        v1PID := 0
        isRunning := false
        runState := "stopped"
        UpdateRunButtons()
        UpdateInlineStatus()
        return
    }

    ; If UI thinks we're running/paused but we don't even have a PID, normalize
    if ((runState = "running" || runState = "paused") && !v1PID) {
        isRunning := false
        runState := "stopped"
        UpdateRunButtons()
        UpdateInlineStatus()
        return
    }
}

ShutdownController(*) {
    global v1PID, overlayGui, showOverlay
    static shuttingDown := false

    if shuttingDown
        return
    shuttingDown := true

    ; Stop timers (prevents them from running while we tear down)
    try SetTimer(UpdateOverlayAndPosition, 0)
    try SetTimer(WatchWorkerHealth, 0)

    ; Hide overlay
    try overlayGui.Hide()

    ; If worker exists, resume it (if suspended) and terminate it
    if (v1PID && ProcessExist(v1PID)) {
        try ProcessResume(v1PID)   ; harmless if not suspended, helpful if it is
        try ProcessClose(v1PID)    ; hard terminate
        v1PID := 0
    }

    ExitApp
}

ManSleep(minMs := 10, maxMs := "") {
    global randSleepEnabled, randSleepMax, randSleepChance
    global runState

    ; Only operate when enabled AND controller state is running
    if !randSleepEnabled
        return 0
    if (runState != "running")
        return 0

    ; Chance roll (0-100)
    if (randSleepChance <= 0)
        return 0
    if (randSleepChance < 100) {
        roll := Random(1, 100)
        if (roll > randSleepChance)
            return 0
    }

    ; Hard safety floor
    if (minMs < 10)
        minMs := 10

    maxSleep := (maxMs = "") ? randSleepMax : maxMs
    if (maxSleep < minMs)
        maxSleep := minMs

    ms := Random(minMs, maxSleep)
    Sleep ms
    return ms
}

SetAntiBanSubTab(which) {
    global gbFeatures, gbTuning
    global chkOvershoot, chkRandSleep
    global lblOvershootTune, editOvershoot, upDown
    global lblRandSleepDur, editRandSleep, upDownRandSleep
    global lblRandSleepChance, editRandSleepChance, upDownRandSleepChance
    global btnAntiFeatures, btnAntiTuning

    showFeatures := (which = "features")
    showTuning := !showFeatures

    ; Panels
    gbFeatures.Visible := showFeatures
    gbTuning.Visible := showTuning

    ; Feature controls
    chkOvershoot.Visible := showFeatures
    chkRandSleep.Visible := showFeatures

    ; Tuning controls
    lblOvershootTune.Visible := showTuning
    editOvershoot.Visible := showTuning
    upDown.Visible := showTuning

    lblRandSleepDur.Visible := showTuning
    editRandSleep.Visible := showTuning
    upDownRandSleep.Visible := showTuning

    lblRandSleepChance.Visible := showTuning
    editRandSleepChance.Visible := showTuning
    upDownRandSleepChance.Visible := showTuning

    ; Button enabled hints (optional, feels tab-like)
    btnAntiFeatures.Enabled := !showFeatures
    btnAntiTuning.Enabled := !showTuning
}

AddCtrlToolTip(guiObj, ctrlObj, tipText) {
    static TTS_ALWAYSTIP := 0x01
    static TTS_NOPREFIX  := 0x02
    static TTF_IDISHWND  := 0x0001
    static TTF_SUBCLASS  := 0x0010
    static WM_USER       := 0x0400
    static TTM_ADDTOOLW  := WM_USER + 50
    static TTM_SETMAXTIPWIDTH := WM_USER + 24
	static TTM_SETDELAYTIME := WM_USER + 3
	static TTDT_INITIAL := 3   ; time before first showing
	static TTDT_RESHOW  := 1   ; time before showing on next control
	static TTDT_AUTOPOP := 2   ; time tooltip remains visible

    ; Create one tooltip window per GUI (cached)
    if !guiObj.HasProp("_ttHwnd") || !guiObj._ttHwnd {
        ; TOOLTIPS_CLASS = "tooltips_class32"
        ttHwnd := DllCall("CreateWindowExW"
            , "UInt", 0
            , "WStr", "tooltips_class32"
            , "Ptr",  0
            , "UInt", TTS_ALWAYSTIP | TTS_NOPREFIX
            , "Int",  0, "Int", 0, "Int", 0, "Int", 0
            , "Ptr",  guiObj.Hwnd
            , "Ptr",  0
            , "Ptr",  0
            , "Ptr",  0
            , "Ptr")
        guiObj._ttHwnd := ttHwnd

        ; Allow multi-line tooltips
        SendMessage(TTM_SETMAXTIPWIDTH, 0, 300, ttHwnd)
		; Delay times are in milliseconds
		SendMessage(TTM_SETDELAYTIME, TTDT_INITIAL, 200, ttHwnd)  ; hover 0.2s before showing
		SendMessage(TTM_SETDELAYTIME, TTDT_RESHOW,  50,  ttHwnd)  ; quick switching between controls
		SendMessage(TTM_SETDELAYTIME, TTDT_AUTOPOP, 0, ttHwnd) ; stays indefinitely while hovered, time in ms
    } else {
        ttHwnd := guiObj._ttHwnd
    }

    ; TOOLINFO struct (Unicode). Size depends on ptr size.
    ; typedef struct tagTOOLINFOW {
    ;   UINT cbSize; UINT uFlags; HWND hwnd; UINT_PTR uId;
    ;   RECT rect; HINSTANCE hinst; LPWSTR lpszText; LPARAM lParam;
    ; } TOOLINFOW;
    cbSize := (A_PtrSize = 8) ? 72 : 48
    ti := Buffer(cbSize, 0)

    NumPut("UInt", cbSize, ti, 0)
    NumPut("UInt", TTF_IDISHWND | TTF_SUBCLASS, ti, 4)
    NumPut("Ptr",  guiObj.Hwnd, ti, 8)
    NumPut("Ptr",  ctrlObj.Hwnd, ti, 8 + A_PtrSize) ; uId = control HWND when TTF_IDISHWND

    ; Keep tip text alive
    if !ctrlObj.HasProp("_tipBuf") || !ctrlObj._tipBuf
        ctrlObj._tipBuf := Buffer((StrLen(tipText) + 1) * 2, 0)
    StrPut(tipText, ctrlObj._tipBuf, "UTF-16")
    NumPut("Ptr", ctrlObj._tipBuf.Ptr, ti, (A_PtrSize=8) ? 48 : 36)

    SendMessage(TTM_ADDTOOLW, 0, ti.Ptr, ttHwnd)
}

; =========================
; SHA-256 (hex) + bytes
; =========================
SHA256(str) {
    hashBuf := SHA256_BYTES(str)
    result := ""
    Loop 32
        result .= Format("{:02x}", NumGet(hashBuf, A_Index - 1, "UChar"))
    return result
}

SHA256_BYTES(str) {
    hashBuf := Buffer(32, 0)
    cbHash  := Buffer(4, 0)
    NumPut("UInt", 32, cbHash, 0)

    if !DllCall("Crypt32\CryptHashCertificate"
        , "Ptr", 0
        , "UInt", 0x0000800C  ; CALG_SHA_256
        , "UInt", 0
        , "AStr", str
        , "UInt", StrLen(str)
        , "Ptr", hashBuf.Ptr
        , "Ptr", cbHash.Ptr)
        throw Error("CryptHashCertificate failed")

    return hashBuf
}

BytesToHex(buf, len := -1) {
    if (len < 0)
        len := buf.Size
    hex := ""
    Loop len
        hex .= Format("{:02x}", NumGet(buf, A_Index - 1, "UChar"))
    return hex
}

; =========================
; Base64 decode
; =========================
Base64_Decode(b64) {
    static tbl := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    static rev := Map()
    static inited := false

    if !inited {
        Loop Parse, tbl
            rev[A_LoopField] := A_Index - 1
        inited := true
    }

    if (b64 = "")
        throw Error("Empty Base64 input")

    if (Mod(StrLen(b64), 4) != 0)
        throw Error("Invalid Base64 length")

    pad := 0
    if (SubStr(b64, -1) = "=")
        pad += 1
    if (SubStr(b64, -2, 1) = "=")
        pad += 1

    outLen := (StrLen(b64) // 4) * 3 - pad
    out := Buffer(outLen, 0)

    o := 0
    i := 1
    while (i <= StrLen(b64)) {
        c1 := SubStr(b64, i, 1), c2 := SubStr(b64, i+1, 1), c3 := SubStr(b64, i+2, 1), c4 := SubStr(b64, i+3, 1)
        i += 4

        if (!rev.Has(c1) || !rev.Has(c2) || (c3 != "=" && !rev.Has(c3)) || (c4 != "=" && !rev.Has(c4)))
            throw Error("Invalid Base64 character(s)")

        v1 := rev[c1]
        v2 := rev[c2]
        v3 := (c3 = "=") ? 0 : rev[c3]
        v4 := (c4 = "=") ? 0 : rev[c4]

        trip := (v1 << 18) | (v2 << 12) | (v3 << 6) | v4

        if (o < outLen)
            NumPut("UChar", (trip >> 16) & 0xFF, out, o), o += 1
        if (c3 != "=" && o < outLen)
            NumPut("UChar", (trip >> 8) & 0xFF, out, o), o += 1
        if (c4 != "=" && o < outLen)
            NumPut("UChar", trip & 0xFF, out, o), o += 1
    }

    return out
}

; =========================
; Deobfuscation (Salt + XOR + Base64)
; =========================
License_Deobfuscate_FromBase64(b64Text, secret) {
    blob := Base64_Decode(b64Text)
    if (blob.Size < 17)
        throw Error("License blob too short")

    salt := Buffer(16, 0)
    DllCall("RtlMoveMemory", "Ptr", salt.Ptr, "Ptr", blob.Ptr, "UPtr", 16)

    ctLen := blob.Size - 16
    ct := Buffer(ctLen, 0)
    DllCall("RtlMoveMemory", "Ptr", ct.Ptr, "Ptr", blob.Ptr + 16, "UPtr", ctLen)

    saltHex := BytesToHex(salt)
    keyBytes := SHA256_BYTES(saltHex "|" secret)

    pt := Buffer(ctLen, 0)
    Loop ctLen {
        b := NumGet(ct, A_Index - 1, "UChar")
        k := NumGet(keyBytes, Mod(A_Index - 1, 32), "UChar")
        NumPut("UChar", b ^ k, pt, A_Index - 1)
    }

    return StrGet(pt, ctLen, "UTF-8")
}

ctrlGui.OnEvent("Close", ShutdownController)
OnExit(ShutdownController)