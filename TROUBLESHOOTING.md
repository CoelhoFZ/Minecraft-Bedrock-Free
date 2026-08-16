# Troubleshooting

Common problems and how to recover. Run the installer again (`irm
https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/raw/main/i.ps1 | iex`)
after fixing the underlying cause.

## "Bad Image" error (status 0xc0e90007) for WINMM.dll when launching Minecraft

```
Minecraft.Windows.exe - Bad Image
C:\Program Files\WindowsApps\...\WINMM.dll is either not designed to run
on Windows or it contains an error. Error status 0xc0e90007.
```

**What it means:** the `winmm.dll` the game is loading is *not a valid DLL
anymore* — it was corrupted, truncated, or removed after the installer finished.
The installer itself verifies the file before finishing (see below), so this
almost always happens *after* a successful install, for one of two reasons:

1. **Antivirus quarantined/modified the DLL.** The unlock binary is packed and
   protected against analysis, which heuristic engines flag (e.g.
   `Wacatac`, `Sabsik`, `Commando`). When Windows Defender or another AV
   quarantines it, the game is left loading a broken/missing file.
2. A previous (older) installer version failed mid-copy and left a truncated
   `winmm.dll`.

**How to fix:**

1. Run the installer again (it replaces `winmm.dll` with a verified copy and
   restores the original if anything goes wrong).
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
restores it; then run the installer again.

## "Access to the path '...winmm.dll' is denied" during install

```
Access to the path 'C:\Program Files\WindowsApps\...\winmm.dll' is denied.
```

**What it means:** the installer could not take ownership of the game folder.
`C:\Program Files\WindowsApps` is protected by TrustedInstaller and can only be
modified by an elevated (administrator) process.

**How to fix:**

1. Close Minecraft completely (the game keeps the DLL mapped while running).
2. Make sure the installer runs **as administrator**. The official bootstrap
   (`irm ... | iex`) and `install.bat` request elevation automatically; the
   manual `.\install.ps1` path now also self-elevates. If you are on an
   account without admin rights, ask the machine's administrator to run it.
3. Run the installer again.

If it still fails, your antivirus may be blocking the write: temporarily
disable real-time protection or add the Minecraft folder as an exclusion
(see the previous section) and retry.

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
If it does not match, the file was modified — reinstall.
