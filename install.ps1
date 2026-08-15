# install.ps1 - Minecraft-Bedrock-Free - instalador (open source, GPLv3).
#
# Instala o winmm.dll proprio (release/) no diretorio do Minecraft.
# Uso:   git clone https://github.com/CoelhoFZ/Minecraft-Bedrock-Free
#        cd Minecraft-Bedrock-Free
#        .\install.ps1
param([string]$DllPath)

$ErrorActionPreference = 'Stop'

$here = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$dll = if ($DllPath -and (Test-Path $DllPath)) { $DllPath } else { Join-Path $here 'release\winmm.dll' }
if (-not (Test-Path $dll)) {
    throw "winmm.dll nao encontrado. Use o comando irm do README ou execute a partir do clone do repo."
}

# ---- 1. localiza o Content do Minecraft (Xbox App GDK ou Microsoft Store) ----
function Find-MinecraftContent {
    # Xbox App (GDK/MSIXVC): instala em C:\XboxGames\Minecraft for Windows\Content.
    $xbox = 'C:\XboxGames\Minecraft for Windows\Content'
    if ((Test-Path $xbox) -and (Test-Path (Join-Path $xbox 'Minecraft.Windows.exe'))) {
        return $xbox
    }
    # Microsoft Store (UWP): instala em C:\Program Files\WindowsApps\Microsoft.MinecraftUWP_*.
    # O InstallLocation do pacote vale para a Store e tambem para outros drives.
    $appx = Get-AppxPackage -Name 'Microsoft.MinecraftUWP*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($appx -and $appx.InstallLocation) {
        if (Test-Path (Join-Path $appx.InstallLocation 'Minecraft.Windows.exe')) {
            return $appx.InstallLocation
        }
        throw "Pacote do Minecraft encontrado, mas o executavel esta faltando. Reinstale o Minecraft e tente de novo."
    }
    throw "Content do Minecraft nao encontrado. Instale o Minecraft pelo Xbox App ou pela Microsoft Store e tente de novo."
}

$content = Find-MinecraftContent
Write-Output "Content: $content"

# ---- 1b. garante escrita na pasta (WindowsApps e protegida por TrustedInstaller) ----
try { & takeown /f $content 2>&1 | Out-Null } catch { }
try { & icacls $content /grant '*S-1-5-32-544:(OI)(CI)F' 2>&1 | Out-Null } catch { }

# ---- 2. fecha o jogo (UWP segura as DLLs mapeadas - falha silenciosa) ----
$p = Get-Process Minecraft.Windows -ErrorAction SilentlyContinue
if ($p) {
    Write-Output "Fechando Minecraft..."
    $p | Stop-Process -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        if (-not (Get-Process Minecraft.Windows -ErrorAction SilentlyContinue)) { break }
    }
    Start-Sleep -Seconds 1
}

# ---- 3. backup do winmm original (uma unica vez) ----
$winmm = Join-Path $content 'winmm.dll'
if ((Test-Path $winmm) -and -not (Test-Path (Join-Path $content 'winmm.dll.orig'))) {
    Copy-Item $winmm (Join-Path $content 'winmm.dll.orig') -Force
    Write-Output "Backup do winmm original em winmm.dll.orig"
}

# ---- 4. remove artefatos de versoes antigas / de outros projetos ----
foreach ($f in @('dlllist.txt',
                 'unlock-CoelhoFZ.dll', 'unlock-CoelhoFZ.ini',
                 'unlocker-CoelhoFZ.dll', 'unlocker-CoelhoFZ.ini',
                 'XGameCore.GDK.dll', 'XGameCore.GDK.ini')) {
    Remove-Item (Join-Path $content $f) -Force -ErrorAction SilentlyContinue
}

# ---- 5. instala o binario ----
# O winmm.dll do jogo pode ter ACL restrita ou read-only (ex.: dono SYSTEM).
# O instalador roda elevado: toma posse e limpa o atributo antes de copiar
# (sem isso o Copy-Item falha com "Access denied" - issue #45).
if (Test-Path $winmm) {
    try { Set-ItemProperty -Path $winmm -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue } catch { }
    try { Remove-Item $winmm -Force -ErrorAction SilentlyContinue } catch { }
}
if (Test-Path $winmm) {
    # ACL restrita (dono SYSTEM/TrustedInstaller): toma posse e libera escrita.
    try { & takeown /f $winmm 2>&1 | Out-Null } catch { }
    try { & icacls $winmm /grant '*S-1-5-32-544:(F)' 2>&1 | Out-Null } catch { }
    try { Set-ItemProperty -Path $winmm -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue } catch { }
    try { Remove-Item $winmm -Force -ErrorAction SilentlyContinue } catch { }
}
Copy-Item $dll $winmm -Force
Write-Output "OK - unlock instalado."

# ---- 6. abre o Minecraft automaticamente ----
try {
    $exe = Join-Path $content 'Minecraft.Windows.exe'
    if (Test-Path $exe) {
        Start-Process -FilePath $exe -WorkingDirectory $content -ErrorAction Stop
    } else {
        Start-Process 'shell:AppsFolder\Microsoft.MinecraftUWP_8wekyb3d8bbwe!App' -ErrorAction Stop
    }
    Write-Output "Minecraft iniciado."
} catch {
    Write-Output "Nao foi possivel iniciar o Minecraft automaticamente. Abra pelo menu Iniciar."
}
