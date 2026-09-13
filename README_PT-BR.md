# Minecraft Bedrock Free

<p align="center">
  <img src="docs/logo.png" alt="Minecraft Bedrock Free logo" width="128">
  <br>
  <a href="https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases"><img alt="GitHub release" src="https://img.shields.io/github/v/release/CoelhoFZ/Minecraft-Bedrock-Free?style=for-the-badge"></a>
  <img alt="Downloads" src="https://mbu-download-counter.xgobg2020.workers.dev/?v=2">
  <img alt="License" src="https://img.shields.io/badge/license-GPLv3%20(scripts)-blue?style=for-the-badge">
  <a href="https://buymeacoffee.com/coelhofz"><img alt="Buy Me a Coffee" src="https://img.shields.io/badge/Support-Buy%20Me%20a%20Coffee-FFDD00?style=for-the-badge"></a>
  <a href="https://discord.gg/u3S4gFgK6M"><img alt="Discord" src="https://img.shields.io/badge/Discord-Join%20community-5865F2?style=for-the-badge&logo=discord&logoColor=white"></a>
</p>

Desbloqueie a versão completa do **Minecraft Bedrock Edition (GDK)** no
Windows 10/11.

**Funciona com instalações via Xbox App (GDK) e Microsoft Store** no
Windows 10/11.

> ⚠️ Projeto educacional. Apoie os desenvolvedores comprando o jogo.

## Requisitos

- **Apenas o build oficial.** Funciona exclusivamente com o build oficial da
  **Microsoft Store** ou do **Xbox App** do Minecraft Bedrock para Windows.
  NÃO funciona com launchers de terceiros nem seletor de versão (eles não usam
  a API de licença GDK que o unlock intercepta).
- **Apenas a versão atual.** Compilado e testado contra a versão mais recente.
  A Microsoft não permite instalar versões antigas, e este projeto não fornece
  nenhuma.
> **Windows on ARM:** esta release distribui apenas o build x64. O build nativo
> ARM64 esta sendo recompilado e voltara em uma release futura. Reporte
> problemas com o prefixo `[ARM64]` se estiver em ARM.

- NÃO copie o `winmm.dll` para outro launcher/pasta. Ele só desbloqueia o
  build oficial e pode quebrar outros launchers.

## Instalação

1. Instale o Minecraft pelo **Xbox App** ou pela **Microsoft Store** e abra uma vez.
2. Abra o **PowerShell** e rode:

```powershell
irm https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/raw/main/i.ps1 | iex
```

O arquivo é **`i.ps1`** (a letra **i**, como em instalador), **não** `e.ps1`.
Um erro de digitação como `.../raw/main/e.ps1 | iex` falha com erro de conexão
(`A solicitação foi anulada`) porque esse arquivo não existe.

3. O instalador abre o Minecraft automaticamente. O botão "Desbloquear Jogo Completo" some.

> Os scripts do instalador são **open source** (GPLv3). Apenas o binário do
> unlock (`release/winmm.dll`) é código fechado - veja [LICENSE](LICENSE).

O instalador localiza a pasta `Content` do jogo, fecha o jogo se estiver
aberto, faz backup de qualquer `winmm.dll` original (como `winmm.dll.orig`) e
instala o desbloqueio. O `winmm.dll` que já estava lá fica guardado durante a
troca e volta ao lugar se algo der errado, então uma instalação que falha nunca
deixa o jogo sem arquivo funcional. Artefatos antigos de versões anteriores são
removidos.

Para remover o unlock depois, rode o instalador de novo e escolha **Remover
desbloqueio**. Para remoção manual (sem o menu), baixe o `uninstall.ps1`
(<https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/raw/main/uninstall.ps1>)
e rode em um PowerShell elevado.

## Auto-contido, sem downloads de terceiros

Nada é baixado de terceiros na instalação nem em runtime. O unlock é um
**binário de código fechado** distribuído neste repositório:

- `release/winmm.dll` - o único arquivo que o jogo precisa (um `winmm.dll`
  falso que é carregado pela ordem de busca de DLLs do app).

