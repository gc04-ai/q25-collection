<#
  LineageOS Q25 (Zinwa Q25 Pro) Install Script
  Checks/installs ADB + fastboot, downloads files, unlocks
  bootloader, flashes partitions + recovery, sideloads
  LineageOS + optional GApps, installs APKs + wallpapers
#>

#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$HELP_FLAGS = @('-?','-help','--help','/?')

function ShowHelp {
    Write-Host -ForegroundColor Green @'
Usage: .\install-lineageos-q25.ps1 [options]

Automated LineageOS 23.2 installer for Zinwa Q25 Pro.
By default, running the script with no arguments will launch the full interactive guide.

Options:
  -help, --help, -?, /?    Show this help menu

Quick-Run Flags (Skip the full interactive guide):
  -bootloader | -b    Check current bootloader unlock status
  -imei | -ic         Run the IMEI check utility
  -postinstall | -pi  Run the post-install app (APK) and wallpaper pusher
  -remediate | -if    Run the IMEI remediation tool
  -unlock | -u        Launch the bootloader unlock sequence
  -relock | -rl       Re-lock the bootloader (stock restore)
  -stock              Flash stock firmware via fastboot
  -download | -d      Download all firmware files and exit
  -check | -c         Check LineageOS API for the latest builds.

Run as Administrator for best results.
'@
    exit 0
}

if ($args | Where-Object { $_ -in $HELP_FLAGS }) { ShowHelp }

# ---- CONFIG ----------------------------------------------------------------
$SCRIPT_NAME     = 'LineageOS Q25 Installer'
$DEVICE          = 'Q25'
$OEM             = 'Zinwa'
$PLATFORM_TOOLS  = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'
$GAPPS_URL       = 'https://github.com/MindTheGapps/16.0.0-arm64/releases/latest/download/MindTheGapps-16.0.0-arm64-20260409_073023.zip'
$GAPPS_API       = 'https://api.github.com/repos/MindTheGapps/16.0.0-arm64/releases/latest'
$LINEAGE_API     = "https://download.lineageos.org/api/v2/devices/$DEVICE/builds"
$SF_BASE         = 'https://sourceforge.net/projects/noprincesshere/files/lineage-23.2/Q25/20260519'
$SF_HASHES       = @{
  'lineage-23.2-20260519-UNOFFICIAL-GMS-Q25.zip' = '64d8a6097048756e56032b37085e2988642ea157237bcc9454aa4aff3c74816c'
}
$WORK_DIR        = Join-Path $PWD.Path 'lineageos-install'
$APK_FOLDER      = Join-Path $PWD.Path 'apks'
$WALLPAPER_DIR   = Join-Path $PWD.Path 'wallpapers'
$STOCK_DIR       = Join-Path $PWD.Path 'stock'
$STOCK_ZIP_ID    = '1bqwBa9aDyaMXZf02JS8qmxgMwQ9uaqUK'

# create working directories up front so user knows where to place files
foreach ($d in @($WORK_DIR, $APK_FOLDER, $WALLPAPER_DIR, $STOCK_DIR)) {
  New-Item -ItemType Directory -Path $d -Force | Out-Null
}

# ---- HELPERS ---------------------------------------------------------------
function Banner {
  Clear-Host
  Write-Host ('=' * 70) -ForegroundColor Cyan
  Write-Host "                        $SCRIPT_NAME" -ForegroundColor Cyan
  Write-Host "                        Device: $OEM $DEVICE" -ForegroundColor Cyan
  Write-Host ('=' * 70) -ForegroundColor Cyan
  ShowWatermelon
  Write-Host -ForegroundColor Cyan @'
Automated LineageOS 23.2 installer for Zinwa Q25 Pro.

Steps (all interactive / guided):
  1. Pre-checks             Admin rights, ADB/fastboot
  2. Bootloader unlock      Guided unlock via fastboot
  3. File downloads         LineageOS API + optional manual fallback
  4. Google Apps            Optional MindTheGapps download
  5. Flash partitions       boot, dtbo, vbmeta, vendor_boot (recovery)
  6. Sideload ROM           Factory reset, sideload LineageOS + GApps
  7. Post-install           Install APKs, push wallpapers via ADB
  8. Flash Stock            Flash back to stock OS if needed
'@
  Write-Host ""
  Ok "Work dir:     $WORK_DIR"    
  Ok "APKs:         $APK_FOLDER"   
  Ok "Wallpapers:   $WALLPAPER_DIR" 
  Write-Host ""
  Info "[optional] You can stage files in Work Dir, APKs, and Wallpapers."
  Info "[default]  You can let the script download everything for you."
  Write-Host ""
  Warn 'Run as Administrator for best results'
  Pause
}


function Step  { param([string]$M); Write-Host "`n>> $M" -ForegroundColor Yellow }
function Info  { param([string]$M); Write-Host "   $M" -ForegroundColor Gray }
function Ok    { param([string]$M); Write-Host "   [OK] $M" -ForegroundColor Green }
function Warn  { param([string]$M); Write-Host "   [!] $M" -ForegroundColor Magenta }
function Err   { param([string]$M); Write-Host "   [ERR] $M" -ForegroundColor Red }

function Confirm {
  param([string]$M)
  do { $r = Read-Host "`n$M (y/n)" } while ($r -notin @('y','n'))
  return $r -eq 'y'
}

function Pause { Read-Host "`nPress Enter to continue" }

function HasCmd {
  param([string]$C)
  return [bool](Get-Command $C -ErrorAction SilentlyContinue)
}

function DownloadFile {
    param(
        [Parameter(Mandatory=$true)] [string]$Url,
        [Parameter(Mandatory=$true)] [string]$Dest,
        [Parameter(Mandatory=$true)] [string]$Name
    )
    
    Info "Downloading $Name..."
    
    # Temporarily bypass strict error rules so curl's progress bar doesn't kill the script
    $oldErr = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    
    try {
        & curl.exe --progress-bar -L -C - -o "$Dest" "$Url"
        
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 33) {
            throw "curl.exe dropped connection (Exit Code: $LASTEXITCODE)"
        }
        
        # Sanity check: reject zero-byte files
        if ((Get-Item $Dest).Length -eq 0) {
            Remove-Item $Dest -Force -ErrorAction SilentlyContinue
            throw "Downloaded file is empty"
        }
        
        Ok "$Name downloaded and verified"
        return $true
    } catch {
        Err "Failed to download $($Name): $_"
        return $false
    } finally {
        # Restore strict error handling for the rest of the script
        $ErrorActionPreference = $oldErr
    }
}

