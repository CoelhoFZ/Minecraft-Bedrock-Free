# uninstall.ps1 - Minecraft-Bedrock-Free - remove o unlock e restaura.
# Uso:   .\uninstall.ps1
$ErrorActionPreference = 'Stop'

function Find-MinecraftContent {
    $candidates = @()
    $candidates += 'C:\XboxGames\Minecraft for Windows\Content'
    try {
        $appx = Get-AppxPackage -Name 'Microsoft.MinecraftUWP*' -ErrorAction Stop |
            Select-Object -First 1
        if ($appx -and $appx.InstallLocation) {
            $candidates += $appx.InstallLocation
            $candidates += (Join-Path $appx.InstallLocation 'Content')
        }
    } catch { }
    foreach ($c in $candidates) {
        if ((Test-Path $c) -and (Test-Path (Join-Path $c 'Minecraft.Windows.exe'))) {
            return $c
        }
    }
    throw "Content do Minecraft nao encontrado."
}

function Remove-MbuDefenderExclusions {
    # Remove as exclusoes do Defender que o INSTALADOR adicionou (pasta temp
    # mbu, pasta Content do jogo e processo Minecraft.Windows.exe). Ate a
    # v4.4.2 o uninstall deixava exclusao de AV permanente sem o usuario
    # saber - higiene ruim. Best-effort: sem admin/Tamper Protection pode
    # negar; nesse caso avisa e segue (nunca impede a remocao do unlock).
    $paths = @()
    foreach ($p in @($args)) { if ($p) { $paths += $p } }
    try {
        $pref = Get-MpPreference -ErrorAction Stop
        $targets = @()
        foreach ($p in @($pref.ExclusionPath)) {
            if (-not $p) { continue }
            $match = ($paths -contains $p) -or ($p -match '\\mbu(-cache)?$') -or
                     ($p -like '*XboxGames\Minecraft*') -or ($p -like '*MinecraftUWP*')
            if ($match) { $targets += $p }
        }
        foreach ($t in $targets) {
            try {
                Remove-MpPreference -ExclusionPath $t -ErrorAction Stop
                Write-Output "Exclusao do Defender removida: $t"
            } catch { }
        }
        $procTargets = @()
        foreach ($p in @($pref.ExclusionProcess)) {
            if ($p -and ($p -match 'Minecraft\.Windows\.exe')) { $procTargets += $p }
        }
        foreach ($t in $procTargets) {
            try {
                Remove-MpPreference -ExclusionProcess $t -ErrorAction Stop
                Write-Output "Exclusao de processo removida: $t"
            } catch { }
        }
        if (($targets.Count -eq 0) -and ($procTargets.Count -eq 0)) {
            Write-Output "Nenhuma exclusao do Defender do unlocker encontrada (nada a limpar)."
        }
    } catch {
        Write-Output "Nao foi possivel listar/remover exclusoes do Defender (rode como administrador)."
    }
}

$content = Find-MinecraftContent
$p = Get-Process Minecraft.Windows -ErrorAction SilentlyContinue
if ($p) {
    Write-Output "Fechando Minecraft..."
    $p | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# Garante escrita na pasta e no winmm.dll (WindowsApps e protegida por TrustedInstaller).
try { & takeown /f $content 2>&1 | Out-Null } catch { }
try { & icacls $content /grant '*S-1-5-32-544:(OI)(CI)F' 2>&1 | Out-Null } catch { }

$winmm = Join-Path $content 'winmm.dll'
if (Test-Path $winmm) {
    try { & takeown /f $winmm 2>&1 | Out-Null } catch { }
    try { & icacls $winmm /grant '*S-1-5-32-544:(F)' 2>&1 | Out-Null } catch { }
}
Remove-Item $winmm -Force -ErrorAction SilentlyContinue
if (Test-Path (Join-Path $content 'winmm.dll.orig')) {
    Move-Item (Join-Path $content 'winmm.dll.orig') $winmm -Force
    Write-Output "winmm original restaurado."
} else {
    Write-Output "winmm.dll removido (o jogo usara o do sistema)."
}
Write-Output "Unlock removido."

# Limpa as exclusoes de AV que o instalador pode ter deixado (v4.5.0+):
# temp mbu, cache offline e a pasta do jogo.
Remove-MbuDefenderExclusions $content (Join-Path $env:TEMP 'mbu') (Join-Path $env:LOCALAPPDATA 'mbu-cache')
