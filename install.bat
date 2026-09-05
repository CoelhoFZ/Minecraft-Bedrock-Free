@echo off
setlocal EnableExtensions
title Minecraft Bedrock Free

rem ---- solicita elevacao de administrador (UAC) ----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando permissao de administrador...
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

rem ---- baixa o menu, VALIDA O SHA256 e roda ----
rem O hash e calculado sobre o conteudo normalizado (bytes 0x0D removidos,
rem BOM preservado) - exatamente o mesmo algoritmo do i.ps1, imune a CRLF vs
rem LF. Ate a v4.4.2 este .bat baixava e executava o menu sem checar NADA;
rem agora ambos os caminhos de entrada (irm i.ps1 | iex e install.bat) tem a
rem mesma garantia de integridade.
rem
rem Manutencao: ao editar o menu.ps1, gere o novo hash com
rem   python3 -c "import hashlib; print(hashlib.sha256(open('menu.ps1','rb').read().replace(b'\r',b'')).hexdigest())"
rem e atualize $menuHashPin abaixo E a variavel $menuHash no i.ps1.
rem
rem Testes locais (VM/fork): defina MBU_BASE_URL apontando pro seu servidor e
rem MBU_EXTRA_HASH com o hash do seu menu local - a checagem contra o pin
rem oficial so e pulada quando AMBAS as variaveis existem (usuarios normais
rem nunca passam por aqui; fail-closed).
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $m = Join-Path $env:TEMP 'mbu-menu.ps1'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u = 'https://raw.githubusercontent.com/CoelhoFZ/Minecraft-Bedrock-Free/main'; if ($env:MBU_BASE_URL) { $u = $env:MBU_BASE_URL.TrimEnd('/') }; Invoke-WebRequest -UseBasicParsing -Uri ($u + '/menu.ps1') -OutFile $m; $menuHashPin='4b27d5ca8c1369978108c46e554489499c00601dead02d1ab7375f0e472bf2d0'; $b=[IO.File]::ReadAllBytes($m); $c=New-Object System.Collections.Generic.List[byte]; foreach($x in $b){ if($x -ne 13){ $c.Add([byte]$x) } }; $sha=[System.Security.Cryptography.SHA256]::Create(); $h=[BitConverter]::ToString($sha.ComputeHash($c.ToArray())).Replace('-','').ToLowerInvariant(); $localOk = ($env:MBU_BASE_URL -and $env:MBU_EXTRA_HASH -and ($h -eq $env:MBU_EXTRA_HASH.ToLowerInvariant())); if(($h -ne $menuHashPin) -and (-not $localOk)){ Write-Host ''; Write-Host ('ERRO: o hash do menu.ps1 baixado nao confere com o esperado.') -ForegroundColor Red; Write-Host ('  Esperado: ' + $menuHashPin); Write-Host ('  Recebido: ' + $h); Write-Host 'Desconfie do link que usou: baixe o install.bat apenas do repositorio oficial (github.com/CoelhoFZ/Minecraft-Bedrock-Free).' -ForegroundColor Yellow; Read-Host 'Pressione Enter para fechar'; exit 1 }; & $m"