function ShowWatermelon {
    Write-Host ""
    Write-Host "                               /\       " -ForegroundColor Red
    Write-Host "                              /  \      " -ForegroundColor Red
    Write-Host "                             / o  \     " -ForegroundColor Red
    Write-Host "                            /      \    " -ForegroundColor Red
    Write-Host "                           / o    o \   " -ForegroundColor Red
    Write-Host "                          /    o     \  " -ForegroundColor Red
    Write-Host "                         / o      o   \ " -ForegroundColor Red
    Write-Host "                        /______________\" -ForegroundColor Red
    Write-Host "                        \______________/" -ForegroundColor Green
    Write-Host ""
}

function CheckForUpdates {
  Step 'Checking for LineageOS updates'
  $latest = GetBuilds
  if ($latest) {
    Ok "Latest build available: $($latest.version)"
    Info "Build date: $($latest.datetime)"
  } else {
    Warn 'Could not retrieve build information from LineageOS API.'
  }
  exit 0
}

# ---- PRE-CHECKS ------------------------------------------------------------
function CheckAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Warn 'Run as Administrator for best results'
    if (-not (Confirm 'Continue anyway?')) { exit 1 }
  }
}

function InstallTools {
  Step 'Checking ADB and fastboot'

  # FIX: Actually define ADB_DIR before calling it later.
  $ADB_DIR = "$env:USERPROFILE\platform-tools"
  $need = $false
  if (-not (HasCmd adb))     { Info 'adb not found'; $need = $true }
  if (-not (HasCmd fastboot)) { Info 'fastboot not found'; $need = $true }
  if (-not $need) { Ok 'ADB and fastboot available'; return }

  Info 'Downloading platform-tools from Google'
  $zip = Join-Path $env:TEMP 'platform-tools-latest-windows.zip'
  if (-not (DownloadFile -Url $PLATFORM_TOOLS -Dest $zip -Name "platform-tools")) {
        exit 1
    }

  Info "Extracting to $ADB_DIR"
  if (Test-Path "$ADB_DIR\adb.exe") {
    Start-Process -FilePath "$ADB_DIR\adb.exe" -ArgumentList "kill-server" -WindowStyle Hidden -Wait
    Ok 'ADB killed, installing again.' }
  if (Test-Path $ADB_DIR) { Remove-Item -Recurse -Force $ADB_DIR }
  Expand-Archive -Path $zip -DestinationPath $env:USERPROFILE -Force
  Remove-Item $zip -Force

  # set path for future runs
  $userPath = [Environment]::GetEnvironmentVariable('Path','User')
  if ($userPath -notlike "*$ADB_DIR*") {
    $newPath = "$userPath;$ADB_DIR"
    [Environment]::SetEnvironmentVariable('Path',$newPath,'User')
  }

  # make current session see ADB 
  $env:Path = "$ADB_DIR;$env:Path"

  if (HasCmd netsh) {
    try { netsh advfirewall firewall add rule name='ADB' dir=in action=allow program="$ADB_DIR\adb.exe" enable=yes | Out-Null } catch {}
  }

  # verification check
  if (Test-Path "$ADB_DIR\adb.exe") {
    Start-Process -FilePath "$ADB_DIR\adb.exe" -ArgumentList "kill-server" -WindowStyle Hidden -Wait
    Start-Process -FilePath "$ADB_DIR\adb.exe" -ArgumentList "start-server" -WindowStyle Hidden
    Start-Sleep -Seconds 5
    Ok 'ADB installed and verified'
  } elseif (HasCmd adb) { 
  Ok 'ADB installed' 
  } else { 
    Err "ADB install failed. File not found at $ADB_DIR\adb.exe"; exit 1
  }
}

function InstallFastbootDriver {
  Step 'Checking Fastboot Drivers'

  Info 'Querying Windows Driver Store...'
  # Check if the Google driver's original filename exists in the local driver store
  $driverExists = [bool](pnputil /enum-drivers 2>$null | Select-String 'android_winusb.inf' -Quiet)

  if ($driverExists) {
    Ok 'Google Fastboot Driver OK'
    return 
  }

  $driverZip = Join-Path $env:TEMP 'google_usb_driver.zip'
  $driverDir = Join-Path $env:TEMP 'google_usb_driver_extract'
  $infPath   = Join-Path $driverDir 'usb_driver\android_winusb.inf'

  if (-not (Test-Path $infPath)) {
    Info 'Downloading official Google USB Driver...'
    $driverUrl = 'https://dl-ssl.google.com/android/repository/latest_usb_driver_windows.zip'
    
    if (-not (DownloadFile -Url $driverUrl -Dest $driverZip -Name 'Google USB Driver')) {
      Warn 'Could not download USB driver. Skipping.'
      return
    }
    
    Info "Extracting driver..."
    if (Test-Path $driverDir) { Remove-Item -Recurse -Force $driverDir }
    Expand-Archive -Path $driverZip -DestinationPath $driverDir -Force
    Remove-Item $driverZip -Force
  }

  Info 'Installing driver to Windows (pnputil)...'
  $r = cmd /c "pnputil /add-driver `"$infPath`" /install 2>&1" 2>$null | Out-String
  
  if ($r -match 'Failed') {
    Warn 'Driver installation reported a failure.'
  } else {
    Ok 'Google Fastboot Driver OK'
  }
}

function CheckImei {
  Step 'IMEI check'
  $connected = $false
  do {
    if (CheckDevice 'adb') { $connected = $true; break }
    Warn 'No ADB device connected'
    Write-Host ''
    Write-Host '   To enable USB debugging:' -ForegroundColor Yellow
    Write-Host '     1. Settings - About phone - tap Build Number 7 times' -ForegroundColor Yellow
    Write-Host '     2. Settings - System - Developer options - USB debugging - ON' -ForegroundColor Yellow
    Write-Host '     3. Connect USB cable, check box, accept the RSA fingerprint prompt on the phone' -ForegroundColor Yellow
  } while ((Read-Host "`nRetry (r) or Skip (s)") -eq 'r')
  if (-not $connected) { Warn 'Skipping IMEI check'; return }

  function ReadTacFromProp {
    $r = adb shell 'getprop gsm.imei' 2>$null
    if ($r -match '(\d{15})') { return $Matches[1].Substring(0,8) }
    return $null
  }

  $tac = ReadTacFromProp

  if (-not $tac) {
    Write-Host ''
    Info 'Launching IMEI settings app on your phone...'
    cmd /c "adb shell am start -n com.android.imeisettings/com.android.imeisettings.ImeiSettings 2>nul" 2>$null | Out-Null
    Start-Sleep -Seconds 2
    Write-Host '   The IMEI app should now be visible on your phone.' -ForegroundColor Yellow
    $r = Read-Host '   Enter the first 8 digits (or press Enter to skip)'
    if ($r -match '^\d{8}$') { $tac = $r }
  }

  if (-not $tac) { Info 'Could not determine TAC - skipping'; return }

  Info "TAC: $tac"
  switch ($tac) {
    '35847405' { Warn 'TAC 35847405 = BB Classic device. IMEI may be spoofed.' }
    '35772285' { Warn 'TAC 35772285 = Zinwa Factory. IMEI may be a factory-default.' }
    default    { Ok "TAC $tac looks normal" }
  }
}

