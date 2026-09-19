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
the [newest release](https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases/latest/download/install.bat).

How to recover:

1. Do not run that file again and do not trust wherever it came from.
2. Delete it and use one of the two official install methods only:
   - `irm https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/raw/main/i.ps1 | iex` in PowerShell, or
   - the official `install.bat` from the
     [newest release](https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases/latest/download/install.bat).
3. The official bootstrap file is `i.ps1`. There is no `e.ps1` in this
   repository, so any guide telling you to run `e.ps1` is outdated or fake.

## "ERRO: o hash do menu.ps1 baixado nao confere com o esperado" (hash mismatch, installer from an old release)

This message comes from an `install.bat` of **v4.9.13 or older**. Those versions
carried the fingerprint of the `menu.ps1` that was current when that release was
built, and they download `menu.ps1` from the `main` branch of this repository.
Every later release that changed `menu.ps1` turned an older `install.bat` into a
refusal: it stopped instead of running a menu it was not built with. The copy
could be official and still fail - an outdated download was enough (the Releases
page lists old versions side by side).

Since **v4.9.14** the official `install.bat` is a thin bootstrap: it does not
carry a fingerprint anymore, it always fetches the current bootstrap (`i.ps1`)
from the `main` branch and lets it download and verify the current `menu.ps1`.
That is how the PowerShell one-liner has always worked. The releases that still
had the old file were also refreshed with this bootstrap, so the links on the
Releases page (including old versions) now serve a file that keeps working.

If you still hit this message, your copy is an old `install.bat` that was saved
somewhere before that. How to recover:

1. Get the current `install.bat` (this link always serves the newest release):

   <https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases/latest/download/install.bat>

   or run in PowerShell (it always downloads the current menu):

   ```powershell
   irm https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/raw/main/i.ps1 | iex
   ```

2. If you already downloaded the newest `install.bat`, wait a few minutes and
   run it again. Right after an update the raw file server can still serve the
   previous `menu.ps1` for a few minutes, and the check fails until it refreshes.
3. If the file did not come from this repository, do not run it. The check is
there to stop a `menu.ps1` that does not match the bootstrap.

This failure happens before the menu starts, so no automatic report is sent.

## The window closes right after the UAC prompt (v4.9.15+)

Symptom: you run the one-liner (or `install.bat`), the download progress
appears, the UAC prompt shows up, you accept it, and then the window closes
without the menu and without any message.

Until v4.9.14 the installer opened the menu by writing a small `.bat` helper
inside `%TEMP%` and launching that helper elevated. A file created seconds
before, in the temporary folder, started with administrator rights is exactly
what antivirus suites, the Windows Defender attack surface reduction rules and
Smart App Control tend to block, and that block is silent. From v4.9.14 the same
launch path was also used by `install.bat`, so both official entries could fail
the same way.

Since v4.9.15 the launch works differently:

- If the window that started the installer is already elevated (a PowerShell or
  a Command Prompt opened as administrator), the menu runs in that same window.
  No new process and no helper file. Since v4.9.17 `install.bat` does not
  elevate itself anymore: it downloads `i.ps1` and lets it handle the elevation,
  so both official entries use the same launch path.
- Otherwise `powershell.exe` itself is elevated, not a helper script, and it
  runs the `menu.ps1` that was already verified by hash. If that elevated
  process fails or never starts, the original window stays open and prints the
  real error. Since v4.9.16 that elevated process is started by `cmd.exe`, so
  the new window keeps the default black console background instead of the blue
  background Windows stores for `powershell.exe`.
- The bootstrap writes a small log next to the downloaded menu, in `%TEMP%`,
  called `mbu-bootstrap.log`. It records each step, including the failure.

If you see `ERROR: the installer could not open with administrator permission`,
do this:

1. Open PowerShell **as administrator** (Start menu, right click on PowerShell,
   Run as administrator).
2. Run:

   ```powershell
   irm https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/raw/main/menu.ps1 | iex
   ```

   This opens the menu directly in the elevated window, with no second process
   involved.
3. If the menu opens now, add an exclusion for the temporary folder in your
   antivirus, or review the Defender rules
   ([antivirus false positives](docs/antivirus-false-positives.md)), and use the
   normal installer again.
4. If it still closes, `%TEMP%\mbu-bootstrap.log` records the last step that
   ran. Send that file to the developer together with the picture of the window.

The bootstrap can also report the failure by itself. When the launch fails it
asks the same question as the menu (send the report to the developer) and sends
the bootstrap stage log if you confirm. This failure happens before the menu
runs, so before v4.9.15 there was no automatic report for it at all.

## "It could not download the installer" in `install.bat`

