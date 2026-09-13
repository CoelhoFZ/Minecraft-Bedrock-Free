# Troubleshooting

Common problems and how to recover. Run the installer again (`irm
https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/raw/main/i.ps1 | iex`)
after fixing the underlying cause.

## Automatic failure reports

The installer no longer prints a diagnostics report on screen. When something
fails - an installer error, Minecraft not opening after install, or the game
crashing right after launch (Bad Image 0xc0e90007) - the menu asks:

> Send the report to the developer to help fix the problem? (Y for yes, N for no)

If you confirm, a diagnostic report (OS, PowerShell, admin status, game
folder, install source, game version and architecture, the installed unlock
build, Defender exclusions and cache status) is sent automatically to the
project maintainer through a Cloudflare Worker. Nothing leaves your machine
without your confirmation, and declining changes nothing about how the
installer behaves.

## "'xxx' is not recognized as an internal or external command" errors from a .bat file

If you ran a `.bat` file and cmd printed a long list of errors like

```
'r' is not recognized as an internal or external command, ...
't-Bedrock-Free' is not recognized as an internal or external command, ...
'<text in Arabic, Hindi, Russian or other scripts>' is not recognized ...
```

followed by a banner warning about short links and "Press any key to continue",
that copy is broken and must not be trusted. Every supported `install.bat` is
**pure ASCII on purpose**: cmd.exe mis-parses a batch file that contains
non-ASCII bytes (it loses its position in the file, splits the command line and
prints exactly those "not recognized as an internal command" errors without
ever running the installer). The garble appears when a rewritten copy of the
installer (usually spread through YouTube, TikTok, Telegram, WhatsApp groups or
short links) embeds translated text saved in an encoding cmd.exe cannot parse.
Some of those copies even include the warning banner of this project to look
official. That is exactly what the warning describes.

**Historical note:** the official `install.bat` from v4.7.0 to v4.9.5 carried
those localized messages inside the .bat file itself and therefore produced the
same symptom - an old copy downloaded from this repository (or from an old
release) can fail with those errors. Since v4.9.6 the file is pure ASCII again.
If you see this with a copy that came from here, re-download `install.bat` from
the [Releases](https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases) page.

How to recover:

1. Do not run that file again and do not trust wherever it came from.
2. Delete it and use one of the two official install methods only:
   - `irm https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/raw/main/i.ps1 | iex` in PowerShell, or
   - the official `install.bat` from the repository page or from the
     [Releases](https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases) page.
3. The official bootstrap file is `i.ps1`. There is no `e.ps1` in this
   repository, so any guide telling you to run `e.ps1` is outdated or fake.

## "An object at the specified path does not exist: C:\Users\NAME~1" (temporary folder)

Seen on Windows with a **space in the user name** (for example `PC XEON`).
Windows stores the temporary folder with the **8.3 short name**
(`C:\Users\PCXEON~1\AppData\Local\Temp`) in the `%TEMP%` environment variable.
When that short alias no longer exists on the volume (8.3 names disabled by
policy, recreated user profile, cloned/restored image), every file operation
pointed at `%TEMP%` hits a dead path: PowerShell reports
`An object at the specified path does not exist` (the message comes from the
PowerShell file-system provider, so it is shown in your system language) and the
installer stops.

**Addressed in v4.9.7**, with two changes:

1. The installer no longer trusts `%TEMP%` blindly: it resolves a temporary
   folder that is **proven to exist and accept writes**, in this order:

   1. `%TEMP%`, 2. `%TMP%`, 3. `%LOCALAPPDATA%\Temp`,
   4. `%USERPROFILE%\AppData\Local\Temp`, 5. `%SystemRoot%\Temp`.

   Candidates whose name carries an **8.3 short alias** (`C:\Users\NAME~1\...`)
   are tried **last**, so the readable spelling (`%LOCALAPPDATA%\Temp`) wins
   when it accepts writes. Nothing is discarded: if only the short spelling
   works, it is still used.

   The selected folder is printed in the failure report on the
   `[temp] used=...` line (with `env=`, `tmp=`, `local=`, `uprof=`, `sysroot=`
   for comparison).

2. The failure report now records the **exact operation that failed**: cmdlet,
   script line and `FullyQualifiedErrorId` (line `[error] ...`). That makes the
   next occurrence point straight at the failing step instead of leaving only
   the translated message.