function RemediateImei {
  Step 'IMEI Remediation'
  $connected = $false
  do {
    if (CheckDevice 'adb') { $connected = $true; break }
    Warn 'No ADB device connected'
    Write-Host ''
    Write-Host '   To enable USB debugging:' -ForegroundColor Yellow
    Write-Host '     1. Settings - About phone - tap Build Number 7 times' -ForegroundColor Yellow
    Write-Host '     2. Settings - System - Developer options - USB debugging - ON' -ForegroundColor Yellow
    Write-Host '     3. Connect USB cable, check box accept the RSA fingerprint prompt on the phone' -ForegroundColor Yellow
  } while ((Read-Host "`nRetry (r) or Skip (s)") -eq 'r')
  if (-not $connected) { Warn 'Skipping'; return }

  Write-Host ''
  Write-Host '  WARNING: This is may or may not be legal. Please check with your lawyer.' -ForegroundColor Magenta
  Write-Host '  You must have valid IMEI to write. Do NOT generate random IMEIs.' -ForegroundColor Magenta
  Write-Host ''
  if (-not (Confirm 'I confirm this is a remediation on my own device and I have checked with my legal team.')) { return }

  Info 'Launching IMEI settings app on your phone...'
  cmd /c "adb shell am start -n com.android.imeisettings/com.android.imeisettings.ImeiSettings 2>nul" 2>$null | Out-Null
  Start-Sleep -Seconds 2

  Write-Host ''
  Write-Host '  1. The IMEI settings app should now be visible on your phone.' -ForegroundColor Yellow
  Write-Host '  2. Type your new IMEI into the IMEI 1 field.' -ForegroundColor Yellow
  Write-Host '  3. [Optional] Type your new IMEI into the IMEI 2 field.' -ForegroundColor Yellow
  Write-Host '  4. Tap the "Setting" button to save.' -ForegroundColor Yellow
  Write-Host '  5. Reboot your phone to apply the changes.' -ForegroundColor Yellow
  Write-Host '  6. Verify the new IMEI in Settings - About phone.' -ForegroundColor Yellow
  Write-Host ''

  if (Confirm 'Have you applied the new IMEI and rebooted the device?') { Ok 'IMEI remediation complete' }
  else { Warn 'Skipping verification - run IMEI check again after reboot' }
}

# ---- DEVICE DETECTION ------------------------------------------------------
function CheckDevice {
  param([string]$Mode)
  $cmd = if ($Mode -eq 'adb') { 'adb devices' } else { 'fastboot devices' }
  $r = Invoke-Expression $cmd 2>$null
  if ($Mode -eq 'adb') { return ($r -match 'device$|sideload') -and $r -notmatch 'unauthorized' }
  return ($r -match 'fastboot')
}

function WaitDevice {
  param([string]$Mode,[string]$Label)
  Info "Waiting for device in $Mode mode ($Label)"
  $timeout = 120; $elapsed = 0
  
  while ($elapsed -lt $timeout) {
    if (CheckDevice $Mode) { return $true }
    Start-Sleep -Seconds 5; $elapsed += 5
    
    # Only print the heartbeat every 15 seconds
    if ($elapsed % 15 -eq 0) {
      Info ("... waiting " + $elapsed + ' s')
    }

    # Drop the manual instructions exactly once at 5 seconds
    if ($elapsed -eq 5 -and $Mode -eq 'fastboot') {
      Write-Host ' '
      Warn 'If the script hangs here, Windows failed to auto-attach the driver!'
      Write-Host '   1. Open Device Manager and find the yellow (!) device.' -ForegroundColor Yellow
      Write-Host '   2. Right-click -> Update Driver -> Browse my computer -> Let me pick from a list' -ForegroundColor Yellow
      Write-Host '   3. Select "Android Device" -> "Android Bootloader Interface" -> Click Yes' -ForegroundColor Yellow
      Write-Host ' '
      Write-Host '   (Do NOT close this window! The script will automatically resume the second the driver applies)' -ForegroundColor Cyan
      Write-Host ' '
    }
  }
  return $false
}

# ---- DOWNLOADS -------------------------------------------------------------
function GetBuilds {
  Step 'Checking LineageOS download server'
  $builds = @()
  try { $builds = Invoke-RestMethod -Uri $LINEAGE_API -UseBasicParsing -ErrorAction Stop }
  catch { Warn "API unreachable: $_" }

  if (-not $builds -or $builds.Count -eq 0) {
    Warn 'No official builds found for Q25'
    Info 'You will need to provide files manually'
    Info 'Required: boot.img, dtbo.img, vbmeta.img, vendor_boot.img, lineage-*.zip'
    return $null
  }

  $latest = $builds | Sort-Object datetime -Descending | Select-Object -First 1
  Ok ("Found build: " + $latest.version)
  return $latest
}

