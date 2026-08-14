# Minecraft Bedrock Unlocker

<p align="center">
  <img src="docs/logo.png" alt="Minecraft Bedrock Unlocker logo" width="128">
  <br>
  <a href="https://github.com/CoelhoFZ/MinecraftBedrockUnlocker/releases"><img alt="GitHub release" src="https://img.shields.io/github/v/release/CoelhoFZ/MinecraftBedrockUnlocker"></a>
  <img alt="Downloads" src="https://mbu-download-counter.xgobg2020.workers.dev/">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Windows%2010%2F11-blue">
  <img alt="License" src="https://img.shields.io/badge/license-GPLv3%20(scripts)-blue">
  <a href="https://buymeacoffee.com/coelhofz"><img alt="Buy Me a Coffee" src="https://img.shields.io/badge/Support-Buy%20Me%20a%20Coffee-FFDD00"></a>
</p>

Desbloqueie a versão completa do **Minecraft Bedrock Edition (GDK)** no
Windows 10/11.

**Funciona apenas com instalação via Xbox App** (NÃO a versão da Microsoft
Store).

> ⚠️ Projeto educacional. Apoie os desenvolvedores comprando o jogo.

## Instalação

1. Instale o Minecraft pelo **Xbox App** e abra uma vez.
2. Abra o **PowerShell** e rode:

```powershell
irm https://github.com/CoelhoFZ/MinecraftBedrockUnlocker/raw/main/i.ps1 | iex
```

3. O instalador abre o Minecraft automaticamente. O botão "Desbloquear Jogo Completo" some.

> Os scripts do instalador são **open source** (GPLv3). Apenas o binário do
> unlock (`release/winmm.dll`) é código fechado — veja [LICENSE](LICENSE).

Alternativa (manual): clone o repo e rode o `.\install.ps1`:

```powershell
git clone https://github.com/CoelhoFZ/MinecraftBedrockUnlocker
cd MinecraftBedrockUnlocker
.\install.ps1
```

O instalador localiza a pasta `Content` do jogo, fecha o jogo se estiver
aberto, faz backup de qualquer `winmm.dll` original (como `winmm.dll.orig`) e
instala o unlock. Artefatos antigos de versões anteriores são removidos.

Para remover o unlock depois, rode o instalador de novo e escolha **Remover
desbloqueio**. Para remoção manual (sem o menu), rode o `.\uninstall.ps1`.

## Auto-contido, sem downloads de terceiros

Nada é baixado de terceiros na instalação nem em runtime. O unlock é um
**binário de código fechado** distribuído neste repositório:

- `release/winmm.dll` — o único arquivo que o jogo precisa (um `winmm.dll`
  falso que é carregado pela ordem de busca de DLLs do app).

## Como funciona (visão geral)

O build GDK do Minecraft consulta uma API do Windows
(`xgameruntime!QueryApiImpl`) para saber se os entitlements de licença são
"owned". O `winmm.dll` distribuído intercepta essas consultas e responde
"owned", então o jogo roda como se estivesse comprado. Todo o resto (conta,
gamertag, perfil) continua real.

## Código fechado

Os binários são **código fechado** — o mecanismo do unlock não é publicado
aqui. Eles são endurecidos contra engenharia reversa:

- O payload real do unlock não existe como arquivo: é um **blob criptografado
  embutido dentro do `winmm.dll`**, mapeado manualmente em runtime por um
  loader custom (dois estágios criptografados, chaves por build).
- Zero strings reveladoras, zero import table do caminho do packer, zero
  símbolos/RTTI.
- Anti-debug (várias camadas), anti-tamper (checagens de integridade no load
  e um watchdog em runtime), anti-dump.

Veja `LICENSE` para os termos.

## Integridade do binário

`SHA256SUMS.txt` lista o hash esperado de `release/winmm.dll`. Verifique antes
de instalar:

```powershell
Get-FileHash .\release\winmm.dll -Algorithm SHA256
```

## Antivírus / SmartScreen

O binário do unlock é de **código fechado**, então o Windows Defender ou o
SmartScreen podem mostrar um aviso de falso positivo. Isso é esperado.
Verifique o binário antes de instalar usando o SHA-256 de `SHA256SUMS.txt`
(veja "Integridade do binário"). Rode o instalador apenas deste repositório.

## Apoie o projeto

Gostou do unlocker? Considere [me pagar um café](https://buymeacoffee.com/coelhofz) ☕ —
ajuda a manter o projeto vivo.

## 🚨 ALERTA DE GOLPE

Golpistas espalham **links falsos de "fix do unlocker"** em chats do Discord
usando URLs curtas e o padrão `irm <link-curto> | iex`. **Isso NÃO é este
projeto** — baixa um trojan de acesso remoto.

- A **única fonte oficial** é este repositório:
  `https://github.com/CoelhoFZ/MinecraftBedrockUnlocker`
- **NUNCA** rode `irm <qualquer coisa> | iex` vindo de link curto (bit.ly,
  tinyurl, …), outro domínio, DM do Discord ou servidor aleatório.
- O instalador oficial só copia os arquivos deste repositório.
