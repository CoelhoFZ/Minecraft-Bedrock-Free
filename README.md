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

**Works with the Xbox App (GDK) installation** on Windows 10/11. The Microsoft
Store installation is **not** supported - see
[The Microsoft Store version is not supported](#the-microsoft-store-version-is-not-supported).

> ⚠️ Educational project. Please support the developers by purchasing the game.

## Requirements

- **Official Xbox App build only.** Works exclusively with the official
  **Xbox App** (GDK) build of Minecraft Bedrock for Windows. The copy installed
  by the **Microsoft Store** is not supported: the installer detects it, explains
  it and stops instead of installing. It will NOT work with third-party
  launchers or version switchers either.
- **Build 1.21 or newer.** Works with any Minecraft for Windows build from 1.21
  on, including a build newer than this release. Older builds are refused.
  Microsoft does not let you install older versions, and this project does not
  provide one.
> **Windows on ARM:** this release ships the x64 build only. The native ARM64
> build is being rebuilt and will return in a future release. Report issues
> with the `[ARM64]` prefix if you are on ARM.

- Do **not** copy `winmm.dll` into another launcher/folder. It only unlocks
  the official build and can break other launchers. Leave the file only where
  the installer puts it: any other program that starts from the same folder as
  the file picks it up when it starts, which can stop that program from working
  (32-bit programs there may not open at all) and online games with anticheat
  can flag the session. This includes a copy you downloaded by hand and left in
  Downloads, on the Desktop or next to another game: delete that extra copy and
  run the installer again.

## The Microsoft Store version is not supported

Minecraft whose game files live inside `C:\Program Files\WindowsApps` was
installed by the **Microsoft Store** into the folder Windows keeps protected, and
the unlock is not compatible with that copy. The installer follows the links the
Store uses to find where the files really are, notices it, says so and stops
**before** downloading anything, so nothing is changed on your PC. An
installation whose files really live in `C:\XboxGames` (where the Xbox app puts
them, and where many Store installs end up through a link) is **not** blocked.

To use this project, uninstall that copy and install the game from the Xbox app:

1. Back up your worlds first. They live in
   `%LOCALAPPDATA%\Packages\Microsoft.MinecraftUWP_8wekyb3d8bbwe\LocalState\games\com.mojang\minecraftWorlds`.
2. Uninstall the current copy: **Settings > Apps > Installed apps > Minecraft
   for Windows > Uninstall**.
3. Install Minecraft again from the **Xbox app**. That copy lives in
   `C:\XboxGames` and is the one this project supports.
4. Run the installer again.

Step by step, with what each one does:
[TROUBLESHOOTING.md](TROUBLESHOOTING.md#the-microsoft-store-version-is-not-supported-v4942).

## Install

1. Install Minecraft from the **Xbox App** (not from the Microsoft Store) and run
   it once. The trial version is enough, the installer unlocks it. If the Store
   page offers only "Buy", read
   [The Store page only offers "Buy" and I need the trial](TROUBLESHOOTING.md#the-store-page-only-offers-buy-and-i-need-the-trial)
   before going on.
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
the unlock. The `winmm.dll` that is already there is kept aside during the swap
and put back if anything goes wrong, so a failed install never leaves the game
without a working file. Old artifacts from previous versions are removed.

To remove the unlock later, run the installer again and choose **Remove
unlock**. For a manual removal (without the menu), download `uninstall.ps1`
(<https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/raw/main/uninstall.ps1>)
and run it in an elevated PowerShell.

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
here. See `LICENSE` for the terms.

## Binary integrity

`SHA256SUMS.txt` lists the expected hash of `release/winmm.dll`. Verify before
installing:

```powershell
Get-FileHash .\release\winmm.dll -Algorithm SHA256
```

## Antivirus

Some antivirus engines flag the unlock binary as a false positive. This is
expected for an unlocker. See [Antivirus false positives](docs/antivirus-false-positives.md).

## Environment variables (advanced)

| Variable | Used by | What it does |
|---|---|---|
| `MBU_LANG` | `menu.ps1` | Forces the menu language (`pt`, `en`, `es`, `fr`, `zh`, `hi`, `ar`, `ru`) instead of auto-detecting from the system. |
| `MBU_BASE_URL` | `i.ps1`, `install.bat`, `menu.ps1` | Points the installer at a different server (forks, local test VM). Integrity hash checks still apply. |
| `MBU_REPORT_URL` | `menu.ps1` | Overrides the failure-report endpoint (Cloudflare Worker), for pointing tests at a local mock. Never set on a daily-use machine. |
| `MBU_NO_LOOP` | `menu.ps1` | Set to `1` to load the menu functions without entering the interactive loop (dot-sourcing for tests). |

## Game version compatibility

The unlock works by hooking the GDK license APIs (`XStore*`), so it is not tied
to one game build: **any Minecraft for Windows build from 1.21 on is
accepted**, including a build **newer** than the one this release was verified
against. The menu downloads `tested-versions.json` from this repository to read
the minimum supported version; if your game is **older** than that floor,the installer stops before downloading anything and asks you to update Minecraft
from the Xbox app.
The `tested` list in that file is only a record of the builds verified by hand:
being newer than it does not block or change anything.

When something fails - an installer error, Minecraft not opening after
install, or the game crashing right after launch - the menu asks whether to
send a diagnostic report to the developer. Confirm with **Y** and the report
is delivered automatically: no copying, no pasting. The report is never shown
on screen and never leaves your machine without your confirmation.

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