function GetFile {
  param([string]$Name)
  Write-Host ''
  $c = Read-Host ("Get '$Name' from: (1) URL  (2) Local file path  (3) Skip")
  switch ($c) {
    '1' {
      $url  = Read-Host '  Enter URL'
      $dest = Join-Path $WORK_DIR $Name
      Info "Downloading $Name"
      try { Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing; Ok "$Name downloaded"; return $dest }
      catch { Err "Failed: $_"; return GetFile $Name }
    }
    '2' {
      $prompt = "  Enter file path [$WORK_DIR\$Name]"
      $path   = Read-Host $prompt
      if (-not $path) { $path = Join-Path $WORK_DIR $Name }
      if (Test-Path $path) { Copy-Item $path (Join-Path $WORK_DIR $Name) -Force; Ok "$Name copied"; return (Join-Path $WORK_DIR $Name) }
      Err "Not found: $path"; return GetFile $Name
    }
    '3' { return $null }
    default { return GetFile $Name }
  }
}

function GetGApps {
    if (-not (Confirm 'Install Google Apps (MindTheGapps)?')) { return $null }

    Info 'Fetching latest MindTheGapps'
    try {
        $rel = Invoke-RestMethod -Uri $GAPPS_API -UseBasicParsing -ErrorAction Stop
        $asset = $rel.assets | Where-Object { $_.name -like '*.zip' -and $_.name -notlike '*.sha256*' } | Select-Object -First 1
        $gappsUrl  = $asset.browser_download_url
        $gappsName = $asset.name
    } catch {
        Warn 'GitHub API unavailable, using default URL'
        $gappsUrl  = $GAPPS_URL
        $gappsName = 'MindTheGapps-16.0.0-arm64.zip'
    }

    $dest = Join-Path $WORK_DIR $gappsName

    if (DownloadFile -Url $gappsUrl -Dest $dest -Name $gappsName) {
        return $dest
    } else {
        # Fallback to manual entry if curl totally fails
        return GetFile $gappsName
    }
}

# ---- FLASHING --------------------------------------------------------------
function UnlockBootloader {
  Step 'BOOTLOADER UNLOCK'
  Write-Host '  WARNING: Unlocking the bootloader will:' -ForegroundColor Magenta
  Write-Host '  - ERASE ALL DATA on your device (factory reset)' -ForegroundColor Magenta
  Write-Host '  - May void your warranty' -ForegroundColor Magenta
  Write-Host '  - Device will show a warning on every boot' -ForegroundColor Magenta
  Write-Host '  - Some apps/banking may refuse to run' -ForegroundColor Magenta
  Write-Host '  - You are doing this at your own risk' -ForegroundColor Magenta
  if (-not (Confirm 'Continue with bootloader unlock?')) { Warn 'Skipping'; return }


  Write-Host '  Unlock OEM Bootloader in phone settings first:' -ForegroundColor Yellow
  Write-Host '   - Settings - System - Developer Options' -ForegroundColor Yellow
  Write-Host '   - OEM Unlocking: ON and click Enable on the pop up' -ForegroundColor Yellow
  Write-Host ''
  Warn 'WARNING: Last chance to back out...'
  Pause

  if (-not (WaitDevice adb 'USB Debugging')) { Err 'Device not detected. Check USB cable and RSA prompt.'; exit 1 }

  Info 'Rebooting to bootloader'
  Warn 'Be ready to press VOLUME UP on the phone to confirm when prompted!'
  adb -d reboot bootloader
  Start-Sleep -Seconds 20

  if (-not (WaitDevice fastboot 'fastboot mode')) { Err 'Device not found in fastboot'; exit 1 }

  Info 'Running: fastboot flashing unlock'
  Warn 'IMMEDIATELY press VOLUME UP on the phone to confirm (you have ~5 seconds!)'
  fastboot flashing unlock
  Start-Sleep -Seconds 20
  fastboot reboot

  Info 'If device has not rebooted, reboot it now'
  Info 'It may take longer than normal to boot, give it 30-45 seconds'
  if (Confirm 'Device rebooted and you see the setup wizard?') {
    Ok 'Bootloader unlocked'
    Info '0. Click start - DO NOT CONNECT WIFI - Click setup offline in bottom left - Skip through setup'
    Info '1. Enable Developer Options: Settings - About - tap Build Number 7x'
    Info '2. Enable OEM Unlock + USB Debugging in Settings - System - Developer Options'
    Info '3. Connect phone via USB, check box and accept the RSA key fingerprint prompt on the phone'
      } else {
        Warn 'You may need to manually reboot'
      }
}

function RelockBootloader {
  Step 'Re-lock bootloader'
  Write-Host '  WARNING: Re-locking will:' -ForegroundColor Magenta
  Write-Host '  - Restore the bootloader to locked state' -ForegroundColor Magenta
  Write-Host '  - Device will no longer show the warning on boot' -ForegroundColor Magenta
  Write-Host '  - Only do this if you are on STOCK firmware' -ForegroundColor Magenta
  if (-not (Confirm 'Continue with bootloader relock?')) { Warn 'Skipping'; return }

  if (CheckDevice 'fastboot') { Info 'Already in fastboot' }
  elseif (CheckDevice 'adb') { Info 'Rebooting to fastboot...'; adb -d reboot bootloader; Start-Sleep -Seconds 15 }
  else { Info 'Connect device in fastboot or ADB, then press Enter'; Pause }
  if (-not (WaitDevice fastboot 'fastboot mode')) { Err 'Device not in fastboot'; return }

  Info 'Running: fastboot flashing lock'
  Warn 'IMMEDIATELY press VOLUME UP on the phone to confirm (you have ~5 seconds!)'
  fastboot flashing lock
  Start-Sleep -Seconds 10

  Info 'Rebooting...'
  cmd /c 'fastboot reboot 2>&1' 2>$null | Out-Null
  Ok 'Bootloader relocked. Device rebooting.'
}