Note: the Windows PowerShell host itself creates `%TEMP%` when it starts, so a
missing temporary folder can appear as a real directory once the installer runs.
If you are on an older version, update to v4.9.7 or later (the bootstraps
`install.bat` and `i.ps1` resolve the folder too, so redownloading either one is
enough).

## "Bad Image" error (status 0xc0e90007) for WINMM.dll when launching Minecraft

```
Minecraft.Windows.exe - Bad Image
C:\Program Files\WindowsApps\...\WINMM.dll is either not designed to run
on Windows or it contains an error. Error status 0xc0e90007.
```

**What it means:** the `winmm.dll` the game is loading is *not a valid DLL
anymore*. It was corrupted, truncated, or removed after the installer finished.
The installer itself verifies the file before finishing (see below), so this
almost always happens *after* a successful install, for one of two reasons:

1. **Antivirus quarantined/modified the DLL.** Antivirus engines flag tools
   in this category and sometimes report generic heuristic labels (e.g.
   `Wacatac`, `Sabsik`, `Commando`). When Windows Defender or another AV
   quarantines it, the game is left loading a broken/missing file.
2. A previous (older) installer version failed mid-copy and left a truncated
   `winmm.dll`.

**How to fix:**

1. Run the installer again. It replaces `winmm.dll` with a verified copy and, if
   anything goes wrong, it puts back the `winmm.dll` that was there before (your
   previous unlock or the game original), so the game is never left without a
   working file.
2. Add an antivirus exclusion for the Minecraft folder so it is not flagged
   again:
   - **Windows Defender:** Settings → Privacy & security → Windows Security →
     Virus & threat protection → Manage settings → Exclusions → Add an
     exclusion → Folder → select `C:\XboxGames\Minecraft for Windows\Content`
     (Xbox App) or the `Microsoft.MinecraftUWP_*` folder inside
     `C:\Program Files\WindowsApps` (Microsoft Store).
   - Other AVs: add the same folder to their exclusion/whitelist.
3. Launch Minecraft. The "Desbloquear Jogo Completo" button should be gone.

If you no longer have the original DLL, reinstalling the game from the Store
restores it, then run the installer again.

**Still crashing and the error path does not match the installer output?** Since
the game moved to the Xbox App layout (files under
`C:\Program Files\WindowsApps\Microsoft.MinecraftUWP_<version>_x64__8wekyb3d8bbwe`),
some machines keep a stale second copy of the game executable under
`C:\XboxGames\Minecraft for Windows\Content` (leftover from the migration).
If the crash message names a `WINMM.dll` under
`C:\Program Files\WindowsApps\...` but the installer said it used
`C:\XboxGames\...`, the unlock went to the copy the game does not run from and
the game is loading an old or broken `winmm.dll` from the package folder. On
those machines:

1. Run the installer again. It prints the Content folder it will use (the
   registered package in WindowsApps comes first). If Minecraft crashes right
   after opening, the menu offers to send the failure report to the developer.
   The report lists every game folder candidate found and marks the one the
   installer used. When the registered package folder (WindowsApps) differs
   from `C:\XboxGames`, that is the case below.
2. Close Minecraft. Delete the stale copy:
   `rmdir /s /q "C:\XboxGames\Minecraft for Windows"` (only when the game
   actually runs from the WindowsApps package, which the diagnostics confirm).
   This is a leftover folder, the installed game itself is not there.
3. Run the installer again. It now targets the registered package folder and
   replaces the broken `winmm.dll` with a verified copy.

## "Access to the path '...winmm.dll.new' is denied" during install

```
Access to the path 'C:\Program Files\WindowsApps\...\winmm.dll.new' is denied.
```

(Depending on the installer version the denied file may be `winmm.dll`,
`winmm.dll.new` or `winmm.dll.new-<hex>`. All of them are the same problem.)

**What it means:** the installer could not create its file inside the game
folder. `C:\Program Files\WindowsApps` is protected by TrustedInstaller, so the
installer first takes ownership of the package folder and grants write access
to the current user, SYSTEM and the Administrators group, then verifies the
permission by actually creating a test file. When Windows still refuses the
write, the cause is almost always one of these:

- Minecraft or another process is holding the folder (close the game first).
- An antivirus with ransomware protection (Windows "Controlled folder access"
  or a third-party equivalent) is blocking writes to the folder even for an
  administrator.
- A security policy or a second antivirus product is denying the change to the
  folder permissions.

