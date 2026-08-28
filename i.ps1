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
# O hash abaixo e calculado sobre o CONTEUDO normalizado para LF (todos os
# bytes 0x0D removidos), PRESERVANDO o BOM UTF-8 do inicio do arquivo. Isso
# deixa a verificacao imune a finais de linha: o GitHub serve o arquivo do
# jeito que esta no blob (LF ou CRLF) e o mantenedor pode gerar hash numa
# copia com o outro fim, os dois passam, eliminando o bug classico "hash do
# menu nao confere" por CRLF vs LF. Para gerar o hash apos editar menu.ps1,
# use este mesmo normalize (remover 0x0D, manter BOM) sobre o arquivo.
$menuHash = '3694781384320c115be0d73c93b119af9879ede3e8976f9be7350eda7c821455'
$menuBytes = [IO.File]::ReadAllBytes($menu)
# Filtra todos os bytes de CR (0x0D) preservando os demais (incl. o BOM).
$clean = New-Object System.Collections.Generic.List[byte]
foreach ($b in $menuBytes) { if ($b -ne 13) { $clean.Add([byte]$b) } }
$menuBytes = $clean.ToArray()
$tmpHash = [System.Security.Cryptography.SHA256]::Create()
$menuActual = [BitConverter]::ToString($tmpHash.ComputeHash($menuBytes)).Replace('-','').ToLowerInvariant()
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