function CheckBootloader {
  Step 'Bootloader status check'
  $connected = $false
  do {
    if (CheckDevice 'adb') { $connected = $true; break }
    Warn 'No ADB device connected'
    Write-Host ''
    Write-Host '   To enable USB debugging:' -ForegroundColor Yellow
    Write-Host '     1. Settings - About phone - tap Build Number 7 times' -ForegroundColor Yellow
    Write-Host '     2. Settings - System - Developer options - USB debugging - ON' -ForegroundColor Yellow
    Write-Host '     3. Connect USB cable, check box, accept the RSA fingerprint prompt on the phone' -ForegroundColor Yellow
  } while ((Read-Host "`nRetry (r) or Skip (s)") -eq 'r')
  if (-not $connected) { Warn 'Skipping bootloader check'; return $null }

  Info 'Rebooting to fastboot ...'
  adb -d reboot bootloader
  Start-Sleep -Seconds 10

  if (-not (WaitDevice fastboot 'fastboot mode')) { Err 'Device not found in fastboot'; return $false }

  $unlocked = $null
  $slot     = $null
  $secure   = $null

  $r = cmd /c 'fastboot getvar unlocked 2>&1' 2>$null | Out-String
  if ($r -match 'unlocked:\s*(\S+)') { $unlocked = $Matches[1] }

  $r = cmd /c 'fastboot getvar slot-count 2>&1' 2>$null | Out-String
  if ($r -match 'slot-count:\s*(\S+)') { $slot = $Matches[1] }

  $r = cmd /c 'fastboot getvar secure 2>&1' 2>$null | Out-String
  if ($r -match 'secure:\s*(\S+)') { $secure = $Matches[1] }

  if ($unlocked) { Ok "Bootloader unlocked: $unlocked" } else { Warn 'Could not determine unlock status' }
  if ($slot)     { Info "Slot count: $slot" }
  if ($secure)   { Info "Secure boot: $secure" }

  $isUnlocked = ($unlocked -eq 'yes')

  Info 'Rebooting back to OS ...'
  cmd /c 'fastboot reboot 2>&1' 2>$null | Out-Null
  Start-Sleep -Seconds 10
  if (-not (WaitDevice adb 'OS')) { Warn 'Device did not return from fastboot; you may need to reconnect manually' }

  return $isUnlocked
}

function FlashParts {
  param([string]$Boot,[string]$Dtbo,[string]$Vbmeta)
  Step 'Flashing boot, dtbo, vbmeta'

  if (CheckDevice 'fastboot') {
    Info 'Already in fastboot mode'
  } elseif (CheckDevice 'adb') {
    Info 'Rebooting to fastboot ...'
    adb -d reboot bootloader
    Start-Sleep -Seconds 10
  } else {
    Err 'Device not found in ADB or fastboot mode'
    return $false
  }

  if (-not (WaitDevice fastboot 'fastboot mode')) { Err 'Device not in fastboot'; return $false }

  $items = @(
    @{N='boot';P=$Boot;R=$true},
    @{N='dtbo';P=$Dtbo;R=$true},
    @{N='vbmeta';P=$Vbmeta;R=$true}
  )
  $ok = $true
  foreach ($f in $items) {
    if (-not $f.P -or -not (Test-Path $f.P)) { Err "$($f.N).img not available. Skipping."; if ($f.R) { $ok = $false }; continue }
        Info "Flashing $($f.N).img"
        $r = cmd /c "fastboot flash $($f.N) `"$($f.P)`" 2>&1" 2>$null | Out-String
        if ($r -match 'FAILED') { Err "flash $($f.N) failed: $r"; $ok = $false } else { Ok "$($f.N) flashed" }
  }

  if (-not (WaitDevice fastboot 'fastboot mode')) { Warn 'Device left fastboot after flash'; return $ok }
  return $ok
}

function FlashRecovery {
  param([string]$VendorBoot)
  Step 'Flashing Lineage Recovery (vendor_boot)'

  if (-not (WaitDevice fastboot 'fastboot mode')) { Err 'Device not in fastboot'; return $false }
  if (-not $VendorBoot -or -not (Test-Path $VendorBoot)) { Err 'vendor_boot.img not available'; return $false }

  Info 'Flashing vendor_boot'
  $r = cmd /c "fastboot flash vendor_boot `"$VendorBoot`" 2>&1" 2>$null | Out-String
  if ($r -match 'FAILED') { Err "flash vendor_boot failed: $r"; return $false }
  Ok 'vendor_boot flashed'

  Info 'Booting into recovery'
  cmd /c 'fastboot reboot recovery 2>&1' 2>$null | Out-Null
  Info 'Device should boot into recovery mode now'
  return $true
}
function Sideload {
  param([string]$Rom,[string]$GApps)

  Step 'Sideloading LineageOS'

  Write-Host ''
  Write-Host '   1. On your phone in recovery, select: Factory Reset - Format data/factory reset' -ForegroundColor Yellow
  Write-Host '   2. Confirm the format, then return to main menu' -ForegroundColor Yellow
  Write-Host '   3. Unplug and re-plug the USB cable (this wakes up ADB on some devices)' -ForegroundColor Yellow
  Write-Host '   4. Select: Apply update - Apply from ADB' -ForegroundColor Yellow
  Write-Host '   5. The device will show "Now send the package you want to apply..."' -ForegroundColor Yellow
  Write-Host ''
  Pause

  if (-not $Rom -or -not (Test-Path $Rom)) { Err 'LineageOS zip not found'; exit 1 }

  Info 'Sideloading ROM'
  Info 'This will take 10+ minutes; it may appear stalled -- this is normal, do not unplug or restart!'
  Warn 'If you see ERROR: recovery: Open failed: /metadata/ota: No such file or directory on phone, ignore it and keep waiting'
  Info 'You will not see a progress bar here. Watch your phone screen!'
  Warn 'When the sideload finishes, the phone will ask "Flash another zip?".'
  Write-Host '   The script will continue as soon as you tap "No" (or "Yes" for GApps) on the phone.' -ForegroundColor Yellow

  # Launch sideload in the background so it cannot freeze the script
  $adbJob = Start-Process -FilePath "adb" -ArgumentList "-d sideload `"$Rom`"" -WindowStyle Hidden -PassThru

  # Give ADB 5 seconds to establish the connection
  Start-Sleep -Seconds 5

  # Monitor the phone's state. It will report 'sideload' while flashing.
    $elapsed = 0
    while ((cmd /c "adb devices 2>&1") -match 'sideload') {
      Start-Sleep -Seconds 5
      $elapsed += 5
      if ($elapsed % 15 -eq 0) {
        Info "... sideloading ROM ($elapsed s) - Watch phone for yes/no "
      }
    }

  # Once the state drops from 'sideload' to 'recovery', kill the zombie ADB process
  if (-not $adbJob.HasExited) {
    $adbJob | Stop-Process -Force 2>$null
  }

  Ok 'LineageOS installed'

  if ($GApps -and (Test-Path $GApps)) {
    Write-Host '   When prompted on device: choose Yes to reboot to recovery for add-ons' -ForegroundColor Yellow
    Write-Host '   After reboot: Apply update - Apply from ADB again' -ForegroundColor Yellow
    Pause

    Info 'Sideloading GApps...'
    $gappsJob = Start-Process -FilePath "adb" -ArgumentList "-d sideload `"$GApps`"" -WindowStyle Hidden -PassThru

    Start-Sleep -Seconds 5
    # Monitor the GApps sideload
    $elapsed = 0
    while ((cmd /c "adb devices 2>&1") -match 'sideload') {
      Start-Sleep -Seconds 5
      $elapsed += 5
      if ($elapsed % 15 -eq 0) {
        Info "... sideloading GApps ($elapsed s) - Watch phone for yes/no "
      }
    }

    if (-not $gappsJob.HasExited) {
      $gappsJob | Stop-Process -Force 2>$null
    }
    
    Ok 'GApps installed'
    Info 'If signature verification fails, select Yes to continue (normal for GApps)'
  }

  Write-Host '   If you are NOT installing GApps, click click Reboot system now' -ForegroundColor Yellow
  if (Confirm 'Ready to reboot?') {
    Ok 'LineageOS is installed. First boot may take up to 15 minutes.'
  }
}

