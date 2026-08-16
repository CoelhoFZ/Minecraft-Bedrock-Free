# install.ps1 - Minecraft-Bedrock-Free - instalador (open source, GPLv3).
#
# Instala o winmm.dll proprio (release/) no diretorio do Minecraft.
# Uso:   git clone https://github.com/CoelhoFZ/Minecraft-Bedrock-Free
#        cd Minecraft-Bedrock-Free
#        .\install.ps1
param([string]$DllPath)

$ErrorActionPreference = 'Stop'

# ---- 0. eleva automaticamente se nao for administrador ----
# A pasta do pacote (WindowsApps) e protegida por TrustedInstaller: sem elevacao
# o takeown/icacls falha e o Copy-Item explode com "Access denied" (issue de
# usuarios que seguiram o caminho manual do README: .\install.ps1 direto).
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if (-not $PSCommandPath) {
        throw "Rode este script como administrador (clique direito -> Executar como administrador)."
    }
    Write-Output 'Solicitando permissao de administrador (UAC)...'
    $elevatedArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($DllPath) { $elevatedArgs += " -DllPath `"$DllPath`"" }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $elevatedArgs -Verb RunAs -WorkingDirectory (Get-Location).Path
    exit
}

$here = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$dll = if ($DllPath -and (Test-Path $DllPath)) { (Resolve-Path $DllPath).Path } else { Join-Path $here 'release\winmm.dll' }
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
        # GDK (Xbox App) fora do drive canonico pode resolver o InstallLocation
        # para a RAIZ do jogo, com o exe dentro de \Content (mesmo layout que o
        # uninstall.ps1 ja cobre). Tenta as duas formas antes de desistir.
        foreach ($c in @($appx.InstallLocation, (Join-Path $appx.InstallLocation 'Content'))) {
            if (Test-Path (Join-Path $c 'Minecraft.Windows.exe')) {
                return $c
            }
        }
        throw "Pacote do Minecraft encontrado, mas o executavel esta faltando. Reinstale o Minecraft e tente de novo."
    }
    throw "Content do Minecraft nao encontrado. Instale o Minecraft pelo Xbox App ou pela Microsoft Store e tente de novo."
}

# ---- 1b. ACL: toma posse e libera escrita (WindowsApps e protegida por TrustedInstaller) ----
# Retorna $true se o takeown+icacls tiverem sucesso. Antes os erros eram engolidos
# (try/catch nao pega falha de comando nativo) e o usuario via so "Access denied"
# na hora do Copy-Item.
function Grant-AdminFullControl {
    param([string]$Path, [string]$Perm)
    & takeown.exe /f $Path 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { return $false }
    & icacls.exe $Path /grant $Perm 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { return $false }
    return $true
}

$content = Find-MinecraftContent
Write-Output "Content: $content"

if (-not (Grant-AdminFullControl -Path $content -Perm '*S-1-5-32-544:(OI)(CI)F')) {
    throw "Nao foi possivel tomar posse da pasta do Minecraft (rode como administrador)."
}

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
if (Test-Path $winmm) {
    # Libera o arquivo (pode ter ACL restrita ou read-only - issue #45).
    Set-ItemProperty -Path $winmm -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
    Grant-AdminFullControl -Path $winmm -Perm '*S-1-5-32-544:(F)' | Out-Null
}
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

# ---- 5. instala o binario (atomico: copia para .new, valida hash, move) ----
# Se o Copy-Item falhar no meio (antivirus bloqueando, ACL restrita, arquivo em
# uso) um winmm.dll truncado/corrompido ficaria no lugar e o Minecraft abriria
# com "Bad Image" (0xc0e90007). Escrevendo em .new + validando o SHA256 antes do
# move, um copia quebrada nunca substitui o original.
$dllHash = (Get-FileHash -Path $dll -Algorithm SHA256).Hash
$tmp = Join-Path $content 'winmm.dll.new'
Remove-Item $tmp -Force -ErrorAction SilentlyContinue
Copy-Item $dll $tmp -Force
if ((Get-FileHash -Path $tmp -Algorithm SHA256).Hash -ne $dllHash) {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    throw "Falha ao copiar winmm.dll (copia corrompida/bloqueada). Verifique se o antivirus nao bloqueou e tente de novo."
}

# Substitui o original so depois de validar a copia (nunca deixa o jogo sem
# winmm.dll nem com um arquivo pela metade).
if (Test-Path $winmm) {
    Remove-Item $winmm -Force -ErrorAction SilentlyContinue
}
if (Test-Path $winmm) {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    throw "Nao foi possivel substituir winmm.dll (Access denied ou arquivo em uso). Feche o Minecraft e rode como administrador."
}
Move-Item $tmp $winmm -Force

# Verificacao final: antivirus (ex.: Windows Defender) pode quarentenar o DLL
# logo apos a copia. Se o hash nao bater aqui, restaura o original e avisa.
if ((Get-FileHash -Path $winmm -Algorithm SHA256).Hash -ne $dllHash) {
    $orig = Join-Path $content 'winmm.dll.orig'
    if (Test-Path $orig) {
        Remove-Item $winmm -Force -ErrorAction SilentlyContinue
        Copy-Item $orig $winmm -Force -ErrorAction SilentlyContinue
    }
    throw "O winmm.dll instalado foi corrompido/removido logo apos a copia (provavel antivirus). Adicione uma exclusao para a pasta do Minecraft e rode de novo."
}
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