```
ERRO: nao foi possivel baixar o instalador deste endereco:
```

**What it means:** the `install.bat` could not download `i.ps1`, so the menu
never started. That happens before anything else runs, which is why the message
comes from the batch file itself and not from the installer.

Since v4.9.17 that message is shown in the language of your Windows, in all the
8 languages of the installer. To do that the batch file downloads `i18n.json`
from this repository, a file with text only that is never executed, and picks
your language from it. If that download also fails (no connection at all), it
falls back to the fixed Portuguese and English text, which are the only ones
that fit inside a batch file.

**How to fix:** check your connection and run the file again. The bootstrap
already retries on temporary errors. If it keeps failing, download the newest
`install.bat` from
<https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases/latest/download/install.bat>.

## "Could not download winmm.dll" during install (server error or no connection)

**What it means:** the installer could not get the binary from the download
server. Since v4.9.25 there are two messages for it: one says the server
answered with a temporary error (503/502/504), the other says the installer
could not connect to the server at all (unstable connection, DNS, or a VPN or
proxy blocking the access). Neither one is a problem inside your machine.

**What the installer already does:** it retries the same address and waits
longer after each try, it honors the `Retry-After` header when the server sends
one, then it tries two alternative addresses for the same file, and when a
verified copy already exists in `%LOCALAPPDATA%\mbu-cache` it uses that copy
instead.

**How to fix:** check your connection, turn off any VPN or proxy you use, wait
a few minutes and run the installer again. The failure report carries a `[dl]`
line with the HTTP code of every attempt, which is what tells a temporary
server error from a block on your side.

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

## Minecraft closes right after launch with exit code 0x80070424 (v4.9.22+)

```
exit code: 0x80070424
```

**What it means:** `0x80070424` is the Windows error *"the specified service
does not exist"* (`HRESULT_FROM_WIN32(1060)`). Minecraft on Windows needs the
**Gaming Services** component to start, and this code means that component is
missing or damaged. It is **not** the unlock: a broken `winmm.dll` gives the
*Bad Image* error `0xc0e90007` instead (previous section).

**How to fix:**

1. Open the **Microsoft Store**, search for **Gaming Services**, open its page
   and install it again (the button says *Install* or *Reinstall*). On a machine
   with the Xbox App you can also run the **Gaming Services Repair Tool**.
2. If that does not help, remove the package and install it again from the
   Store. In a PowerShell window opened as administrator:

   ```powershell
   Get-AppxPackage Microsoft.GamingServices | Remove-AppxPackage -AllUsers
   ```
3. Restart the PC, open Minecraft once, close it, then run the installer again.

Since v4.9.22 the menu shows this explanation on screen in your language when the
game exits with this code, and the failure report marks it as
`0x80070424: Gaming Services missing/corrupt`, so it can be told apart from an
unlock problem. If you send the report, the `[pkg]` line also tells whether the
game package is registered in Windows and which folder is being used.

## Minecraft closes right after launch with exit code 0x87E50035 (v4.9.28+)

```
exit code: 0x87E50035
```

**What it means:** Windows could not activate the game app, so it started as a
plain executable and died before the window appeared. `0x87E5...` codes come from
the Store / Xbox app activation layer. It is **not** the unlock: a broken
`winmm.dll` gives the *Bad Image* error `0xc0e90007` instead (see the section
above).

Three lines of the report show this state:

- `[pkg] registered=no allusers=yes` means `-AllUsers` still sees the package on
  this PC while your account is not registered for it, which happens when the
  game was installed by another Windows user or the registration was lost. When
  both say `no`, there is no package on the PC at all.
- `[launch] mode=exe official=yes` means the installer started
  `Minecraft.Windows.exe` straight from the official folder, which only happens
  when the registered package is not available to open through `shell:AppsFolder`.
- `[crash] evidence=process-exit code=0x87E50035` is the activation failure.

**How to fix:** the game needs a registration for the account that owns it.

1. Open the **Xbox App** (or the **Microsoft Store**) signed in with the account
   that owns Minecraft and install, reinstall or repair the game from there.
2. If the game is already on disk and only the registration is missing, open
   PowerShell **as administrator** and register the package again:

   ```powershell
   Get-AppxPackage -AllUsers Microsoft.MinecraftUWP | ForEach-Object { Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppxManifest.xml" }
   ```
3. Open the game once to confirm it starts, then run this installer again.

Since v4.9.28 the menu shows this explanation on screen in your language when the
game exits with this code, and the failure report marks the reason as
`0x87E50035: app activation failed (package not registered)`.

## Minecraft closes and the crash log names WINMM.dll (v4.9.34+)

