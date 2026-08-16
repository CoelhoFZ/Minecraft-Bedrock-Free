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
$menuHash = '7ae41651236be10a5a00f3d48b32d3d5076f48ede0c1e7597846a1541dc368d9'
$menuActual = (Get-FileHash -Path $menu -Algorithm SHA256).Hash.ToLowerInvariant()
if ($menuActual -ne $menuHash) {
    Write-Host ''
    Write-Host 'ERRO: o hash do menu.ps1 baixado nao confere com o esperado.' -ForegroundColor Red
    Write-Host "  Esperado: $menuHash"
    Write-Host "  Recebido: $menuActual"
    Write-Host 'Isso geralmente significa que o menu.ps1 no repositorio foi' -ForegroundColor Yellow
    Write-Host 'atualizado sem sincronizar o hash neste bootstrap (i.ps1).' -ForegroundColor Yellow
    Write-Host 'Se voce nao e o mantenedor, desconfie do link que usou.'
    Read-Host 'Pressione Enter para fechar esta janela'
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