# ---- POST-INSTALL ----------------------------------------------------------
function PostInstall {
    Step 'Post-install: installing apps and wallpapers'

    if (Confirm 'Download default APKs and wallpapers from GitHub?') {
        $repo = Read-Host "   Enter GitHub repo [gc04-ai/q25-lineage-installer]"
        if (-not $repo) { $repo = 'gc04-ai/q25-lineage-installer' }
        
        # Ensure target folders exist
        if (-not (Test-Path $APK_FOLDER)) { New-Item -ItemType Directory -Path $APK_FOLDER -Force | Out-Null }
        if (-not (Test-Path $WALLPAPER_DIR)) { New-Item -ItemType Directory -Path $WALLPAPER_DIR -Force | Out-Null }

        $apiUrl = "https://api.github.com/repos/$repo/contents"
        $targets = @(
            @{ GitPath='apks'; Local=$APK_FOLDER },
            @{ GitPath='wallpapers'; Local=$WALLPAPER_DIR }
        )
        
        foreach ($dir in $targets) {
            Info "Checking GitHub for $($dir.GitPath)..."
            try {
                $items = Invoke-RestMethod -Uri "$apiUrl/$($dir.GitPath)" -UseBasicParsing -ErrorAction Stop
                
                foreach ($item in $items | Where-Object { $_.type -eq 'file' }) {
                    $dest = Join-Path $dir.Local $item.name
                    # Let the helper handle auto-resuming and file-skipping
                    DownloadFile -Url $item.download_url -Dest $dest -Name $item.name | Out-Null
                }
            } catch {
                Warn "  Failed to read $($dir.GitPath) from $repo. (Check repo name or folder structure)"
            }
        }
    }

    Warn 'Make sure USB Debugging is on'
    Write-Host ''
    Write-Host '   To enable USB debugging:' -ForegroundColor Yellow
    Write-Host '     1. Settings - About phone - tap Build Number 7 times' -ForegroundColor Yellow
    Write-Host '     2. Settings - System - Developer options - USB debugging - ON' -ForegroundColor Yellow
    Write-Host '     3. Connect USB cable, check box, accept the RSA fingerprint prompt on the phone' -ForegroundColor Yellow
    Pause

    if (-not (WaitDevice adb 'Android after first boot')) {
        Warn 'Device not found. Run this step later manually.'
        Info '  adb install MyApp.apk'
        Info '  adb push wallpaper.jpg /sdcard/Pictures/'
        return
    }

    # APKs
    if (Test-Path $APK_FOLDER) {
        $apks = Get-ChildItem $APK_FOLDER -Filter '*.apk' -ErrorAction SilentlyContinue
        if ($apks) {
            Info "Installing $($apks.Count) APK(s)"
            foreach ($apk in $apks) {
                Info "  Installing $($apk.Name)"
                $r = cmd /c "adb install -r `"$($apk.FullName)`" 2>&1" 2>$null | Out-String
                if ($r -match 'Success|success') {
                    Ok "$($apk.Name) installed"
                } else {
                    Warn "$($apk.Name) failed: $r"
                }
            }
        } else {
            Info 'No APKs found in ' + $APK_FOLDER
        }
    } else {
        New-Item -ItemType Directory -Path $APK_FOLDER -Force | Out-Null
        Info "Created $APK_FOLDER - place APKs here"
    }

    # Wallpapers
    if (Test-Path $WALLPAPER_DIR) {
        $images = Get-ChildItem (Join-Path $WALLPAPER_DIR '*') -Include '*.jpg','*.jpeg','*.png','*.webp' -ErrorAction SilentlyContinue
        if ($images) {
            Info "Pushing $($images.Count) wallpaper(s)"
            $remoteDir = '/sdcard/Pictures/Wallpapers'
            cmd /c "adb shell mkdir -p $remoteDir 2>&1" 2>$null | Out-Null
            
            foreach ($img in $images) {
                Info "  Pushing $($img.Name)"
                $r = cmd /c "adb push `"$($img.FullName)`" $remoteDir/ 2>&1" 2>$null | Out-String
                if ($r -match 'pushed|success') {
                    Ok "$($img.Name) pushed"
                } else {
                    Warn "$($img.Name) failed: $r"
                }
            }
        } else {
            Info 'No images found in ' + $WALLPAPER_DIR
        }
    } else {
        New-Item -ItemType Directory -Path $WALLPAPER_DIR -Force | Out-Null
        Info "Created $WALLPAPER_DIR - place wallpapers here"
    }

    Ok 'Post-install complete'
}

# ---- STOCK FLASH (fastboot) -------------------------------------------------
function DownloadStockFirmware {
  Step 'Download stock firmware'
  $zip = Join-Path $STOCK_DIR 'OS-permissions-0326-Q25-GMS.zip'
  $id  = $STOCK_ZIP_ID
  if (Test-Path $zip) { Info 'Already downloaded'; return $zip }

  $dlUrl = "https://drive.usercontent.google.com/download?id=$id&export=download&authuser=0&confirm=t"
  if (DownloadFile -Url $dlUrl -Dest $zip -Name 'stock firmware (approx 2.7 GB)') {
    if ((Get-Item $zip).Length -lt 1MB) { Err 'File too small'; return $null }
    $size = [math]::Round((Get-Item $zip).Length / 1GB, 1)
    Ok "Downloaded ($size GB)"
    Info 'Extracting (this may take a few minutes)...'
    $extractTimer = Get-Date
    Expand-Archive -Path $zip -DestinationPath $STOCK_DIR -Force
    $elapsed = [math]::Round(((Get-Date) - $extractTimer).TotalSeconds)
    Ok "Extracted in ${elapsed}s"
    return $zip
  }
  Write-Host "  Download manually: https://drive.google.com/file/d/$id/view" -ForegroundColor Yellow
  return $null
}

