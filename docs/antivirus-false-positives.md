# Antivirus false positives

The unlock binary (`winmm.dll`) is occasionally flagged by antivirus engines.
This page explains why that happens, how to verify that the files you have are
the genuine ones, and what to do if an antivirus quarantines the file.

## Short version

- The unlocker is **not malware**. The installer and the unlock source are
  open source (GPLv3) and the full project is public:
  <https://github.com/CoelhoFZ/Minecraft-Bedrock-Free>.
- The unlocker bypasses a license, and antivirus vendors classify any tool in
  that category as `hacktool`/`crack`, regardless of what the file actually
  does.
- A minority of engines report it (mostly labelled `hacktool/crack`).
  **Microsoft Defender has also flagged it on some machines** (e.g. the
  generic `Wacatac`/`Sabsik`/`Commando` ML labels), and engines that sort the
  tool as potentially unwanted report riskware category labels such as
  `RiskWare.Agent`. Definitions change over time, so a clean scan today does
  not guarantee a clean scan tomorrow.
- Both entries a scan can show are the **same binary**, the unlock
  `winmm.dll`. See [The two files an antivirus
  flags](#the-two-files-an-antivirus-flags).

## Why antivirus engines flag it

- **It bypasses a license.** Tools that bypass licensing are classified by
  definition as "hacktool" or "crack" by some vendors. A few of them (e.g.
  ESET) keep that label even after manual review.
- **Category labels, not signatures.** Engines that cannot match a known
  signature score the file with heuristics and machine learning, so a clean
  scan on one machine and a detection on another is normal for this category
  of tool.
- **Machine-learning labels.** Vendors that ship ML models report generic
  labels that change with every definition update, such as the Microsoft
  Defender `Wacatac`/`Sabsik`/`Commando` detections.
- **Riskware category labels.** Engines that sort the tool into potentially
  unwanted / riskware software report names built on that category, such as
  `RiskWare.Agent`. The name says which bucket the engine put the file in,
  not which family it found in it, and it carries no behavior claim beyond
  that category.

## The two files an antivirus flags

A scan usually shows two entries, and both are the same DLL:

| Path | What it is |
|---|---|
| `C:\XboxGames\Minecraft for Windows\Content\winmm.dll` | the installed unlock, the file the game loads |
| `%LOCALAPPDATA%\mbu-cache\payload-x64.bin` | the installer's own offline cache copy of that same DLL, under its internal name |

The cache copy is not a second component. The installer only uses it when its
SHA-256 matches the official one, so it is byte-identical to the file in the
game folder. Since v4.9.31 no copy the installer keeps outside the game folder
is named `winmm.dll`, which is why the cached one is called
`payload-x64.bin`.

## What this means for you

- The detections are **heuristic labels**, not evidence of malicious behavior.
- The installer and the unlock source are open source, so anyone can audit
  exactly what they do and how the binary is built.
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

## Open source and the antivirus labels

The unlock source is published in [`source/`](../source) under the GPLv3, so
anyone can read, build and audit the mechanism. The labels above do not go
away because of that: some vendors classify any license bypasser as
`hacktool`/`crack` by definition, and machine-learning labels move with the
definition updates.

Being open has a second effect, and this page will not hide it: anyone can
rebuild the code and spread their own copies, including the fake "fix"
installers that already circulate in Discord chats. What separates the
official file from those copies is identity: the SHA-256 in `SHA256SUMS.txt`
and on the release page pins the exact binary distributed here, and a rebuild
will not match it. The official binary is the one downloaded from this
repository.

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

### What you can verify

Everything around the binary is open and auditable:

- **The unlock source is public (GPLv3).** The code behind
  `release/winmm.dll` lives in [`source/`](../source). Read it, or build your
  own copy from it.
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
- **Behavior can be watched.** You can also observe the shipped binary:
  run the installer in a disposable VM, or with Sysinternals Process Monitor
  open, and see what it touches. Uploading the file to VirusTotal is also
  useful, but expect
  `hacktool`/`crack` labels from some engines (that is the category, see
  above) and look for whether anything beyond that shows up. See
  [VirusTotal](virustotal.md) for how to read that report.

### If you still do not trust it

That is a valid outcome. "I will not run this" is a reasonable decision, and
the only fully safe option is not running the tool. Not trusting an unlocker
is a legitimate position. The mistake would be to jump from "I cannot verify
this myself" straight to "it is malware": that conclusion has exactly as
much evidence behind it as "the README says it is safe, so it is". Neither
is proof. The difference is that the steps above let you gather real
evidence if you want it.

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
     (the Xbox App installation, the copy this project supports).
   - **Other AVs:** add the same folder to their exclusion/whitelist, and check
     the product's own quarantine list. A quarantine done by a third-party
     antivirus does not appear in Windows Security, and the Defender exclusions
     do not apply to other products.
2. Run the installer again. It writes a verified copy, checks the hash again
   after copying, and names the active third-party antivirus when the file
   disappears right after the install.

### If the antivirus blocks the write instead of quarantining the file

Some products block the write while the installer is running, without removing
anything: the install ends with *access denied writing winmm.dll*, and the
report shows the antivirus by name. **360 Total Security** is the one reported
most often. Adding the folder to its exclusion list does not always stop its
file guard from refusing the DLL, so also add the folder to its **Trust List**
(Settings > Antivirus > Trusted Files, or the trusted zone in the version you
have), or turn its real-time protection off for the duration of the install.
Since v4.9.44 the error message prints the exact folder to add, which is the
folder the game files really live in (`C:\XboxGames\...` for an Xbox app
installation, even when the package folder in `WindowsApps` points there).

Since v4.9.44 the installer also retries the publish by copying the DLL under
the final name when the rename is refused, so a product that only blocks the
rename no longer fails the install. The `[swap]` line of the report tells the
developer which way worked.

The same products can block the installer earlier, while it writes its own
temporary file in `%TEMP%\mbu`. Since v4.9.48 that case has its own message
(*Could not write the temporary download file*), it names the antivirus found on
the machine, and the installer first moves to a new file name and to a second
working folder by itself. Since v4.9.49 the same switch also happens when the
denial arrives in the middle of a download attempt, instead of retrying the same
blocked file until the sources run out. If it still fails, add `%TEMP%\mbu` and
`%LOCALAPPDATA%\mbu-cache` to the exclusions (or trusted folders) of the product,
restore the file from its quarantine if it is there, and run the installer again.
The full instructions are in [TROUBLESHOOTING](../TROUBLESHOOTING.md).

Since v4.9.51 the message for a download blocked **after it arrives** prints the
exact list of folders to exclude and names the antivirus products found running
on the machine, so you do not have to guess which product to configure.

### If Defender blocks the command you typed instead of a file

This one is not about the binary. If you start the installer by wrapping the
official one-liner inside another PowerShell command, for example from a
Command Prompt window:

```
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/CoelhoFZ/Minecraft-Bedrock-Free/main/i.ps1 | iex"
```

Windows Defender can flag that **command line** as `Trojan:Win32/Commando.A!ml`
and terminate the process before the installer runs. The detection names the
`CmdLine` of `powershell.exe` as the affected resource, and the protection
history shows the remediation applied to the process, not to a file. Downloading
a script and running it in the same line is the pattern that heuristic reacts
to, so the block is about the command, not about the files of this project.

Use one of the two official entries directly, with no wrapper around it:

- In PowerShell:
  `irm https://raw.githubusercontent.com/CoelhoFZ/Minecraft-Bedrock-Free/main/i.ps1 | iex`
- The `install.bat` published on the
  [release page](https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases/latest)

If the notification appears again, choose "Allow on device" in the Defender
notification, or add the exclusion described above. After the installer runs,
`%TEMP%\mbu-bootstrap.log` records each step of the launch.

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for these and other problems.
