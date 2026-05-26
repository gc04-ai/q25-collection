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
iwr "https://raw.githubusercontent.com/gc04-ai/q25-collection/refs/heads/main/install-lineageos-q25.ps1" -o "install-lineageos-q25.ps1"
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

## See help text for more usage
```
.\install-lineageos-q25.ps1 -help
```
