# VirusTotal and this project

A scan of the files of this project on VirusTotal shows a number of engines
flagging them. That is expected for this kind of tool. This page explains how to
read those reports and how to confirm that the file you scanned is the official
one.

## Short version

- The unlocker removes a license restriction. Engines classify any tool in that
  category as `hacktool`/`crack`, so a share of them always flags it. The label
  describes the category, not something the file does.
- Most of the detections are generic heuristics and machine-learning labels
  (`Evo-gen`, `Heur.BZC.ONG.Boxter`, `Detected`, score entries). Several engines
  return the very same detection string, which is a shared signature set rather
  than independent discoveries. No real malware family is named.
- The report does not show data theft, a keylogger, persistence (no service, no
  scheduled task, no autostart entry) or a command-and-control server.
- The value you should trust is the SHA-256, published in `SHA256SUMS.txt` and
  on the release page. VirusTotal is a second opinion, not the source of truth.

## What the report fields mean

- **Popular threat label** (`trojan.boxter/crack`): the most common labels the
  engines returned, combined into one line. It is built from the labels, not
  from an analysis of the file.
- **Threat categories** (`trojan`, `hacktool`, `pua`): the category the engines
  put the file in. A license unlocker lands in `hacktool`/`crack` by definition.
- **Family labels** (`boxter`, `crack`, `crackagen`): the family strings used by
  the engines that flagged it. Here they are the heuristic and category names,
  not a family found in the file.

## Detections that repeat are one detection

When many engines show the same text, read the text and not the count. In a
typical report for this project:

- The same string (`Win64:Evo-gen`, `Heur.BZC.ONG.Boxter`, `TR/W64.Evo`,
  `Unwanted-Program`, `Trojan.Win32.crack`) appears under several engine names.
  Those engines share a signature or a heuristic, so the count is not a count of
  independent confirmations.
- The rest are generic names and score entries (`Malicious`, `Detected`,
  `Malicious (high Confidence)`, `susgen`). Those entries say "this looks like
  the category", not "this file does this".

That is also why the total moves between runs and between releases without
anything in the file changing: definitions and machine-learning models change
over time. A clean scan today does not guarantee a clean scan tomorrow, and the
opposite is true as well.

## Which file to scan

The report is for a `.zip`, and the file name matters:

- **`Minecraft-Bedrock-Free-main.zip`** is the source archive GitHub builds from
  the `main` branch. It is generated from the branch, it is not a release asset,
  and its hash is not published. Scanning it is fine, but do not expect it to
  match `SHA256SUMS.txt`.
- **`release/winmm.dll`** is the file the project pins. Its SHA-256 lives in
  [`SHA256SUMS.txt`](../SHA256SUMS.txt) and on the release page, and it is the
  same file every installed copy gets. If you want a result you can compare with
  the published one, scan this file.

## How to confirm the file is the official one

1. Download only from the two official entries: the `install.bat` on the
   [release page](https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases/latest),
   or `irm https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/raw/main/i.ps1 | iex`.
2. Compare the SHA-256 of the downloaded `winmm.dll` with the published value:

   ```powershell
   Get-FileHash .\winmm.dll -Algorithm SHA256
   ```

   The installer runs this check by itself, before and after copying the file,
   and refuses to continue when the value does not match.
3. If a scan still bothers you, run the installer in a disposable VM, or watch
   what the file touches with Sysinternals Process Monitor. Since the binary is
   closed source, observing it is the honest way to settle the remaining doubt.

See [Antivirus false positives](antivirus-false-positives.md) for the general
explanation and for what to do when an antivirus quarantines the file.

## If you are not comfortable

That is a valid position. The tool bypasses a license and part of it is closed
source, so "I cannot verify this, so I will not run it" is a reasonable choice.
The only fully safe option is not running the tool.

## Reporting a detection

If a scan shows something beyond the category labels, for example a named
malware family, data theft or a network address, open an issue with the
VirusTotal link and the SHA-256 of the file. See [SECURITY.md](../SECURITY.md).