## Como funciona (visão geral)

O build GDK do Minecraft consulta uma API do Windows
(`xgameruntime!QueryApiImpl`) para saber se os entitlements de licença são
"owned". O `winmm.dll` distribuído intercepta essas consultas e responde
"owned", então o jogo roda como se estivesse comprado. Todo o resto (conta,
gamertag, perfil) continua real.

## Código fechado

Os binários são **código fechado** - o mecanismo do unlock não é publicado
aqui. Veja `LICENSE` para os termos.

## Integridade do binário

`SHA256SUMS.txt` lista o hash esperado de `release/winmm.dll`. Verifique antes
de instalar:

```powershell
Get-FileHash .\release\winmm.dll -Algorithm SHA256
```

## Antivírus

Alguns antivírus marcam o binário do unlock como falso positivo. Isso é
esperado para um unlocker. Veja [Falsos positivos de antivírus](docs/antivirus-false-positives.md).

## Variaveis de ambiente (avancado)

| Variavel | Usada por | O que faz |
|---|---|---|
| `MBU_LANG` | `menu.ps1` | Forca o idioma do menu (`pt`, `en`, `es`, `fr`, `zh`, `hi`, `ar`, `ru`) em vez de detectar automaticamente pelo sistema. |
| `MBU_BASE_URL` | `i.ps1`, `install.bat`, `menu.ps1` | Aponta o instalador para outro servidor (forks, VM de teste). As verificacoes de hash continuam valendo. |
| `MBU_EXTRA_HASH` | `install.bat` | Junto com `MBU_BASE_URL`: permite que um `menu.ps1` modificado localmente (hash diferente) passe na verificacao em ambiente de teste. Nunca defina isso na maquina do dia a dia. |
| `MBU_REPORT_URL` | `menu.ps1` | Sobrescreve o endpoint de report de falha (Cloudflare Worker), para apontar testes para um mock local. Nunca defina na maquina do dia a dia. |
| `MBU_NO_LOOP` | `menu.ps1` | Defina como `1` para carregar as funcoes do menu sem entrar no loop interativo (dot-source em testes). |

## Compatibilidade de versao do jogo

O menu baixa o `tested-versions.json` deste repositorio e **bloqueia a
instalacao** quando a sua versao do Minecraft **ainda nao foi testada** com
este unlocker. Atualize o jogo pela Microsoft Store para a versao atual e
rode o instalador de novo.
Se o seu jogo estiver **mais novo** que a lista testada (a Store atualizou
depois desta release), atualizar nao resolve - o suporte a essa build tem que
vir deste projeto. Acompanhe a pagina de
[Releases](https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases) ou o
[Discord](https://discord.gg/u3S4gFgK6M).

Quando algo falha - um erro do instalador, o Minecraft nao abrir depois da
instalacao, ou o jogo crashar logo apos abrir - o menu pergunta se voce quer
enviar um relatorio de diagnostico ao desenvolvedor. Confirme com **S** e o
relatorio chega automaticamente: sem copiar, sem colar. O relatorio nunca e
mostrado na tela e nunca sai da sua maquina sem a sua confirmacao.

## Solução de problemas

Problemas ao instalar ou abrir o jogo? Veja [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Apoie o projeto

Gostou do unlocker? Considere [me pagar um café](https://buymeacoffee.com/coelhofz) ☕ -
ajuda a manter o projeto vivo.

## 🚨 ALERTA DE GOLPE

Golpistas espalham **links falsos de "fix do unlocker"** em chats do Discord
usando URLs curtas e o padrão `irm <link-curto> | iex`. **Isso NÃO é este
projeto** - baixa um trojan de acesso remoto.

- A **única fonte oficial** é este repositório:
  `https://github.com/CoelhoFZ/Minecraft-Bedrock-Free`
- **NUNCA** rode `irm <qualquer coisa> | iex` vindo de link curto (bit.ly,
  tinyurl, …), outro domínio, DM do Discord ou servidor aleatório.
- O instalador oficial só copia os arquivos deste repositório.
