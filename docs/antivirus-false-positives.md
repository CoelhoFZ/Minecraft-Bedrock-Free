# Antivirus false positives

The unlock binary (`winmm.dll`) is occasionally flagged by antivirus engines.
This page explains why that happens, how to verify that the files you have are
the genuine ones, and what to do if an antivirus quarantines the file.

## Short version

- The unlocker is **not malware**. The installer is open source (GPLv3) and
  the full project is public: <https://github.com/CoelhoFZ/Minecraft-Bedrock-Free>.
- The unlocker bypasses a license, and antivirus vendors classify any tool in
  that category as `hacktool`/`crack`, regardless of what the file actually
  does.
- A minority of engines report it (mostly labelled `hacktool/crack`).
  **Microsoft Defender has also flagged it on some machines** (e.g. the
  generic `Wacatac`/`Sabsik`/`Commando` ML labels). Its definitions change
  over time, so a clean scan today does not guarantee a clean scan tomorrow.

## Why antivirus engines flag it

- **It bypasses a license.** Tools that bypass licensing are classified by
  definition as "hacktool" or "crack" by some vendors. A few of them (e.g.
  ESET) keep that label even after manual review.
- **The binary is closed source.** Engines that cannot inspect a file end up
  scoring it with heuristics instead of a signature, so a clean scan on one
  machine and a detection on another is normal for this category of tool.
- **Machine-learning labels.** Vendors that ship ML models report generic
  labels that change with every definition update, such as the Microsoft
  Defender `Wacatac`/`Sabsik`/`Commando` detections.

## What this means for you

- The detections are **heuristic labels**, not evidence of malicious behavior.
- The installer is open source, so anyone can audit exactly what it does. Only
  the unlock binary itself is closed.
- You can verify authenticity yourself: the official SHA-256 checksums are
  published on the [release page](https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases/latest)
  and in `SHA256SUMS.txt` in the repository.

Verify a downloaded file with PowerShell:

```powershell
Get-FileHash <file> -Algorithm SHA256
```

- Only download from the official repository. Scammers spread fake "fix"
  links in Discord chats that run `irm <short-link> | iex`. That is never
  this project.

## Why the binary is closed source

The unlock binary is closed source to prevent code theft. If the source were
published, anyone could copy it, rebrand it, and spread modified copies,
including the fake "fix" installers that already circulate in Discord chats.

We are not going to pretend that costs nothing. Closed source means you are
being asked to run a file you cannot read, and no explanation on this page
can remove that from the equation. What we can do is be precise about what
this tool is, what you can verify without the source, and where the real
trust decision lives.

### What this tool actually is

It is an unlocker: it removes the trial restriction so the game runs as the
full version. It does not steal data, spy, or damage your system. That is
what "malware" means, and this is not that.

Antivirus vendors classify any tool that bypasses a license as
`hacktool`/`crack` by definition, and a few keep that label even after manual
review. So expect the label. It describes the category of the tool, not
malicious behavior.

If you are not comfortable running a license unlocker at all, that is a fair
position, so do not run it.

### What you can verify without the source

The source of the binary is closed, but everything around it is open and
auditable:

- **The installer is fully open source (GPLv3).** Read it and see exactly
  what it does: where the binary is downloaded from (this repository's
  official release page, over HTTPS), how the SHA-256 is verified before and
  after installation, and which files and folders it touches (the Minecraft
  install folder and a local cache).
- **Authenticity is pinned.** Each release publishes the official SHA-256 of
  the exact file in `SHA256SUMS.txt` and on the release page. Compare it with
  `Get-FileHash` before running anything.
- **The supply chain is short and public.** Every file you run comes from one
  public GitHub repository, downloaded over HTTPS from that repository, not
  from a random short link. That narrows the trust question to one concrete
  point: *do you trust the owner of this repository?* There is no hidden
  middleman.
- **Behavior can be watched.** Since the binary itself is closed, the honest
  way to satisfy residual doubt is to observe it: run the installer in a
  disposable VM, or with Sysinternals Process Monitor open, and see what it
  touches. Uploading the file to VirusTotal is also useful, but expect
  `hacktool`/`crack` labels from some engines (that is the category, see
  above) and look for whether anything beyond that shows up.

### If you still do not trust it

That is a valid outcome. "I cannot verify this, so I will not run it" is a
reasonable decision, and the only fully safe option is not running the tool.
Distrusting a closed binary is not "useless". It is a legitimate position.
The mistake would be to jump from "closed source" straight to "it is
malware": that conclusion has exactly as much evidence behind it as "the
README says it is safe, so it is". Neither is proof. The difference is that
the steps above let you gather real evidence if you want it.

If you still believe this unlocker has a virus after reading this page, do
not use it. BUY MINECRAFT YOURSELF!

## If your antivirus quarantines or blocks the file

When an antivirus quarantines `winmm.dll` after the installer finishes, the
game can fail to start with a **"Bad Image" error (status `0xc0e90007`)**.
The DLL it needs is no longer a valid file. To fix it:

1. Add an exclusion for the Minecraft folder in your antivirus:
   - **Windows Defender:** Settings → Privacy & security → Windows Security →
     Virus & threat protection → Manage settings → Exclusions → Add an
     exclusion → Folder → select `C:\XboxGames\Minecraft for Windows\Content`
     (Xbox App) or the `Microsoft.MinecraftUWP_*` folder inside
     `C:\Program Files\WindowsApps` (Microsoft Store).
   - Other AVs: add the same folder to their exclusion/whitelist.
2. Run the installer again. It writes a verified copy and checks the hash
   again after copying.

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for these and other problems.
