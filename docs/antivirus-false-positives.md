# Antivirus false positives

The unlock binary (`winmm.dll`) is occasionally flagged by antivirus engines.
This page explains why that happens, how to verify that the files you have are
the genuine ones, and what to do if an antivirus quarantines the file.

## Short version

- The unlocker is **not malware**. The installer is open source (GPLv3) and
  the full project is public: <https://github.com/CoelhoFZ/Minecraft-Bedrock-Free>.
- The binary is a **proxy DLL** that hooks the game's licensing check, and it
  is **packed/protected against analysis** — exactly the traits heuristic
  engines flag as suspicious.
- A minority of engines report it (mostly labelled `hacktool/crack`).
  **Microsoft Defender has also flagged it on some machines** (e.g. the
  generic `Wacatac`/`Sabsik`/`Commando` ML labels) — its definitions change
  over time, so a clean scan today does not guarantee a clean scan tomorrow.

## Why antivirus engines flag it

- **Proxy DLL / DLL sideloading.** The game loads `winmm.dll` through the
  standard Windows DLL search order. "Proxy DLL" is a classic malware
  technique, so it alone triggers heuristics.
- **Packed/protected binary.** The unlock mechanism is embedded as encrypted
  blobs and hardened against reverse engineering (anti-debug, anti-dump,
  integrity checks). Static analysis of protected binaries trips heuristic
  detections such as `detect-debug-environment` or `long-sleeps`.
- **It bypasses a license.** Tools that bypass licensing are classified by
  definition as "hacktool" or "crack" by some vendors. A few of them (e.g.
  ESET) keep that label even after manual review.

## What this means for you

- The detections are **heuristic labels**, not evidence of malicious behavior.
- The installer is open source, so anyone can audit exactly what it does; only
  the packed unlock binary is closed.
- You can verify authenticity yourself: the official SHA-256 checksums are
  published on the [release page](https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases/latest)
  and in `SHA256SUMS.txt` in the repository.

Verify a downloaded file with PowerShell:

```powershell
Get-FileHash <file> -Algorithm SHA256
```

- Only download from the official repository. Scammers spread fake "fix"
  links in Discord chats that run `irm <short-link> | iex` — that is never
  this project.

## If your antivirus quarantines or blocks the file

When an antivirus quarantines `winmm.dll` after the installer finishes, the
game can fail to start with a **"Bad Image" error (status `0xc0e90007`)** —
the DLL it needs is no longer a valid file. To fix it:

1. Add an exclusion for the Minecraft folder in your antivirus:
   - **Windows Defender:** Settings → Privacy & security → Windows Security →
     Virus & threat protection → Manage settings → Exclusions → Add an
     exclusion → Folder → select `C:\XboxGames\Minecraft for Windows\Content`
     (Xbox App) or the `Microsoft.MinecraftUWP_*` folder inside
     `C:\Program Files\WindowsApps` (Microsoft Store).
   - Other AVs: add the same folder to their exclusion/whitelist.
2. Run the installer again — it writes a verified copy and checks the hash
   again after copying.

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for these and other problems.
