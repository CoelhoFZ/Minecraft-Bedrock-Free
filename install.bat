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

rem ---- baixa e roda o menu interativo ----
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$m = Join-Path $env:TEMP 'mbu-menu.ps1'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/CoelhoFZ/Minecraft-Bedrock-Free/main/menu.ps1' -OutFile $m; & $m"