```
Faulting module name: WINMM.dll_unloaded, version: 0.0.0.0, timestamp: 0x00000000
Exception code: 0xc0000005
Fault offset: 0x6b37
```

**What it means:** the Windows crash log (WER) names the *faulting module*, so
when that module is `WINMM.dll` (sometimes written `WINMM.dll_unloaded`) the
fault was recorded inside the unlock, not in the game. The `_unloaded` suffix
means the module was already being or had been unloaded when the fault was
recorded, which is consistent with a short-lived unlock thread still pending
when the game released the DLL (or when the game was shutting down). The
`0.0.0.0` version and the `0x00000000` timestamp are also expected: the unlock
file is built without a version resource and without a timestamp, so they do not
point at a wrong file.

**What to do:**

1. Remove the unlock with option `[1]` of the menu and open the game: without
the unlock it starts normally. The menu offers exactly that right after the
crash, and since v4.9.34 it shows this explanation in your language instead of
the generic "Minecraft closed right after opening" message.
2. If your game is the old 1.21 line (Microsoft Store or Minecraft Launcher
   install), try updating it through the Microsoft Store or the Xbox App. The
   unlock is verified on the current build, so an update also gives you the
   supported target.
3. Send the failure report. Since v4.9.34 the report adds
   `[crash] fault-module=WINMM.dll_unloaded code=0xc0000005 off=0x6b37` (when the
   WER event carries these fields), which is what makes this case separable from
   the gaming services and app activation cases above.

The cause of the unload is under investigation; the module, the exception code
and the fault offset in the report are what make it possible to fix. Since
v4.9.35 the unlock stays loaded for the whole game session, which covers this
case on the installations that release the DLL; if the crash still appears on
v4.9.35 or newer, the report is what moves the fix forward.

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

Since v4.9.33 that line also reports `denySeen` and `denyRemoved` (deny
entries present on the folder, including inherited ones, and whether they
were removed) and adds a read-back of the folder state taken after the last
attempt (`aclOwner`, `aclDenyLeft`, `aclAdmWrite`). The report also
lists the file system filters loaded in the system in the `[filters]` line.
Since v4.9.35 the `Err=` suffix only appears when the tool really failed: a
localized *success* summary (for example the Spanish `Se procesaron
correctamente 1 archivos; error al procesar 0 archivos`, which contains the
word `error`) no longer marks a successful step as an error, and a failure is
recognized by the access-denied wording or by a non-zero count in the summary
(`Failed processing 1 files`). Steps that succeed are printed as `name=0`.
When the read-back shows the permissions are correct (owner changed, no deny
entry left, `aclAdmWrite=yes`) and the write is still denied, no permission
change will help: a product with a filter in the disk stack (antivirus,
endpoint security or a system hardening tool) is blocking the write to the
game folder, and the filter names in the report usually identify it.

If the game is the old Microsoft Store (UWP) installation (the game folder is
inside `C:\Program Files\WindowsApps`), Windows may deny the permission change
even to an administrator, and no antivirus exclusion will help. Since v4.9.33
the installer adds that note to the error message. The current Minecraft
version, installed through the Xbox app (GDK), uses a folder the installer can
write to (`C:\XboxGames`), so moving the game to that version is the way out on
a PC where the Store folder stays blocked. If the Store does not offer a newer
version, uninstall the game and install it again from the Store or the Xbox
app. Back up your worlds first: they live in
`%LOCALAPPDATA%\Packages\Microsoft.MinecraftUWP_8wekyb3d8bbwe\LocalState\games\com.mojang\minecraftWorlds`.

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
- Since v4.9.35 the `[swap]` line also tells why a copy was rejected:
  `verify=fail got=<hash prefix> want=<hash prefix>` means the copied file did
  not match the expected hash (the antivirus changed or quarantined it), while
  `got=unreadable` means the copy could not even be read back, which is what a
  file held open by a scanner looks like. The installer now re-reads that copy
  up to 3 times before giving up, so a short lock during the scan no longer
  fails the install and shows up as `verify=retry-ok`.
- `[threat]` and `[cfa]` now say when a third-party antivirus is active: those
  two lines read the Windows Defender log only, so `[threat] none` with another
  antivirus running means "not covered here", not "nothing blocked it".

## Installer blocks an old game version (v4.9.5+, version floor since v4.9.23)

Since v4.9.23 the installer checks a **minimum supported version** (the
`min_supported` field of `tested-versions.json`) instead of an exact list: any
Minecraft for Windows build from **1.21 on** is accepted, including a build
**newer** than the one this release was verified against. That is on purpose -
the unlock hooks the GDK license APIs (`XStore*`), which is not tied to the
game build.

