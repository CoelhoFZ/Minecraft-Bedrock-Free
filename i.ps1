# i.ps1 - Minecraft Bedrock Free - bootstrap (open source, GPLv3).
#
# Baixa o menu interativo e o abre em uma janela CMD (fundo preto classico),
# igual ao install.bat. Solicita elevacao (UAC) se preciso.
#
# Uso (PowerShell):
#   irm https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/raw/main/i.ps1 | iex
$ErrorActionPreference = 'Stop'

$base = if ($env:MBU_BASE_URL) { $env:MBU_BASE_URL.TrimEnd('/') } else {
    'https://raw.githubusercontent.com/CoelhoFZ/Minecraft-Bedrock-Free/main'
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$menu = Join-Path $env:TEMP 'mbu-menu.ps1'
Invoke-WebRequest -UseBasicParsing -Uri "$base/menu.ps1" -OutFile $menu
$menuHash = 'a5f62c9c851f446290f02754e26c7f8a7b8d5cc3e99b5d4b1d0292d159ddd512'
$menuActual = (Get-FileHash -Path $menu -Algorithm SHA256).Hash.ToLowerInvariant()
if ($menuActual -ne $menuHash) {
    Write-Host "Hash do menu.ps1 invalido: $menuActual (esperado $menuHash). Abortando."
    exit 1
}

# Abre o menu em uma janela CMD (mesmo visual do install.bat): um .bat em
# %TEMP% titula a janela, aplica o fundo preto classico e roda o menu.
$launcher = Join-Path $env:TEMP 'mbu-launch.bat'
[System.IO.File]::WriteAllLines($launcher, @(
    '@echo off',
    'title Minecraft Bedrock Free',
    'color 07',
    ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $menu),
    'del "%~f0" >nul 2>&1'
), [System.Text.Encoding]::ASCII)

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

try {
    if ($isAdmin) {
        Start-Process -FilePath $launcher
    } else {
        Write-Host 'Solicitando permissao de administrador (UAC)...'
        Start-Process -FilePath $launcher -Verb RunAs
    }
} finally {
    # Fecha a janela atual (o menu roda na janela CMD nova).
    exit
}
