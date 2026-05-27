# LineageOS Q25 Installer

Automated PowerShell script to install LineageOS 23.2 on the Zinwa Q25 Pro, including optional Google Apps, custom APKs, and wallpapers.

## Prerequisites

- Windows 10/11 (PowerShell 5.1+)
- Zinwa Q25 Pro device
- USB cable
- Stock Android running (with USB debugging enabled)

## Quick Start

### Open Powershell as Admin
```
1. Press Windows key
2. Type powershell
3. Click Run as Administrator
```
### Change to your home directory
```
cd ~
```
### Download the script
```
iwr "https://raw.githubusercontent.com/gc04-ai/q25-lineage-installer/refs/heads/main/install-lineageos-q25.ps1" -o "install-lineageos-q25.ps1"
```
### Run the script
```
powershell -ExecutionPolicy Bypass -File install-lineageos-q25.ps1
```

## What It Does

1. **Pre-checks** -- verifies admin rights, checks for ADB/fastboot (auto-installs if missing via Google platform-tools)
2. **Bootloader unlock** -- guides through enabling OEM unlock and running `fastboot flashing unlock`
3. **Download files** -- queries LineageOS API for Q25 builds; if none found (currently the case), prompts for URLs or local file paths for each image
4. **Google Apps** -- optionally downloads MindTheGapps arm64 for Android 16
5. **Flash partitions** -- flashes boot.img, dtbo.img, vbmeta.img, then vendor_boot.img (Lineage Recovery)
6. **Sideload ROM** -- factory resets in recovery, sideloads LineageOS zip + optional GApps
7. **Post-install** -- after first boot, installs APKs and pushes wallpapers via ADB

## Required Files

| File | Source |
|---|---|
| `boot.img` | LineageOS downloads |
| `dtbo.img` | LineageOS downloads |
| `vbmeta.img` | LineageOS downloads |
| `vendor_boot.img` | LineageOS downloads (recovery) |
| `lineage-*.zip` | LineageOS downloads (ROM) |
| `MindTheGapps-*.zip` | GitHub (auto-downloaded if opted in) |

When the LineageOS API has no builds for Q25, the script will ask you to provide each file via URL or local path.

## Optional: APKs & Wallpapers

Create these folders next to the script:

```
install-lineageos-q25.ps1
apks/
  MyApp.apk
  AnotherApp.apk
wallpapers/
  wallpaper1.jpg
  wallpaper2.png
```

After first boot, the script installs all `.apk` files and pushes images to `/sdcard/Pictures/Wallpapers/` on the device.

## Notes

- First boot takes up to 15 minutes
- GApps signature verification failure is normal -- select "Yes" to continue
- All downloaded files are cached in `%USERPROFILE%\lineageos-install` for reuse
- The post-install step (APKs/wallpapers) can be re-run later by calling `PostInstall` manually after ADB is connected


## Quick-Run Flags (Standalone Execution)

By default, running the script without any arguments launches the full, interactive guided installer. However, if you only need to perform a specific task, you can use the quick-run flags below to bypass the main menu.

**`-bootloader` | `-b**`

* **What it does:** Reboots the device to `fastboot` and queries the current unlock status, slot count, and secure boot state.
* **When to use it:** When you are troubleshooting a failed flash or simply want to verify that your device successfully unlocked before proceeding with the rest of the installation.

**`-imei` | `-ic**`

* **What it does:** Connects via ADB to read the device's current TAC (Type Allocation Code) and checks it against a list of known factory-default or spoofed blocks (like the Zinwa factory default).
* **When to use it:** Run this before installing LineageOS to ensure your device has a valid, unique IMEI, which is critical for cellular network registration.

**`-remediate` | `-if**`

* **What it does:** Automatically launches the hidden Engineering/IMEI settings app on the device via ADB so you can input a valid IMEI.
* **When to use it:** Use this *only* if the `-imei` check flags your device as having a spoofed or generic factory IMEI, and you need to legally restore the device's original IMEI from its retail box.

**`-unlock` | `-u**`

* **What it does:** Reboots to the bootloader and initiates the `fastboot flashing unlock` command.
* **When to use it:** When starting with a fresh, stock device. *Note: This will trigger a factory reset and wipe all user data.*

**`-download` | `-d**`

* **What it does:** Queries the LineageOS API (or the SourceForge fallback) and downloads all necessary image files (`boot.img`, `dtbo.img`, `vbmeta.img`, `vendor_boot.img`) and the ROM `.zip` into your working directory.
* **When to use it:** When you want to pre-stage all your files on a fast network before touching the device, or if you just want to archive the latest build for offline use.

**`-check` | `-c**`

* **What it does:** Pings the LineageOS API and returns the version string and date of the latest available build without actually downloading any files.
* **When to use it:** When you want a quick status check to see if a new update has dropped before deciding whether to run the installer.

**`-postinstall` | `-pi**`

* **What it does:** Connects to a booted Android environment via ADB, installs any `.apk` files staged in the `\apks` folder, and pushes image files from the `\wallpapers` folder directly to the device's local storage.
* **When to use it:** Use this after a fresh install or an OTA update to quickly restore your favorite standard apps and customizations without flashing anything.

**`-stock`**

* **What it does:** Parses the MediaTek scatter file and flashes the heavy factory `.img` files (including the ~5.5GB `super.img`) via `fastboot` to completely overwrite LineageOS.
* **When to use it:** When you need to unbrick the device, start over from scratch, or prepare the device for resale by returning it to its factory Zinwa software state.

**`-relock` | `-rl**`

* **What it does:** Reboots to the bootloader and executes `fastboot flashing lock` to re-enable secure boot.
* **When to use it:** **ONLY** use this immediately after running the `-stock` flag. Relocking the bootloader while a custom ROM like LineageOS is installed will hard-brick your device. Use this when you are completely reverting to factory conditions.