**What it means when you are blocked:** your game build is **older** than the
floor (for example 1.17.x or 1.20.x). The installer stops before downloading
anything, with the message
"Installation BLOCKED: game version ... is older than the minimum supported
version (...)".

**How to fix:** update Minecraft from the Microsoft Store, then run the
installer again.

**If your game is NEWER than the `tested` list:** nothing to do, it is not a
block. Since v4.9.23 a build newer than the verified one installs normally.
Since v4.9.33 a build between the minimum supported and the verified build is
reported as `older than the verified build`, which is not a block either.
Older releases (v4.9.5 up to v4.9.22) refused it with the same message, so if
you saw this on a game that was already up to date, update the installer
(re-run the one-liner) and try again.

The `tested` list in
[`tested-versions.json`](https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/blob/main/tested-versions.json)
is only a record of the builds verified by hand; the `min_supported` field is
what decides if the installer proceeds.

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

- `[dl]` - every download attempt with the address, the attempt number, the
  HTTP code and the error text, plus what happened to the file (missing, empty,
  unreadable hash, whether MotW was present, whether the offline cache worked,
  and whether the installer moved to an alternative address),
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

## "Minecraft Launcher package found, but the game files are missing" (v4.9.20+)

On some machines the game is registered by the official Minecraft Launcher while
the game files are not there yet. The package points to
`%APPDATA%\.minecraft_bedrock\versions\<id>` and that folder has no
`Minecraft.Windows.exe`. The installer finds the package, sees that the game
executable is missing and stops with this message. Right above it the installer
lists the folders it checked, so you can compare that list with where your game
really is installed.

**How to fix:** open the launcher you installed the game with, let it finish the
installation (or use its verify/repair option), start the game once and close it,
then run the installer again. If your copy comes from the Microsoft Store or the
Xbox App, install it from there instead. The old wording for this case was only
"Minecraft package found but the game executable is missing", which sent users to
a full reinstall that was usually not necessary.

Since v4.9.30 that list also covers the folder the registered package really
points to and every `XboxGames` folder on the fixed drives of the PC. So a game
whose content sits in `C:\XboxGames\Minecraft for Windows_1\Content`, or on a
drive other than `C:`, is found and installed without a reinstall. The failure
report shows the same locations: the `[pkg]` line adds `target=` when the
package folder is a link, and each `[candidate]` line marks it as
`(junction -> ...)` followed by where it points.

## "Windows refused administrator permission for this account" (v4.9.21+)

This message appears when Windows itself refuses the elevation request, before
the UAC window is even shown. The installer needs administrator rights to write
the game files, so it cannot continue without them. Until v4.9.20 this case
printed only the raw Windows error text (`This command cannot be run due to the
error: Access is denied`), which told the user nothing.

Two causes are common:

1. The account you are using is not an administrator on this PC, so the request
   would need the user name and password of an administrator account.
2. The elevation prompt is blocked by a Windows policy, or by the family and
   parental controls of a child account, so the request is denied without
   asking anything.

**How to fix:** sign in with an administrator account and run the installer
again, or ask the administrator of the PC to run the command below in a
PowerShell window opened as administrator:

```powershell
irm https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/raw/main/menu.ps1 | iex
```

You can check your account type in Windows Settings, Accounts, Your info, where
it says "Standard user" or "Administrator". If the message says that you
cancelled the administrator request, the request reached the UAC window and was
declined: run the installer again and accept that window.

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

Since v4.9.26 the installer checks the folder it is about to use. When that
folder is not the official installation it explains the risk and asks for
confirmation before touching anything. When the game does not start after the
install, the failure message tells you to open the game through your launcher,
and the report records why the automatic start failed (executable missing,
start error, no process after the fallback).

### Does it work on an older Minecraft version?

The unlock targets the official build and is only tested on the **current**
version. Microsoft doesn't let you install an older version, so there's no
supported way to run an older version with this unlocker.

### I downloaded the file by hand and left it in Downloads / next to another game

Delete that extra copy and run the installer again, nothing else is needed. The
file must live only in the Minecraft game folder, which is where the installer
puts it. Any other program that starts from the same folder as the file picks it
up, which can stop that program from working (32-bit programs there may not open
at all) and online games with anticheat can flag the session.

### Where is the offline copy the installer keeps? (v4.9.31+)

It is `%LOCALAPPDATA%\mbu-cache\payload-x64.bin`. Do not move or rename it. It
is not the file the game reads, and only the installer places the file where the
game reads it. Installs up to v4.9.30 kept that same copy as `winmm.dll` in that
folder, and the installer now renames a valid copy to the new name on the first
run, so the offline install keeps working after the update.