**How to fix:**

1. Close Minecraft completely (the game keeps the DLL mapped while running).
2. Make sure the installer runs **as administrator**. The official bootstrap
   (`irm ... | iex`) and `install.bat` request elevation automatically. If you
   are on an account without admin rights, ask the machine's administrator to
   run it.
3. Run the installer again. Recent versions retry the write step up to three
   times and re-apply the folder permissions between attempts, so a temporary
   block often clears on the second try.

If it still fails, your antivirus is the likely blocker:

1. Open Windows Security and check **Virus and threat protection > Ransomware
   protection**. If Controlled folder access is on, allow the installer (or
   add the Minecraft folder under the previous section) and retry.
2. If you use a third-party antivirus, add the Minecraft folder and
   `%TEMP%\mbu` to its exclusions, or temporarily disable its real-time
   protection, and retry.
3. Some third-party antivirus products ship their own "protected folders" or
   anti-ransomware feature (even when Windows Security shows Defender as
   passive). If the installer still fails with **Administrator: yes** in the
   report, that feature is the blocker: allow the Minecraft Content folder in
   it, then retry.

The failure report you can send from the menu includes an `[acl]` line with
the result of every permission step (takeown, grants and the write probe).
Steps that fail also include the tool's own output (for example
`grantAdm=1, grantAdmErr=Access is denied. | ...`), which tells whether the
permission change itself was rejected.

If you are still stuck after the steps above, sending that report tells the
developer exactly which step is being denied.

Since v4.9.8 the installer is explicit about this case:

- When a third-party antivirus with real-time protection is registered, the
  menu warns **before** installing and names it (the automatic exclusions only
  cover Windows Defender, so they do nothing for it).
- When the write is denied even though the folder was released and the write
  probe passed, the error message names the detected antivirus instead of
  showing the raw `Access to the path ... is denied` from .NET.
- The staging file uses a unique name per attempt, so a `winmm.dll.new` left
  locked by an antivirus from a previous run no longer blocks the next try.
- The failure report carries an `[error]` line with the cmdlet and the script
  line of the operation that actually failed (`cmd=Copy-Item line=...`),
  instead of pointing at the installer's internal rethrow.

Since v4.9.10 a denied write no longer destroys the unlock you already had:

- Before touching `winmm.dll`, the installer moves it aside to a
  `winmm.dll.mbu-prev-*` file. If publishing the new DLL fails (exactly the
  antivirus case above), that file goes back to its place and the machine ends
  up exactly as it started, with the previous unlock or the game original still
  working. A `winmm.dll.mbu-prev-*` left behind by a run that was killed
  mid-swap is recovered on the next run.
- If the antivirus quarantines the new DLL right after it was copied, the
  installer puts the previous one back. Before, it only restored
  `winmm.dll.orig`, which does not exist when a known unlock was installed - in
  that case the game was left with a broken `winmm.dll`.
