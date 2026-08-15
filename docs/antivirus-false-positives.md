# Antivirus false positives

The unlock binary (`winmm.dll`) is occasionally flagged by antivirus engines.
This page explains why that happens and how to verify that the files you have
are the genuine ones.

## Short version

- The unlocker is **not malware**. The installer is open source (GPLv3) and
  the full project is public: <https://github.com/CoelhoFZ/Minecraft-Bedrock-Free>.
- The binary is a **proxy DLL** that hooks the game's licensing check, and it
  is **packed/protected against analysis** — exactly the traits heuristic
  engines flag as suspicious.
- A small minority of engines report it (e.g. 7 of 67 on VirusTotal, mostly
  labelled `hacktool/crack`). The large majority — including Microsoft
  Defender — do not.

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
- **Microsoft Defender does not flag the file.**
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
