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