- The failure report now carries `[swap]` (hash prefix of the DLL that was
  there, whether the swap published and whether a rollback was needed) and
  `[defender]` (whether the installer tried to add the automatic Defender
  exclusions and whether Windows accepted them, which is what Tamper Protection
  blocks - until now the report could not tell "tried and failed" from "never
  tried").
- `[threat]` and `[cfa]` now say when a third-party antivirus is active: those
  two lines read the Windows Defender log only, so `[threat] none` with another
  antivirus running means "not covered here", not "nothing blocked it".

## Installer blocks old or untested game versions (v4.9.5+)

Since v4.9.5 the installer refuses to start when your Minecraft **package
version is not in the tested list** (`tested-versions.json`), instead of
warning and continuing.

**What it means:** the unlocker is built for one Store version at a time. An
old game (for example 1.18.x) cannot be unlocked by the current binary, so the
installer stops before downloading anything, with the message
"Installation BLOCKED: game version ... has not been tested".

**How to fix:** update Minecraft from the Microsoft Store to the current
version, then run the installer again.

**If your game is NEWER than the tested list** (the Microsoft Store updated it
after this unlocker release, so updating again is not possible), the unlocker
simply does not support that build yet. Updating the game will not help -
the fix comes from this project: follow the
[Releases](https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases) page or
the [Discord](https://discord.gg/u3S4gFgK6M) for the version that adds support
for your build. You can also check which version this release supports in
[`tested-versions.json`](https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/blob/main/tested-versions.json).

## Installer fails while downloading with "contains a virus or potentially unwanted software" ([#49](https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/issues/49))
During the download step the installer verifies the binary it just wrote to
`%TEMP%\mbu\winmm.dll`. If your antivirus removes or blocks that file right
after it is written you may see errors like:
```
Get-FileHash : The file '...\Temp\mbu\winmm.dll' cannot be read: Operation did not complete successfully because the file contains a virus or potentially unwanted software.
```
followed by "You cannot call a method on a null-valued expression."
(on versions before v4.4.1 the second message replaced the real cause).

**What it means:** Microsoft Defender (or a third-party antivirus) flagged the
unlock binary during the write. The installer adds Defender exclusions before
downloading, but some setups still block the file anyway (cloud-delivered
protection acting at first sight, the engine applying new exclusions
asynchronously, managed policy ignoring local exclusions, or another
antivirus product running alongside Defender).

**How to fix:**
1. Open **Windows Security -> Virus & threat protection -> Protection history**
and look for the blocked `winmm.dll`. Choose **Allow** or **Restore**.
2. Add the exclusions manually (both folders):
   - `%TEMP%\mbu` (the download folder)
   - the Minecraft `Content` folder from the first section above
3. If you use another antivirus in addition to Defender, add the same
exclusions there too.
4. Run the installer again. Since v4.4.1 it retries automatically and shows a
clear message naming the folders when this happens.

### If it still fails (v4.9.9)

Two things changed, so read this before touching anything:

1. **The installer now uses its own offline copy first.** After any successful
   install it keeps the verified binary in `%LOCALAPPDATA%\mbu-cache`. When a
   download is removed or left unreadable (no network error involved - the file
   simply is not there or cannot be hashed), the installer copies that cached
   copy instead of failing. Same bytes, already accepted on your machine: in the
   2026-09-12 report the cached copy and the file inside the game folder were
   both intact while every fresh download was eaten in `%TEMP%`.
2. **"Controlled folder access" (ransomware protection) is handled.** Path
   exclusions do **not** cover it: it has its own allowed-applications list. If
   it is on, the error message now says so instead of sending you to
   Protection history, where there is no **Allow** button for this kind of
   block. To fix it: **Windows Security -> Virus & threat protection ->
   Ransomware protection -> Manage ransomware protection -> Controlled folder
   access**, then allow the installer/PowerShell and `Minecraft.Windows.exe`
   (or turn it off temporarily and run the installer again).

When you send the failure report, it now carries the objective evidence of the
block instead of only saying "your antivirus blocked it":

- `[dl]` - each download attempt and what happened to it (file missing, empty,
  unreadable hash, whether MotW was present, whether the offline cache worked),
- `[threat]` - the last entries Defender recorded as a threat (name, time,
  resource), which is what tells a real detection from a folder-protection
  block,
- `[cfa]` - recent controlled folder access events (1123 blocked / 1124
  audited) from the Windows Defender operational log.

See [docs/antivirus-false-positives.md](docs/antivirus-false-positives.md)
for why these detections happen.

## Verifying the installed file

The installer verifies the SHA-256 of `winmm.dll` both before and after copying
it. You can do the same manually:

```powershell
Get-FileHash "$env:ProgramFiles\WindowsApps\Microsoft.MinecraftUWP_*\winmm.dll" -Algorithm SHA256
# or, for the Xbox App install:
Get-FileHash "C:\XboxGames\Minecraft for Windows\Content\winmm.dll" -Algorithm SHA256
```

Compare against the hash published in
[`SHA256SUMS.txt`](https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/blob/main/SHA256SUMS.txt).
If it does not match, the file was modified. Reinstall.

## FAQ

### How do I remove the unlock without the menu?

Download `uninstall.ps1` from
<https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/raw/main/uninstall.ps1>,
open PowerShell **as administrator**, and run it. It closes the game, restores
`winmm.dll` (or removes it when there was no original), cleans the Defender
exclusions the installer added and deletes the local binary cache.

### Does it work with a third-party launcher / version switcher?

No. The unlock only works with the official **Microsoft Store / Xbox App**
build. It does nothing in other launchers - and can break them. Do not copy
it into another launcher.

### Does it work on an older Minecraft version?

The unlock targets the official build and is only tested on the **current**
version. Microsoft doesn't let you install an older version, so there's no
supported way to run an older version with this unlocker.
