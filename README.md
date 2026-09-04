# Minecraft Bedrock Free

<p align="center">
  <img src="docs/logo.png" alt="Minecraft Bedrock Free logo" width="128">
  <br>
  <a href="https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases"><img alt="GitHub release" src="https://img.shields.io/github/v/release/CoelhoFZ/Minecraft-Bedrock-Free?style=for-the-badge"></a>
  <img alt="Downloads" src="https://mbu-download-counter.xgobg2020.workers.dev/?v=2">
  <img alt="License" src="https://img.shields.io/badge/license-GPLv3%20(scripts)-blue?style=for-the-badge">
  <a href="https://buymeacoffee.com/coelhofz"><img alt="Buy Me a Coffee" src="https://img.shields.io/badge/Support-Buy%20Me%20a%20Coffee-FFDD00?style=for-the-badge"></a>
  <a href="https://discord.gg/u3S4gFgK6M"><img alt="Discord" src="https://img.shields.io/badge/Discord-Join%20community-5865F2?style=for-the-badge&logo=discord&logoColor=white"></a>
</p>

Unlock the full version of **Minecraft Bedrock Edition (GDK)** on Windows 10/11.

**Works with Xbox App (GDK) and Microsoft Store installations** on Windows 10/11.

> ⚠️ Educational project. Please support the developers by purchasing the game.

## Requirements

- **Official build only.** Works exclusively with the official **Microsoft
  Store** or **Xbox App** build of Minecraft Bedrock for Windows. It will NOT
  work with third-party launchers or version switchers (they don't use the GDK
  license API the unlock hooks).
- **Current version only.** Built and tested against the latest version.
  Microsoft does not let you install older versions, and this project does not
  provide one.
> **Windows on ARM (beta):** on Snapdragon PCs the installer now picks the native
> ARM64 build automatically (`release/winmm-arm64.dll`). Requirements: the ARM64
> Store/Xbox package of Minecraft. Report issues with the `[ARM64]` prefix.

- Do **not** copy `winmm.dll` into another launcher/folder. It only unlocks
  the official build and can break other launchers.

## Install

1. Install Minecraft from the **Xbox App** or the **Microsoft Store** and run it once.
2. Open **PowerShell** and run:

```powershell
irm https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/raw/main/i.ps1 | iex
```

The file is **`i.ps1`** (the letter **i**, as in "install"), not
`e.ps1`. A typo like `.../raw/main/e.ps1 | iex` fails with a connection
error ("the request was aborted: the connection was closed unexpectedly")
because that file does not exist.

3. The installer opens Minecraft automatically. The "Unlock full game" button is gone.

> The installer scripts are **open source** (GPLv3). Only the unlock binary
> (`release/winmm.dll`) is closed source - see [LICENSE](LICENSE).

The installer locates the game's `Content` folder, closes the game if it is
running, backs up any original `winmm.dll` (as `winmm.dll.orig`) and installs
the unlock. Old artifacts from previous versions are removed.

To remove the unlock later, run the installer again and choose **Remove
unlock**. For a manual removal (without the menu), run `.\uninstall.ps1`.

## Self-contained, no third-party downloads

Nothing is downloaded from third parties at install time or at runtime. The
unlock is a **closed-source binary** shipped in this repository:

- `release/winmm.dll` - the only file the game needs (a fake `winmm.dll` that
  is picked up by the app's DLL search order).

## How it works (high level)

Minecraft's GDK build asks a Windows API (`xgameruntime!QueryApiImpl`) whether
the license entitlements are owned. The shipped `winmm.dll` intercepts those
queries and reports "owned", so the game runs as if fully purchased. Everything
else (account, gamertag, profile) stays real.

## Closed source

The binaries are **closed source** - the unlock mechanism is not published
here. They are hardened against reverse engineering:

- The actual unlock payload does not exist as a file: it is an **encrypted
  blob embedded inside `winmm.dll`**, mapped manually at runtime by a custom
  loader (two encrypted stages, per-build keys).
- No revealing strings, no import table of the packer path, no symbols/RTTI.
- Anti-debug (multiple layers), anti-tamper (integrity checks at load and a
  watchdog at runtime), anti-dump.

See `LICENSE` for the terms.

## Binary integrity

`SHA256SUMS.txt` lists the expected hash of `release/winmm.dll`. Verify before
installing:

```powershell
Get-FileHash .\release\winmm.dll -Algorithm SHA256
```

## Antivirus

Some antivirus engines flag the unlock binary as a false positive. This is
expected for an unlocker — see [Antivirus false positives](docs/antivirus-false-positives.md).

## Environment variables (advanced)

| Variable | Used by | What it does |
|---|---|---|
| `MBU_LANG` | `menu.ps1` | Forces the menu language (`pt`, `en`, `es`, `fr`, `zh`, `hi`, `ar`, `ru`) instead of auto-detecting from the system. |
| `MBU_BASE_URL` | `i.ps1`, `install.bat`, `menu.ps1` | Points the installer at a different server (forks, local test VM). Integrity hash checks still apply. |
| `MBU_EXTRA_HASH` | `install.bat` | Together with `MBU_BASE_URL`: lets a locally-modified `menu.ps1` (different hash) pass the integrity check in test environments. Never set these on a daily-use machine. |
| `MBU_NO_LOOP` | `menu.ps1` | Set to `1` to load the menu functions without entering the interactive loop (dot-sourcing for tests). |

## Game version compatibility

The menu downloads `tested-versions.json` from this repository and warns when
your Minecraft version has **not been tested** with this unlocker yet.

Option **[3] Diagnostics** in the menu prints (and copies to the clipboard) the
OS version, game folder, install source (Store/Xbox App), game version and
architecture, installed unlock build, Defender exclusions related to
Minecraft/mbu and the offline-reinstall cache status - ready to paste in the
[Discord support channel](https://discord.gg/u3S4gFgK6M).

## Troubleshooting

Problems installing or launching the game? See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Support

Enjoying the unlocker? Consider [buying me a coffee](https://buymeacoffee.com/coelhofz) ☕ -
it helps keep the project going.

## 🚨 SCAM ALERT

Scammers spread **fake "unlocker fix"** links in Discord chats using short
URLs and the pattern `irm <short-link> | iex`. **That is NOT this project** -
it downloads a remote access trojan.

- The **ONLY official source** is this repository:
  `https://github.com/CoelhoFZ/Minecraft-Bedrock-Free`
- **NEVER** run `irm <anything> | iex` from a short link (bit.ly, tinyurl, …),
  another domain, a Discord DM or a random server.
- The official installer only ever copies the files in this repository.