function FlashStock {
  Step 'Flash stock firmware (fastboot)'

  # scatter may be in stock\ directly or in a subfolder (SP1A.210812.016RELEASE-KEYS)
  $scatter = Get-ChildItem $STOCK_DIR -Recurse -Filter 'MT6789_Android_scatter.txt' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
  if (-not $scatter) {
    if (Confirm 'Download stock firmware from Google Drive (approx 2.7 GB)?') { DownloadStockFirmware | Out-Null }
    $scatter = Get-ChildItem $STOCK_DIR -Recurse -Filter 'MT6789_Android_scatter.txt' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
  }
  if (-not $scatter) { Err 'Scatter file not found'; return }

  # set stock dir to where the scatter lives so images resolve
  $stockDir = Split-Path $scatter

  # parse scatter: filename -> partition_name
  $map = @{}; $part = ''; $file = ''
  Get-Content $scatter | ForEach-Object {
    if     ($_ -match 'partition_name:\s*(\S+)') { $part = $Matches[1] }
    elseif ($_ -match 'file_name:\s*(\S+)') { $file = $Matches[1]; if ($file -ne 'NONE' -and $part -notlike 'preloader*') { $map[$file] = $part } }
  }
  if ($map.Count -eq 0) { Err 'No flashable partitions'; return }

  Info "Found $($map.Count) partitions to flash (excluding preloader)"
  foreach ($kv in $map.GetEnumerator() | Sort-Object Name) {
    $img = Join-Path $stockDir $kv.Name
    if (Test-Path $img) { Info "  $($kv.Name) -> $($kv.Value)  ($([math]::Round((Get-Item $img).Length/1MB,1)) MB)" }
  }
  Write-Host ''
  Write-Host '  WARNING: This wipes LineageOS and restores stock firmware.' -ForegroundColor Magenta
  Write-Host '  super.img is ~5.5 GB -- flashing takes 10-20 minutes. Do NOT unplug.' -ForegroundColor Yellow
  if (-not (Confirm 'Flash stock firmware now?')) { Warn 'Skipping'; return }

  if (CheckDevice 'fastboot') { Info 'Already in fastboot' }
  elseif (CheckDevice 'adb') { Info 'Rebooting to fastboot...'; adb -d reboot bootloader; Start-Sleep -Seconds 15 }
  else { Info 'Connect device in fastboot or ADB, then press Enter'; Pause }
  if (-not (WaitDevice fastboot 'fastboot mode')) { Err 'Device not in fastboot'; return }

  $ok = $true
  foreach ($kv in $map.GetEnumerator()) {
    $img = Join-Path $stockDir $kv.Name
    if (-not (Test-Path $img)) { continue }
    Info "Flashing $($kv.Name)..."
    $r = cmd /c "fastboot flash $($kv.Value) `"$img`" 2>&1" 2>$null | Out-String
    if ($r -match 'FAILED') { Err "flash $($kv.Name) failed: $r"; $ok = $false } else { Ok "$($kv.Name) flashed" }
  }
  if ($ok) { cmd /c 'fastboot reboot 2>&1' 2>$null | Out-Null; Ok 'Stock firmware restored! Rebooting...' }
  else     { Warn 'Some partitions failed. Device may be in fastboot mode.' }
}

# ---- MAIN ------------------------------------------------------------------
function DownloadOnly {
  Step 'Download firmware files'
  New-Item -ItemType Directory -Path $WORK_DIR -Force | Out-Null
  $latestBuild = GetBuilds
  $unofficial = $false
  if (-not $latestBuild) {
    if (Confirm 'Download unofficial GMS build from SourceForge instead?') { $unofficial = $true }
  }
  if ($unofficial) {
    $files = @('boot.img','dtbo.img','vbmeta.img','vendor_boot.img','lineage-23.2-20260519-UNOFFICIAL-GMS-Q25.zip')
    foreach ($f in $files) {
      $dest = Join-Path $WORK_DIR $f
      if (Test-Path $dest) { Info "$f already downloaded"; continue }
      $url = "$SF_BASE/$f/download"
      Info "Go download from SourceForge $SF_BASE"
      Info "and place in $WORK_DIR"
      Pause
    }
  } elseif ($latestBuild) {
    Info "Found $($latestBuild.files.Count) files in build $($latestBuild.version)"
    foreach ($f in $latestBuild.files) {
      $dest = Join-Path $WORK_DIR $f.filename
      $sizeStr = if ($f.size -gt 100MB) { "{0:N1} GB" -f ($f.size / 1GB) } else { "{0:N0} KB" -f ($f.size / 1KB) }
      if (Test-Path $dest) {
        $local = (Get-FileHash $dest -Algorithm SHA256).Hash.ToLower()
        if ($local -eq $f.sha256) { Ok "$($f.filename)  $sizeStr -- SHA256 OK" }
        else { Warn "$($f.filename) -- SHA256 MISMATCH (expected $($f.sha256), got $local)" }
        continue
      }
      if (DownloadFile -Url $f.url -Dest $dest -Name $f.filename) {
        $local = (Get-FileHash $dest -Algorithm SHA256).Hash.ToLower()
        if ($local -eq $f.sha256) { Ok "$($f.filename)  $sizeStr -- SHA256 OK" }
        else { Warn "$($f.filename) -- SHA256 MISMATCH (expected $($f.sha256), got $local)" }
      } else {
        GetFile $f.filename | Out-Null
      }
    }
  } else {
    foreach ($f in @('boot.img','dtbo.img','vbmeta.img','vendor_boot.img','lineage-*.zip')) { GetFile $f | Out-Null }
  }
  Ok 'All firmware files downloaded'
}

function Main {
  Banner
  CheckAdmin
  InstallTools
  InstallFastbootDriver
  CheckImei
  if (Confirm 'Run IMEI remediation?') { RemediateImei }

  $bootloaderUnlocked = CheckBootloader

  if ($bootloaderUnlocked -eq $false) {
    if (Confirm 'Bootloader is locked. Unlock it now?') { UnlockBootloader }
  } elseif ($bootloaderUnlocked) {
    Info 'Bootloader already unlocked'
  }

  New-Item -ItemType Directory -Path $WORK_DIR -Force | Out-Null

  $latestBuild = GetBuilds

  $unofficial = $false
  if (-not $latestBuild) {
    if (Confirm 'Download unofficial GMS build from SourceForge instead?') { $unofficial = $true }
  }

  Step 'Collecting firmware files'
  Info "Files stored in $WORK_DIR"

  if ($unofficial) {
    $files = @('boot.img','dtbo.img','vbmeta.img','vendor_boot.img','lineage-23.2-20260519-UNOFFICIAL-GMS-Q25.zip')
    $romZip = $null
    foreach ($f in $files) {
      $dest = Join-Path $WORK_DIR $f
      if (Test-Path $dest) {
        Info "$f already downloaded"
      } else {
        $url = "$SF_BASE/$f/download"
        Info "Go download from SourceForge $SF_BASE"
        Info "and place in $WORK_DIR"
        Info 'Then press enter'
        Pause
      }
      if ($f -like '*.zip') { $romZip = $dest }
      if ($SF_HASHES.ContainsKey($f)) {
        $hash = (Get-FileHash $dest -Algorithm SHA256).Hash.ToLower()
        if ($hash -eq $SF_HASHES[$f]) { Ok "SHA256 matches" } else { Warn "SHA256 MISMATCH - expected $($SF_HASHES[$f]), got $hash" }
      }
    }
    $bootImg    = Join-Path $WORK_DIR 'boot.img'
    $dtboImg    = Join-Path $WORK_DIR 'dtbo.img'
    $vbmetaImg  = Join-Path $WORK_DIR 'vbmeta.img'
    $vendorBoot = Join-Path $WORK_DIR 'vendor_boot.img'
  } elseif ($latestBuild) {
    $files = $latestBuild.files

    foreach ($f in $files) {
      $dest = Join-Path $WORK_DIR $f.filename
      $sizeStr = if ($f.size -gt 100MB) { "{0:N1} GB" -f ($f.size / 1GB) } else { "{0:N0} KB" -f ($f.size / 1KB) }
      if (Test-Path $dest) {
        $local = (Get-FileHash $dest -Algorithm SHA256).Hash.ToLower()
        if ($local -eq $f.sha256) { Ok "$($f.filename)  $sizeStr -- SHA256 OK" }
        else { Warn "$($f.filename) -- SHA256 MISMATCH (expected $($f.sha256), got $local)" }
        continue
      }
      if (DownloadFile -Url $f.url -Dest $dest -Name $f.filename) {
        $local = (Get-FileHash $dest -Algorithm SHA256).Hash.ToLower()
        if ($local -eq $f.sha256) { Ok "$($f.filename)  $sizeStr -- SHA256 OK" }
        else { Warn "$($f.filename) -- SHA256 MISMATCH (expected $($f.sha256), got $local)" }
      } else {
        Warn "Failed to download $($f.filename); provide it manually."
        GetFile $f.filename | Out-Null
      }
    }
    $bootImg    = Join-Path $WORK_DIR 'boot.img'
    $dtboImg    = Join-Path $WORK_DIR 'dtbo.img'
    $vbmetaImg  = Join-Path $WORK_DIR 'vbmeta.img'
    $vendorBoot = Join-Path $WORK_DIR 'vendor_boot.img'
    $romZip     = Join-Path $WORK_DIR $latestBuild.files[0].filename
  } else {
    $bootImg    = GetFile 'boot.img'
    $dtboImg    = GetFile 'dtbo.img'
    $vbmetaImg  = GetFile 'vbmeta.img'
    $vendorBoot = GetFile 'vendor_boot.img'
    $romZip     = GetFile 'lineage-*.zip'
  }

  if ($unofficial) {
    Info 'GMS is already included in the unofficial build - skipping separate GApps download'
    $gappsZip = $null
  } else {
    $gappsZip = GetGApps
  }

  if ($bootImg -or $dtboImg -or $vbmetaImg) {
    if (Confirm 'Flash boot/dtbo/vbmeta?') { FlashParts -Boot $bootImg -Dtbo $dtboImg -Vbmeta $vbmetaImg }
  }

  if ($vendorBoot -and $romZip) {
    if (Confirm 'Flash recovery and install LineageOS?') {
      if (FlashRecovery -VendorBoot $vendorBoot) { Sideload -Rom $romZip -GApps $gappsZip }
    }
  }

  if (Confirm 'Run post-install (APKs + wallpapers)?') { PostInstall }

  # if (Confirm 'Flash back to stock firmware?') { FlashStock }

  # Banner
  Write-Host ""
  ShowWatermelon
  Write-Host "            All done! Enjoy LineageOS on your $OEM $DEVICE." -ForegroundColor Green
  Write-Host ""
  
}

# quick-run: .\install-lineageos-q25.ps1 -postinstall  (or -imei, -remediate, -bootloader, -unlock)
$quickCmd = $args | ForEach-Object { $_.TrimStart('-') } | Where-Object { $_ -in @('imei','remediate','bootloader','unlock','relock','postinstall','stock','download','check','w','b','ic','pi','if','u','rl','c', 'd') } | Select-Object -First 1
if ($quickCmd) {
  switch ($quickCmd) {
    'imei'        { CheckImei }
    'remediate'   { RemediateImei }
    'bootloader'  { CheckBootloader | Out-Null }
    'unlock'      { UnlockBootloader }
    'relock'      { RelockBootloader }
    'postinstall' { PostInstall }
    'stock'       { FlashStock }
    'download'    { DownloadOnly }
    'check'       { CheckForUpdates }
    'd'           { DownloadOnly }
    'ic'          { CheckImei }
    'if'          { RemediateImei }
    'b'           { CheckBootloader | Out-Null }
    'u'           { UnlockBootloader }
    'rl'          { RelockBootloader }
    'pi'          { PostInstall }
    'w'           { ShowWatermelon }
    'c'           { CheckForUpdates }
  }
  exit
}

Main
