
$ErrorActionPreference = 'Stop'
$Script:Version = '4.9.11'
$base = if ($env:MBU_BASE_URL) {
    $env:MBU_BASE_URL.TrimEnd('/')
} else {
    'https://raw.githubusercontent.com/CoelhoFZ/Minecraft-Bedrock-Free/main'
}
$expectedHash = '9371baf3b6ad442f2694e62449f0991805fa941e0281cbabcec3585d54fbd299'
$knownUnlockHashes = @(
    'f387b5f6b9717800a8511d554d37023472e4f2dbd60bc74a44205e640ce02d7e',
    'f7b1408c36590abbfcb5310cf98c1efb1fa16f3a54a9387df56b1441de90335b',
    '86689c9724be7f391ba9bd1f4ef8dddaa73baec0b76b9c73bebef89f37b76e97'
)

$expectedHashArm64 = '7a74d63cec0654c50044c55c144dc59f710ded8ccada4f0bd1dc28f557f13f46'
$knownUnlockHashesArm64 = @(
    '7a74d63cec0654c50044c55c144dc59f710ded8ccada4f0bd1dc28f557f13f46'
)
$unlockBuildLabels = @{
    '9371baf3b6ad442f2694e62449f0991805fa941e0281cbabcec3585d54fbd299' = 'v4.9.11'
    'f387b5f6b9717800a8511d554d37023472e4f2dbd60bc74a44205e640ce02d7e' = 'v4.8.0'
    'f7b1408c36590abbfcb5310cf98c1efb1fa16f3a54a9387df56b1441de90335b' = 'v4.4.1'
    '86689c9724be7f391ba9bd1f4ef8dddaa73baec0b76b9c73bebef89f37b76e97' = 'v4.3.0'
}
$unlockBuildLabelsArm64 = @{
    '7a74d63cec0654c50044c55c144dc59f710ded8ccada4f0bd1dc28f557f13f46' = 'v4.4.2'
}
$Script:MbuTempDir = $null
function Get-TempDir {
    if ($Script:MbuTempDir) {
        return $Script:MbuTempDir
    }
    $cands = New-Object System.Collections.Generic.List[string]
    try {
        if ($env:TEMP) {
            $cands.Add([string]$env:TEMP)
        }
    } catch { }
    try {
        if ($env:TMP) {
            $cands.Add([string]$env:TMP)
        }
    } catch { }
    try {
        if ($env:LOCALAPPDATA) {
            $cands.Add((Join-Path $env:LOCALAPPDATA 'Temp'))
        }
    } catch { }
    try {
        if ($env:USERPROFILE) {
            $cands.Add((Join-Path $env:USERPROFILE 'AppData\Local\Temp'))
        }
    } catch { }
    try {
        if ($env:SystemRoot) {
            $cands.Add((Join-Path $env:SystemRoot 'Temp'))
        }
    } catch { }
    try {
        $cands.Add([IO.Path]::GetTempPath())
    } catch { }
    $longPaths = New-Object System.Collections.Generic.List[string]
    $shortPaths = New-Object System.Collections.Generic.List[string]
    foreach ($cand in $cands) {
        try {
            $candTxt = [string]$cand
        } catch {
            $candTxt = ''
        }
        if ($candTxt -and ($candTxt -match '~\d')) {
            $shortPaths.Add($candTxt)
        } else {
            $longPaths.Add($candTxt)
        }
    }
    $cands = @($longPaths) + @($shortPaths)
    foreach ($c in $cands) {
        try {
            if (-not $c -or -not $c.Trim()) {
                continue
            }
            $c = $c.Trim()
            if (-not (Test-Path -LiteralPath $c -PathType Container)) {
                continue
            }
            $probe = Join-Path $c ('.mbu-tprobe-' + [guid]::NewGuid().ToString('N') + '.tmp')
            $fs = [IO.File]::Open($probe, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $fs.Dispose()
            [IO.File]::Delete($probe)
            $Script:MbuTempDir = $c.TrimEnd('\')
            return $Script:MbuTempDir
        } catch { }
    }
    try {
        $Script:MbuTempDir = ([IO.Path]::GetTempPath()).TrimEnd('\')
    } catch {
        $Script:MbuTempDir = $env:TEMP
    }
    return $Script:MbuTempDir
}

$cacheDir = Join-Path $env:LOCALAPPDATA 'mbu-cache'
$Script:TestedVersionData = $null
$Script:AclDiag = $null
$Script:SwapPrevDll = $null
$Script:SwapDiag = @()
$Script:DefenderExclAttempted = @()
$Script:DefenderExclEffective = @()
$Script:ThirdPartyAv = @()
$Script:DownloadDiag = $null
$urls = @{
    'troubleshooting' = 'https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/blob/main/TROUBLESHOOTING.md'
    'discord'         = 'https://discord.gg/u3S4gFgK6M'
    'donate'          = 'https://buymeacoffee.com/coelhofz'
}

$reportEndpoint = if ($env:MBU_REPORT_URL) {
    $env:MBU_REPORT_URL.TrimEnd('/')
} else {
    'https://mbu-error-worker.xgobg2020.workers.dev/report'
}
function Get-PeMachineType {
    param([string]$Path)
    try {
        if (-not (Test-Path $Path)) {
            return 0
        }
        $fs = [IO.File]::OpenRead($Path)
        try {
            $br = New-Object IO.BinaryReader($fs)
            $fs.Position = 0x3C
            $peOff = $br.ReadInt32()
            $fs.Position = $peOff + 4
            return [UInt16]$br.ReadUInt16()
        } finally {
            $fs.Dispose()
        }
    } catch {
        return 0
    }
}

function Resolve-MbuLanguage {
    $candidates = New-Object System.Collections.Generic.List[string]
    try {
        if ($env:MBU_LANG) {
            $candidates.Add([string]$env:MBU_LANG)
        }
    } catch { }
    try {
        $candidates.Add((Get-UICulture).Name)
    } catch { }
    try {
        $candidates.Add((Get-Culture).Name)
    } catch { }
    try {
        $userLanguages = Get-WinUserLanguageList -ErrorAction SilentlyContinue
        foreach ($language in $userLanguages) {
            try {
                if ($language.LanguageTag) {
                    $candidates.Add([string]$language.LanguageTag)
                }
            } catch { }
            try {
                if ($language.EnglishName) {
                    $candidates.Add([string]$language.EnglishName)
                }
            } catch { }
            try {
                if ($language.NativeName) {
                    $candidates.Add([string]$language.NativeName)
                }
            } catch { }
        }
    } catch { }
    foreach ($regPath in @('HKCU:\Control Panel\International', 'HKCU:\Control Panel\Desktop', 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language')) {
        try {
            $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            foreach ($prop in @('LocaleName', 'sLanguage', 'Locale', 'PreferredUILanguages')) {
                $value = $props.$prop
                if ($value -is [array]) {
                    foreach ($item in $value) {
                        if ($item) {
                            $candidates.Add([string]$item)
                        }
                    }
                } elseif ($value) {
                    $candidates.Add([string]$value)
                }
            }
        } catch { }
    }
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        $value = $candidate.Trim().ToLowerInvariant()
        switch -Wildcard ($value) {
            'en*' {
                return 'en'
            }
            '*english*' {
                return 'en'
            }
            'pt*' {
                return 'pt'
            }
            '*portugu*' {
                return 'pt'
            }
            '*brasil*' {
                return 'pt'
            }
            '*brazil*' {
                return 'pt'
            }
            'zh*' {
                return 'zh'
            }
            '*chinese*' {
                return 'zh'
            }
            'hi*' {
                return 'hi'
            }
            '*hindi*' {
                return 'hi'
            }
            'es*' {
                return 'es'
            }
            '*spanish*' {
                return 'es'
            }
            '*espanol*' {
                return 'es'
            }
            '*español*' {
                return 'es'
            }
            'fr*' {
                return 'fr'
            }
            '*french*' {
                return 'fr'
            }
            '*francais*' {
                return 'fr'
            }
            '*français*' {
                return 'fr'
            }
            'ar*' {
                return 'ar'
            }
            '*arabic*' {
                return 'ar'
            }
            'ru*' {
                return 'ru'
            }
            '*russian*' {
                return 'ru'
            }
        }
    }
    return 'en'
}

$Script:Lang = Resolve-MbuLanguage

$Script:PT = @{
    'greet_morning'      = 'Bom dia'
    'greet_afternoon'    = 'Boa tarde'
    'greet_evening'      = 'Boa noite'
    'banner_build_note'  = 'Suporte apenas ao build OFICIAL (Store/Xbox App) na versao ATUAL. Launchers de terceiros e versoes antigas NAO sao suportados.'
    'err_content_not_found' = 'Content do Minecraft nao encontrado. Instale o Minecraft pelo Xbox App ou pela Microsoft Store e tente de novo.'
    'err_package_incomplete' = 'Pacote do Minecraft encontrado, mas o executavel esta faltando. Reinstale o Minecraft e tente de novo.'
    'closing_mc'         = 'Fechando Minecraft...'
    'downloading_bin'    = 'Baixando o binario (winmm.dll)...'
    'retry_download'     = 'Falha temporaria de rede no download (ex.: 503 do servidor). Tentando novamente ({0}/{1})...'
    'err_download_unavailable' = 'Nao foi possivel baixar o winmm.dll: o servidor de download (GitHub) respondeu com erro temporario (503/502/504) varias vezes seguidas. Nao e um problema do instalador. Verifique sua conexao e rode o instalador de novo em alguns minutos.'
    'err_download_failed' = 'Nao foi possivel baixar o winmm.dll. Verifique sua conexao com a internet e rode o instalador de novo. Detalhe: {0}'
    'err_hash_invalid'   = 'Hash do winmm.dll invalido: {0}'
    'err_acl'            = 'Nao foi possivel tomar posse da pasta do Minecraft. Rode como administrador.'
    'err_copy_corrupt'   = 'Falha ao copiar winmm.dll (copia corrompida/bloqueada). Verifique se o antivirus nao bloqueou e tente de novo.'
    'err_replace'        = 'Nao foi possivel substituir winmm.dll (Access denied ou arquivo em uso). Feche o Minecraft e rode como administrador.'
    'err_av_quarantine'  = 'O winmm.dll foi corrompido/removido pelo antivirus logo apos a copia. Adicione uma exclusao para a pasta do Minecraft e rode de novo.'
    'av_cfa_hint'        = 'Atencao: a protecao de pastas do Windows (Acesso controlado a pastas / Ransomware protection) tambem esta LIGADA, e ela NAO usa as exclusoes do antivirus - ela tem lista propria de apps permitidos. Libere o instalador/PowerShell e o Minecraft.Windows.exe nela (ou desligue-a temporariamente) e rode o instalador de novo.'
    'err_av_blocked'     = 'O antivirus bloqueou o download do winmm.dll mesmo com a exclusao automatica. Abra a Seguranca do Windows, va em Protecao contra virus e ameacas, abra o Historico de protecao, localize o winmm.dll bloqueado e escolha Permitir ou Restaurar. Depois adicione manualmente as exclusoes para: {0}. Se voce usa outro antivirus, adicione as mesmas exclusoes nele. Rode o instalador de novo.'
    'av_retrying'        = 'O antivirus pode ter removido o arquivo baixado. Tentando novamente ({0}/{1})...'
    'warn_third_party_av' = 'Atencao: antivirus de terceiros ativo ({0}). Ele pode bloquear a copia do winmm.dll para a pasta do Minecraft. Se a instalacao falhar, adicione a pasta do Minecraft nas exclusoes (ou pastas protegidas) desse antivirus e rode de novo.'
    'err_write_blocked'  = 'Acesso negado ao gravar o winmm.dll na pasta do Minecraft, mesmo com a pasta liberada como administrador. Isso quase sempre e um antivirus bloqueando a gravacao. Antivirus detectado: {0}. Adicione a pasta do Minecraft nas exclusoes (ou pastas protegidas) desse antivirus e rode o instalador de novo.'
    'av_generic_name'    = 'um antivirus ou protecao de pasta'
    'av_exclusion_ok'    = 'Exclusao do Windows Defender adicionada para: {0}'
    'av_exclusion_fail'  = 'Nao foi possivel adicionar a exclusao do Windows Defender automaticamente. Rode como administrador ou adicione manualmente: {0}'
    'backup_orig'        = 'Backup do winmm original em winmm.dll.orig'
    'install_ok'         = 'OK - unlock instalado.'
    'restored_ok'        = 'winmm original restaurado.'
    'removed_ok'         = 'winmm.dll removido (o jogo usara o do sistema).'
    'unlock_removed'     = 'Unlock removido.'
    'nothing_to_restore' = 'O desbloqueio nao esta instalado (nada a restaurar).'
    'mc_started'         = 'Minecraft iniciado.'
    'mc_start_failed'    = 'Nao foi possivel iniciar o Minecraft automaticamente. Abra pelo menu Iniciar.'
    'state_unlocked'     = 'O Minecraft ja esta DESBLOQUEADO.'
    'state_unlocked_hint'= 'Se quiser, escolha [1] para remover o desbloqueio e voltar a Trial.'
    'state_trial'        = 'O Minecraft esta na versao TRIAL.'
    'state_trial_hint'   = 'Escolha [1] para desbloquear o jogo completo.'
    'menu_title'         = 'Opcoes disponiveis'
    'menu_1_install'     = 'Instalar desbloqueio'
    'menu_1_remove'      = 'Remover desbloqueio (voltar a Trial)'
    'menu_2_reinstall'   = 'Reinstalar desbloqueio'
    'menu_0'             = 'Sair'
    'choose_option'      = 'Escolha uma opcao'
    'invalid_option'     = 'Opcao invalida.'
    'press_enter'        = 'Pressione ENTER para continuar'
    'arch_line'          = 'Build do jogo detectado: {0} (Machine={1})'
    'arch_unknown'       = 'Nao foi possivel ler o build do jogo no executavel, assumindo x64.'
    'arm64_detected'     = '[ARM64] PC Windows on ARM detectado: usando o unlocker nativo ARM64 (BETA).'
    'arm64_no_release'   = '[ARM64] O build ARM64 ainda nao foi publicado nesta release.'
    'arm64_hash_skipped' = '[ARM64] Verificacao de hash indisponivel nesta fase beta.'
    'track_releases'     = 'Acompanhe novos releases em {0}'
    'state_unlocked_v'   = 'O Minecraft ja esta DESBLOQUEADO ({0}).'
    'state_older_hint'   = 'O unlock instalado ({0}) e mais antigo que este menu ({1}) - use [2] para atualizar.'
    'tested_warning'     = 'Aviso: a versao do jogo {0} ainda NAO foi testada com este unlocker. Se algo falhar, reporte no Discord.'
    'gate_untested'      = 'Instalacao BLOQUEADA: a versao do jogo {0} nao foi testada com este unlocker e provavelmente nao funcionaria.'
    'gate_untested_hint' = 'Atualize o Minecraft pela Microsoft Store para a versao suportada e rode o instalador de novo.'
    'cache_used'         = 'Sem internet: usando copia local validada do binario ({0}).'
    'cache_saved'        = 'Copia local salva para reinstalacao offline: {0}'
    'menu_4_trouble'     = 'Abrir guia de problemas (web)'
    'menu_5_discord'     = 'Abrir Discord da comunidade'
    'menu_6_bmc'         = 'Apoiar o projeto (Buy Me a Coffee)'
    'diag_title'         = 'Relatorio de diagnostico - Minecraft Bedrock Free v{0}'
    'diag_os'            = 'Sistema'
    'diag_ps'            = 'PowerShell'
    'diag_admin'         = 'Administrador'
    'diag_yes'           = 'sim'
    'diag_no'            = 'nao'
    'diag_content'       = 'Pasta Content'
    'diag_source'        = 'Origem da instalacao'
    'diag_source_store'  = 'Microsoft Store (UWP)'
    'diag_source_gdk'    = 'Xbox App (GDK)'
    'diag_source_unknown'= 'desconhecida'
    'diag_game_version'  = 'Versao do jogo'
    'diag_game_arch'     = 'Arquitetura do jogo'
    'diag_unlock'        = 'Unlock instalado'
    'diag_unlock_none'   = 'nao instalado (Trial)'
    'diag_tested'        = 'Versao do jogo vs versoes testadas'
    'diag_tested_ok'     = 'OK - coberta por tested-versions.json'
    'diag_tested_bad'    = 'ATENCAO - fora da lista de testadas'
    'diag_tested_unknown'= 'indisponivel (sem internet ou sem dados)'
    'diag_av'            = 'Exclusoes do Defender (mbu/Minecraft)'
    'diag_av_none'       = 'nenhuma encontrada'
    'diag_av_unavail'    = 'indisponivel (nao foi possivel consultar o Defender)'
    'diag_cache'         = 'Cache offline do binario'
    'diag_cache_ok'      = 'presente e valido ({0})'
    'diag_cache_bad'     = 'presente MAS com hash diferente do binario atual'
    'diag_cache_none'    = 'ausente (sera criada na proxima instalacao)'
    'install_content_dir'   = 'Pasta Content: {0}'
    'diag_winmm_hash'       = 'hash do winmm'
    'diag_machine_unreadable' = 'ilegivel'
    'diag_cand_label'       = '[candidato]'
    'diag_cand_present'     = 'winmm.dll presente'
    'diag_cand_absent'      = 'sem winmm.dll'
    'diag_cand_used'        = 'pasta usada'
    'diag_reason'           = 'Motivo'
    'diag_date'             = 'Data do relatorio'
    'diag_os_arch'          = 'Arquitetura do SO'
    'diag_cpu'              = 'CPU'
    'diag_pkg'              = 'Pacote da Store'
    'diag_defender'         = 'Defender (tempo real/engine/assinatura)'
    'diag_defender_none'    = 'indisponivel'
    'diag_sac'              = 'Smart App Control'
    'diag_sac_off'          = 'desligado'
    'diag_sac_on'           = 'LIGADO (bloqueia o unlocker)'
    'diag_sac_eval'         = 'avaliacao (tambem bloqueia)'
    'diag_sac_unknown'      = 'indisponivel'
    'sac_warn_title'        = 'Smart App Control esta LIGADO.'
    'sac_warn_body'         = 'O Smart App Control bloqueia arquivos sem assinatura digital. O winmm.dll do desbloqueio nao tem assinatura, entao com ele ligado o Minecraft nao abre desbloqueado (continua na Trial). Desligue o Smart App Control antes de instalar.'
    'sac_ask'               = 'Deseja abrir as configuracoes do Smart App Control para desligar agora? (S para sim, N para nao)'
    'sac_opened'            = 'Configuracoes do Smart App Control abertas. Desligue o Smart App Control e rode o instalador de novo.'
    'sac_open_fail'         = 'Nao foi possivel abrir as configuracoes. Abra manualmente: Seguranca do Windows > App e navegador > Smart App Control settings.'
    'sac_continue'          = 'Continuando a instalacao mesmo assim. Se o jogo nao abrir desbloqueado, desligue o Smart App Control e tente de novo.'
    'sac_ask_off'           = 'Deseja desligar o Smart App Control agora? (S para sim, N para nao)'
    'sac_off_ok'            = 'Smart App Control desligado. Continuando a instalacao...'
    'sac_off_reboot_hint'   = 'O Windows pode precisar de um reboot para aplicar. Se o jogo nao abrir, reinicie o PC e rode o instalador de novo.'
    'sac_off_need_reboot'   = 'Nao foi possivel aplicar o desligamento do Smart App Control. Reinicie o PC e rode o instalador de novo.'
    'sac_off_write_fail'    = 'Nao foi possivel GRAVAR a chave do Smart App Control (acesso negado). O reboot NAO resolve isso. Verifique se o antivirus/politica nao protege o registro, rode como administrador e tente de novo - ou desligue pela Seguranca do Windows: App e navegador > Smart App Control settings.'
    'sac_skip_launch'       = 'O Smart App Control foi desligado, mas o Windows so libera o Minecraft depois de reiniciar. O jogo NAO foi aberto. Reinicie o PC e rode o instalador de novo.'
    'err_acl_admin'         = 'A pasta do Minecraft segue bloqueada para escrita MESMO com permissao de administrador aplicada. Isso normalmente e causado por um antivirus de terceiros (protecao anti-ransomware ou pasta protegida) ou uma politica de seguranca. Verifique o antivirus instalado, permita/exclua a pasta do Minecraft nele e rode o instalador de novo.'
    'diag_avs'              = 'Antivirus registrados (SecurityCenter2)'
    'diag_avs_none'         = 'nenhum produto registrado'
    'diag_avs_unavail'      = 'indisponivel'
    'diag_cfa'              = 'Acesso controlado a pastas (Defender)'
    'diag_cfa_on'           = 'LIGADO (bloqueia escrita de apps nao confiaveis)'
    'diag_cfa_off'          = 'desligado'
    'diag_cfa_unavail'      = 'indisponivel'
    'diag_acl_deny_removed' = 'deny ACEs removidos'
    'diag_search'           = 'Estado da busca por Content do Minecraft'
    'diag_search_pkg'       = 'Pacote Microsoft.MinecraftUWP'
    'diag_search_noappx'    = 'nenhum pacote registrado'
    'diag_search_proc'      = 'Processo Minecraft.Windows'
    'diag_search_proc_none' = 'nao esta rodando'
    'diag_probe_missing'    = 'nao existe'
    'diag_probe_noexe'      = 'existe, sem Minecraft.Windows.exe'
    'report_trigger_install_error' = 'O instalador encontrou um erro.'
    'report_trigger_start_failed'  = 'O Minecraft nao abriu apos a instalacao.'
    'report_trigger_game_crashed'  = 'O Minecraft abriu e fechou logo em seguida.'
    'corrupt_winmm_found'   = 'Foi detectado um winmm.dll corrompido ou incompativel no jogo (possivel causa do erro Bad Image 0xc0e90007).'
    'report_ask'            = 'Deseja enviar o relatorio para o desenvolvedor para ajuda-lo a corrigir o problema? (S para sim, N para nao)'
    'report_sent'           = 'Relatorio enviado ao desenvolvedor. Obrigado!'
    'report_not_sent'       = 'Ok, relatorio nao enviado.'
    'report_send_fail'      = 'Nao foi possivel enviar o relatorio automaticamente.'
    'report_av_removed'     = 'O winmm.dll foi removido ou corrompido logo apos a instalacao (antivirus?).'
    'report_checking'       = 'Verificando se o Minecraft abriu corretamente...'
}

$Script:I18N = @{
    'err_acl' = @{
        en='Could not take ownership of the Minecraft folder. Run as administrator.'
        es='No se pudo tomar posesion de la carpeta de Minecraft. Ejecuta como administrador.'
        zh='无法取得 Minecraft 文件夹的所有权。请以管理员身份运行。'
        hi='Minecraft फ़ोल्डर का स्वामित्व नहीं लिया जा सका। व्यवस्थापक के रूप में चलाएँ।'
        fr='Impossible de prendre possession du dossier Minecraft. Exécutez en tant qu''administrateur.'
        ar='تعذّر الحصول على ملكية مجلد Minecraft. شغّل كمسؤول.'
        ru='Не удалось получить права на папку Minecraft. Запустите от имени администратора.'
    }
    'err_copy_corrupt' = @{
        en='Failed to copy winmm.dll (corrupted/blocked copy). Check if your antivirus blocked it and try again.'
        es='Error al copiar winmm.dll (copia corrupta/bloqueada). Comprueba si tu antivirus lo bloqueo e intentalo de nuevo.'
        zh='复制 winmm.dll 失败（副本损坏或受阻）。请检查杀毒软件是否阻止，然后重试。'
        hi='winmm.dll की प्रतिलिपि विफल (दूषित/अवरुद्ध प्रतिलिपि)। जाँचें कि क्या आपके एंटीवायरस ने इसे रोका और फिर से प्रयास करें।'
        fr='Échec de la copie de winmm.dll (copie corrompue/bloquée). Vérifiez que votre antivirus ne l''a pas bloquée et réessayez.'
        ar='فشل نسخ winmm.dll (نسخة تالفة/محظورة). تحقق مما إذا كان برنامج مكافحة الفيروسات قد حظرها وحاول مرة أخرى.'
        ru='Не удалось скопировать winmm.dll (копия повреждена/заблокирована). Проверьте, не заблокировал ли его антивирус, и попробуйте снова.'
    }
    'err_replace' = @{
        en='Could not replace winmm.dll (access denied or file in use). Close Minecraft and run as administrator.'
        es='No se pudo reemplazar winmm.dll (acceso denegado o archivo en uso). Cierra Minecraft y ejecuta como administrador.'
        zh='无法替换 winmm.dll（访问被拒绝或文件被占用）。请关闭 Minecraft 并以管理员身份运行。'
        hi='winmm.dll को प्रतिस्थापित नहीं किया जा सका (पहुँच अस्वीकृत या फ़ाइल उपयोग में)। Minecraft बंद करें और व्यवस्थापक के रूप में चलाएँ।'
        fr='Impossible de remplacer winmm.dll (accès refusé ou fichier utilisé). Fermez Minecraft et exécutez en tant qu''administrateur.'
        ar='تعذّر استبدال winmm.dll (تم رفض الوصول أو الملف قيد الاستخدام). أغلق Minecraft وشغّل كمسؤول.'
        ru='Не удалось заменить winmm.dll (отказано в доступе или файл используется). Закройте Minecraft и запустите от имени администратора.'
    }
    'err_av_quarantine' = @{
        en='winmm.dll was corrupted/removed by antivirus right after copying. Add an exclusion for the Minecraft folder and run again.'
        es='winmm.dll fue corrompido/eliminado por el antivirus justo despues de copiarlo. Anade una exclusion para la carpeta de Minecraft y vuelve a intentarlo.'
        zh='winmm.dll 刚复制完就被杀毒软件破坏/删除。请为 Minecraft 文件夹添加排除项后重新运行。'
        hi='प्रतिलिपि के तुरंत बाद एंटीवायरस ने winmm.dll को दूषित/हटा दिया। Minecraft फ़ोल्डर के लिए बहिष्करण जोड़ें और फिर से चलाएँ।'
        fr='winmm.dll a été corrompu/supprimé par l''antivirus juste après la copie. Ajoutez une exclusion pour le dossier Minecraft et relancez.'
        ar='تم إتلاف/حذف winmm.dll بواسطة مكافح الفيروسات بعد النسخ مباشرة. أضف استثناءً لمجلد Minecraft وأعد التشغيل.'
        ru='Антивирус повредил/удалил winmm.dll сразу после копирования. Добавьте исключение для папки Minecraft и запустите снова.'
    }
    'av_cfa_hint' = @{
        en='Note: Windows folder protection (Controlled folder access / Ransomware protection) is also ON, and path exclusions do NOT cover it - it has its own allowed-apps list. Allow the installer/PowerShell and Minecraft.Windows.exe there (or turn it off temporarily) and run the installer again.'
        es='Aviso: la proteccion de carpetas de Windows (Acceso controlado a carpetas / proteccion contra ransomware) tambien esta ACTIVADA, y las exclusiones de ruta no la cubren: tiene su propia lista de aplicaciones permitidas. Permite ahi el instalador/PowerShell y Minecraft.Windows.exe (o desactivala temporalmente) y vuelve a ejecutar el instalador.'
        fr='Remarque : la protection des dossiers Windows (Acces controle aux dossiers / protection contre les ranconlogiciels) est aussi ACTIVE, et les exclusions de chemin ne la couvrent pas : elle a sa propre liste d''applications autorisees. Autorisez-y l''installateur/PowerShell et Minecraft.Windows.exe (ou desactivez-la temporairement) puis relancez l''installateur.'
        zh='注意：Windows 文件夹保护（受控文件夹访问/勒索软件防护）也已开启，路径排除项并不覆盖它，它有独立的允许应用列表。请在其中允许安装程序/PowerShell 和 Minecraft.Windows.exe（或暂时关闭它），然后重新运行安装程序。'
        hi='ध्यान दें: Windows फ़ोल्डर सुरक्षा (नियंत्रित फ़ोल्डर एक्सेस / रैनसमवेयर सुरक्षा) भी चालू है और पथ बहिष्करण उसे नहीं कवर करते, उसकी अपनी अनुमत ऐप्स सूची है। वहाँ इंस्टॉलर/PowerShell और Minecraft.Windows.exe को अनुमति दें (या उसे अस्थायी रूप से बंद करें) और इंस्टॉलर फिर से चलाएँ।'
        ar='ملاحظة: حماية المجلدات في Windows (الوصول المتحكم به إلى المجلدات / الحماية من برامج الفدية) مفعّلة أيضًا، واستثناءات المسار لا تغطيها، فلديها قائمة تطبيقات مسموح بها خاصة. اسمح هناك للمثبّت/PowerShell ولـ Minecraft.Windows.exe (أو أوقفها مؤقتًا) ثم شغّل المثبّت مرة أخرى.'
        ru='Примечание: защита папок Windows (контролируемый доступ к папкам / защита от программ-вымогателей) также ВКЛЮЧЕНА, и исключения путей её не покрывают - у неё свой список разрешённых приложений. Разрешите там установщик/PowerShell и Minecraft.Windows.exe (или временно отключите её) и запустите установщик снова.'
    }
    'err_av_blocked' = @{
        en='Your antivirus blocked the downloaded winmm.dll even with the automatic exclusion. Open Windows Security, go to Virus & threat protection, open Protection history, find the blocked winmm.dll and choose Allow or Restore. Then add the exclusions manually for: {0}. If you use another antivirus, add the same exclusions there too. Run the installer again.'
        es='Tu antivirus bloqueo la descarga de winmm.dll incluso con la exclusion automatica. Abra Seguridad de Windows, vaya a Proteccion contra virus y amenazas, abra el Historial de proteccion, encuentre el winmm.dll bloqueado y elija Permitir o Restaurar. Despues anada manualmente las exclusiones para: {0}. Si usa otro antivirus, anada las mismas exclusiones alli tambien. Ejecute el instalador de nuevo.'
        zh='即使已自动添加排除项，杀毒软件仍阻止了下载的 winmm.dll。请打开 Windows 安全中心，进入“病毒和威胁防护”，打开“保护历史记录”，找到被阻止的 winmm.dll 并选择“允许”或“还原”。然后手动为以下路径添加排除项：{0}。如果你使用其他杀毒软件，请在其中添加相同的排除项。重新运行安装程序。'
        hi='स्वचालित बहिष्करण के बावजूद आपके एंटीवायरस ने डाउनलोड किए गए winmm.dll को अवरुद्ध कर दिया। Windows Security खोलें, Virus & threat protection पर जाएँ, Protection history खोलें, अवरुद्ध winmm.dll ढूँढें और Allow या Restore चुनें। फिर इनके लिए मैन्युअल रूप से बहिष्करण जोड़ें: {0}। यदि आप कोई अन्य एंटीवायरस उपयोग करते हैं, तो उसमें भी वही बहिष्करण जोड़ें। इंस्टॉलर फिर से चलाएँ।'
        fr='Votre antivirus a bloqué le winmm.dll téléchargé malgré l''exclusion automatique. Ouvrez Sécurité Windows, allez dans Protection contre les virus et menaces, ouvrez l''historique de protection, trouvez le winmm.dll bloqué et choisissez Autoriser ou Restaurer. Ajoutez ensuite manuellement les exclusions pour : {0}. Si vous utilisez un autre antivirus, ajoutez-y les mêmes exclusions. Relancez l''installateur.'
        ar='حظر مكافح الفيروسات لديك ملف winmm.dll الذي تم تنزيله حتى مع الاستثناء التلقائي. افتح أمان Windows، وانتقل إلى الحماية من الفيروسات والتهديدات، وافتح سجل الحماية، وابحث عن winmm.dll المحظور واختر السماح أو الاستعادة. ثم أضف الاستثناءات يدويًا لهذه المسارات: {0}. إذا كنت تستخدم مكافح فيروسات آخر، أضف نفس الاستثناءات إليه أيضًا. شغّل المثبّت مرة أخرى.'
        ru='Ваш антивирус заблокировал загруженный winmm.dll, даже несмотря на автоматическое исключение. Откройте «Безопасность Windows», перейдите в «Защита от вирусов и угроз», откройте «Журнал защиты», найдите заблокированный winmm.dll и выберите «Разрешить» или «Восстановить». Затем добавьте исключения вручную для: {0}. Если вы используете другой антивирус, добавьте такие же исключения и в него. Запустите установщик снова.'
    }
    'av_retrying' = @{
        en='The antivirus may have removed the downloaded file. Retrying ({0}/{1})...'
        es='El antivirus pudo haber eliminado el archivo descargado. Reintentando ({0}/{1})...'
        zh='杀毒软件可能已删除下载的文件。正在重试（{0}/{1}）...'
        hi='एंटीवायरस ने डाउनलोड की गई फ़ाइल हटा दी हो सकती है। पुनः प्रयास ({0}/{1})...'
        fr='L''antivirus a peut-être supprimé le fichier téléchargé. Nouvel essai ({0}/{1})...'
        ar='ربما حذف مكافح الفيروسات الملف الذي تم تنزيله. إعادة المحاولة ({0}/{1})...'
        ru='Возможно, антивирус удалил загруженный файл. Повторная попытка ({0}/{1})...'
    }
    'warn_third_party_av' = @{
        en='Warning: a third-party antivirus is active ({0}). It may block copying winmm.dll into the Minecraft folder. If the install fails, add the Minecraft folder to that antivirus exclusions (or protected folders) and run again.'
        es='Aviso: hay un antivirus de terceros activo ({0}). Puede bloquear la copia de winmm.dll en la carpeta de Minecraft. Si la instalacion falla, anade la carpeta de Minecraft a las exclusiones (o carpetas protegidas) de ese antivirus y vuelve a ejecutar.'
        fr='Attention : un antivirus tiers est actif ({0}). Il peut bloquer la copie de winmm.dll dans le dossier Minecraft. Si l''installation echoue, ajoutez le dossier Minecraft aux exclusions (ou dossiers proteges) de cet antivirus et relancez.'
        zh='警告：检测到第三方杀毒软件正在运行（{0}）。它可能会阻止将 winmm.dll 复制到 Minecraft 文件夹。如果安装失败，请把 Minecraft 文件夹加入该杀毒软件的排除项（或受保护文件夹）后重试。'
        hi='चेतावनी: थर्ड-पार्टी एंटीवायरस चालू है ({0})। यह Minecraft फ़ोल्डर में winmm.dll की प्रतिलिपि रोक सकता है। यदि इंस्टॉल विफल हो, तो उस एंटीवायरस के बहिष्करण (या संरक्षित फ़ोल्डर) में Minecraft फ़ोल्डर जोड़ें और फिर से चलाएँ।'
        ar='تنبيه: يوجد برنامج مكافحة فيروسات تابع لجهة خارجية قيد التشغيل ({0}). قد يمنع نسخ winmm.dll إلى مجلد Minecraft. إذا فشل التثبيت، فأضف مجلد Minecraft إلى الاستثناءات (أو المجلدات المحمية) في ذلك البرنامج وأعد التشغيل.'
        ru='Внимание: активен сторонний антивирус ({0}). Он может блокировать копирование winmm.dll в папку Minecraft. Если установка не удалась, добавьте папку Minecraft в исключения (или защищённые папки) этого антивируса и запустите снова.'
    }
    'err_write_blocked' = @{
        en='Access denied when writing winmm.dll into the Minecraft folder, even with the folder released as administrator. This is almost always an antivirus blocking the write. Detected antivirus: {0}. Add the Minecraft folder to that antivirus exclusions (or protected folders) and run the installer again.'
        es='Acceso denegado al escribir winmm.dll en la carpeta de Minecraft, incluso con la carpeta liberada como administrador. Casi siempre es un antivirus bloqueando la escritura. Antivirus detectado: {0}. Anade la carpeta de Minecraft a las exclusiones (o carpetas protegidas) de ese antivirus y vuelve a ejecutar el instalador.'
        fr='Acces refuse lors de l''ecriture de winmm.dll dans le dossier Minecraft, meme avec le dossier libere en administrateur. C''est presque toujours un antivirus qui bloque l''ecriture. Antivirus detecte : {0}. Ajoutez le dossier Minecraft aux exclusions (ou dossiers proteges) de cet antivirus et relancez l''installateur.'
        zh='写入 winmm.dll 到 Minecraft 文件夹时被拒绝访问，即使已以管理员身份释放该文件夹。这几乎总是杀毒软件阻止了写入。检测到的杀毒软件：{0}。请把 Minecraft 文件夹加入该杀毒软件的排除项（或受保护文件夹），然后重新运行安装程序。'
        hi='Minecraft फ़ोल्डर में winmm.dll लिखते समय पहुँच अस्वीकृत, फ़ोल्डर को व्यवस्थापक के रूप में मुक्त करने के बाद भी। यह लगभग हमेशा किसी एंटीवायरस द्वारा लेखन रोकने के कारण होता है। पाया गया एंटीवायरस: {0}। उस एंटीवायरस के बहिष्करण (या संरक्षित फ़ोल्डर) में Minecraft फ़ोल्डर जोड़ें और इंस्टॉलर फिर से चलाएँ।'
        ar='تم رفض الوصول عند كتابة winmm.dll في مجلد Minecraft، حتى بعد تحرير المجلد كمسؤول. هذا دائمًا تقريبًا بسبب برنامج مكافحة فيروسات يمنع الكتابة. البرنامج المكتشف: {0}. أضف مجلد Minecraft إلى الاستثناءات (أو المجلدات المحمية) في ذلك البرنامج وأعد تشغيل المثبّت.'
        ru='Отказано в доступе при записи winmm.dll в папку Minecraft, даже после освобождения папки от имени администратора. Почти всегда это антивирус блокирует запись. Обнаруженный антивирус: {0}. Добавьте папку Minecraft в исключения (или защищённые папки) этого антивируса и снова запустите установщик.'
    }
    'av_generic_name' = @{
        en='an antivirus or folder protection'
        es='un antivirus o proteccion de carpeta'
        fr='un antivirus ou une protection de dossier'
        zh='杀毒软件或文件夹保护'
        hi='कोई एंटीवायरस या फ़ोल्डर सुरक्षा'
        ar='برنامج مكافحة فيروسات أو حماية مجلدات'
        ru='антивирус или защита папок'
    }
    'av_exclusion_ok' = @{
        en='Windows Defender exclusion added for: {0}'
        pt='Exclusao do Windows Defender adicionada para: {0}'
        es='Exclusion de Windows Defender anadida para: {0}'
        zh='已为以下路径添加 Windows Defender 排除项：{0}'
        hi='इनके लिए Windows Defender बहिष्करण जोड़ा गया: {0}'
        fr='Exclusion Windows Defender ajoutée pour : {0}'
        ar='تمت إضافة استثناء Windows Defender لهذه المسارات: {0}'
        ru='Исключение Защитника Windows добавлено для: {0}'
    }
    'av_exclusion_fail' = @{
        en='Could not add the Windows Defender exclusion automatically. Run as administrator or add it manually: {0}'
        pt='Nao foi possivel adicionar a exclusao do Windows Defender automaticamente. Rode como administrador ou adicione manualmente: {0}'
        es='No se pudo anadir la exclusion de Windows Defender automaticamente. Ejecuta como administrador o anadela manualmente: {0}'
        zh='无法自动添加 Windows Defender 排除项。请以管理员身份运行或手动添加：{0}'
        hi='Windows Defender बहिष्करण स्वचालित रूप से नहीं जोड़ा जा सका। व्यवस्थापक के रूप में चलाएँ या मैन्युअल रूप से जोड़ें: {0}'
        fr='Impossible d''ajouter automatiquement l''exclusion Windows Defender. Exécutez en tant qu''administrateur ou ajoutez-la manuellement : {0}'
        ar='تعذّر إضافة استثناء Windows Defender تلقائيًا. شغّل كمسؤول أو أضفه يدويًا: {0}'
        ru='Не удалось автоматически добавить исключение Защитника Windows. Запустите от имени администратора или добавьте вручную: {0}'
    }
    'greet_morning' = @{
        en='Good morning'
        zh='早上好'
        hi='सुप्रभात'
        es='Buenos días'
        fr='Bonjour'
        ar='صباح الخير'
        ru='Доброе утро'
    }
    'greet_afternoon' = @{
        en='Good afternoon'
        zh='下午好'
        hi='शुभ दोपहर'
        es='Buenas tardes'
        fr='Bon après-midi'
        ar='مساء الخير'
        ru='Добрый день'
    }
    'greet_evening' = @{
        en='Good evening'
        zh='晚上好'
        hi='शुभ संध्या'
        es='Buenas noches'
        fr='Bonsoir'
        ar='مساء النور'
        ru='Добрый вечер'
    }
    'banner_build_note' = @{
        en='Official Store/Xbox App build (current version) only. No 3rd-party launchers or older versions.'
        zh='仅支持官方 Store/Xbox App 版本（当前版本）。不支持第三方启动器或旧版本。'
        hi='केवल आधिकारिक Store/Xbox App बिल्ड (वर्तमान संस्करण)। कोई तृतीय-पक्ष लॉन्चर या पुराना संस्करण नहीं।'
        es='Solo el build oficial de Store/Xbox App (version actual). Sin launchers de terceros ni versiones antiguas.'
        fr='Uniquement le build officiel Store/Xbox App (version actuelle). Pas de launchers tiers ni d''anciennes versions.'
        ar='فقط إصدار Store/Xbox App الرسمي (النسخة الحالية). لا توجد مشغلات طرف ثالث أو إصدارات قديمة.'
        ru='Только официальная сборка Store/Xbox App (текущая версия). Без сторонних лаунчеров и старых версий.'
    }
    'err_content_not_found' = @{
        en='Minecraft Content folder not found. Install Minecraft from the Xbox App or the Microsoft Store and try again.'
        zh='未找到 Minecraft Content 文件夹。请从 Xbox 应用安装 Minecraft。'
        hi='Minecraft Content फ़ोल्डर नहीं मिला। Xbox App से Minecraft इंस्टॉल करें।'
        es='No se encontró la carpeta Content de Minecraft. Instala Minecraft desde la Xbox App.'
        fr='Dossier Content de Minecraft introuvable. Installez Minecraft depuis l''application Xbox.'
        ar='لم يتم العثور على مجلد Content الخاص بـ Minecraft. ثبّت Minecraft من تطبيق Xbox.'
        ru='Папка Content Minecraft не найдена. Установите Minecraft из приложения Xbox.'
    }
    'err_package_incomplete' = @{
        en='Minecraft package found but the game executable is missing. Reinstall Minecraft and try again.'
        zh='找到 Minecraft 包，但缺少游戏可执行文件。请重新安装 Minecraft 后再试。'
        hi='Minecraft पैकेज मिला, लेकिन गेम एक्ज़ीक्यूटेबल गायब है। Minecraft फिर से इंस्टॉल करके देखें。'
        es='Se encontró el paquete de Minecraft, pero falta el ejecutable del juego. Reinstala Minecraft e inténtalo de nuevo.'
        fr='Le package Minecraft est présent, mais l''exécutable du jeu est manquant. Réinstallez Minecraft et réessayez.'
        ar='تم العثور على حزمة Minecraft، لكن ملف تشغيل اللعبة مفقود. أعد تثبيت Minecraft وحاول مرة أخرى.'
        ru='Пакет Minecraft найден, но исполняемый файл игры отсутствует. Переустановите Minecraft и попробуйте снова.'
    }
    'closing_mc' = @{
        en='Closing Minecraft...'
        zh='正在关闭 Minecraft...'
        hi='Minecraft बंद किया जा रहा है...'
        es='Cerrando Minecraft...'
        fr='Fermeture de Minecraft...'
        ar='جارٍ إغلاق Minecraft...'
        ru='Закрытие Minecraft...'
    }
    'downloading_bin' = @{
        en='Downloading the binary (winmm.dll)...'
        zh='正在下载二进制文件 (winmm.dll)...'
        hi='बाइनरी डाउनलोड हो रही है (winmm.dll)...'
        es='Descargando el binario (winmm.dll)...'
        fr='Téléchargement du binaire (winmm.dll)...'
        ar='جارٍ تنزيل الملف الثنائي (winmm.dll)...'
        ru='Загрузка бинарного файла (winmm.dll)...'
    }
    'retry_download' = @{
        en='Temporary network error while downloading (e.g. GitHub 503). Retrying ({0}/{1})...'
        es='Error temporal de red al descargar (p. ej., 503 de GitHub). Reintentando ({0}/{1})...'
        fr='Erreur réseau temporaire lors du téléchargement (ex. 503 de GitHub). Nouvel essai ({0}/{1})...'
        zh='下载时出现临时网络错误（例如 GitHub 503）。正在重试（{0}/{1}）...'
        hi='डाउनलोड के दौरान अस्थायी नेटवर्क त्रुटि (जैसे GitHub 503)। पुनः प्रयास ({0}/{1})...'
        ar='خطأ شبكة مؤقت أثناء التنزيل (مثل 503 من GitHub). إعادة المحاولة ({0}/{1})...'
        ru='Временная сетевая ошибка при загрузке (например, 503 от GitHub). Повторная попытка ({0}/{1})...'
    }
    'err_download_unavailable' = @{
        en='Could not download winmm.dll: the download server (GitHub) returned a temporary error (503/502/504) several times in a row. This is not an installer problem. Check your connection and run the installer again in a few minutes.'
        es='No se pudo descargar winmm.dll: el servidor de descarga (GitHub) devolvio un error temporal (503/502/504) varias veces seguidas. No es un problema del instalador. Verifica tu conexion y vuelve a ejecutar el instalador en unos minutos.'
        fr='Impossible de télécharger winmm.dll : le serveur de téléchargement (GitHub) a renvoyé une erreur temporaire (503/502/504) plusieurs fois de suite. Ce n''est pas un problème de l''installateur. Vérifiez votre connexion et relancez l''installateur dans quelques minutes.'
        zh='无法下载 winmm.dll：下载服务器（GitHub）连续多次返回临时错误（503/502/504）。这不是安装程序的问题。请检查网络连接，几分钟后重新运行安装程序。'
        hi='winmm.dll डाउनलोड नहीं हो सका: डाउनलोड सर्वर (GitHub) ने लगातार कई बार अस्थायी त्रुटि (503/502/504) दी। यह इंस्टॉलर की समस्या नहीं है। अपना कनेक्शन जाँचें और कुछ मिनटों बाद इंस्टॉलर फिर से चलाएँ।'
        ar='تعذّر تنزيل winmm.dll: أعاد خادم التنزيل (GitHub) خطأً مؤقتًا (503/502/504) عدة مرات متتالية. ليست مشكلة في المثبّت. تحقق من اتصالك وأعد تشغيل المثبّت بعد بضع دقائق.'
        ru='Не удалось загрузить winmm.dll: сервер загрузки (GitHub) несколько раз подряд возвращал временную ошибку (503/502/504). Это не проблема установщика. Проверьте подключение и снова запустите установщик через несколько минут.'
    }
    'err_download_failed' = @{
        en='Could not download winmm.dll. Check your internet connection and run the installer again. Detail: {0}'
        es='No se pudo descargar winmm.dll. Verifica tu conexion a internet y vuelve a ejecutar el instalador. Detalle: {0}'
        fr='Impossible de télécharger winmm.dll. Vérifiez votre connexion internet et relancez l''installateur. Détail : {0}'
        zh='无法下载 winmm.dll。请检查网络连接并重新运行安装程序。详细信息：{0}'
        hi='winmm.dll डाउनलोड नहीं हो सका। अपना इंटरनेट कनेक्शन जाँचें और इंस्टॉलर फिर से चलाएँ। विवरण: {0}'
        ar='تعذّر تنزيل winmm.dll. تحقق من اتصالك بالإنترنت وأعد تشغيل المثبّت. التفاصيل: {0}'
        ru='Не удалось загрузить winmm.dll. Проверьте подключение к интернету и снова запустите установщик. Подробности: {0}'
    }
    'err_hash_invalid' = @{
        en='Invalid winmm.dll hash: {0}'
        zh='winmm.dll 哈希无效: {0}'
        hi='winmm.dll का हैश अमान्य: {0}'
        es='Hash de winmm.dll inválido: {0}'
        fr='Hash de winmm.dll invalide : {0}'
        ar='تجزئة winmm.dll غير صالحة: {0}'
        ru='Неверный хеш winmm.dll: {0}'
    }
    'backup_orig' = @{
        en='Backup of the original winmm saved as winmm.dll.orig'
        zh='已将原始 winmm 备份为 winmm.dll.orig'
        hi='मूल winmm का बैकअप winmm.dll.orig के रूप में सहेजा गया'
        es='Copia de seguridad del winmm original en winmm.dll.orig'
        fr='Sauvegarde du winmm original dans winmm.dll.orig'
        ar='تم حفظ نسخة احتياطية من winmm الأصلي باسم winmm.dll.orig'
        ru='Резервная копия оригинального winmm сохранена в winmm.dll.orig'
    }
    'install_ok' = @{
        en='OK - unlock installed.'
        zh='OK - 解锁已安装。'
        hi='OK - अनलॉक स्थापित हो गया।'
        es='OK - desbloqueo instalado.'
        fr='OK - déverrouillage installé.'
        ar='تم تثبيت فتح اللعبة.'
        ru='OK - разблокировка установлена.'
    }
    'restored_ok' = @{
        en='Original winmm restored.'
        zh='已还原原始 winmm。'
        hi='मूल winmm पुनर्स्थापित हो गया।'
        es='winmm original restaurado.'
        fr='winmm original restauré.'
        ar='تمت استعادة winmm الأصلي.'
        ru='Оригинальный winmm восстановлен.'
    }
    'removed_ok' = @{
        en='winmm.dll removed (the game will use the system one).'
        zh='已移除 winmm.dll (游戏将使用系统自带的)。'
        hi='winmm.dll हटा दिया गया (गेम सिस्टम वाला उपयोग करेगा)।'
        es='winmm.dll eliminado (el juego usará el del sistema).'
        fr='winmm.dll supprimé (le jeu utilisera celui du système).'
        ar='تمت إزالة winmm.dll (ستستخدم اللعبة ملف النظام).'
        ru='winmm.dll удалён (игра будет использовать системный).'
    }
    'unlock_removed' = @{
        en='Unlock removed.'
        zh='解锁已移除。'
        hi='अनलॉक हटा दिया गया।'
        es='Desbloqueo eliminado.'
        fr='Déverrouillage supprimé.'
        ar='تمت إزالة فتح اللعبة.'
        ru='Разблокировка удалена.'
    }
    'nothing_to_restore' = @{
        en='The unlock is not installed (nothing to restore).'
        zh='解锁未安装（没有可还原的内容）。'
        hi='अनलॉक स्थापित नहीं है (पुनर्स्थापित करने के लिए कुछ नहीं)।'
        es='El desbloqueo no está instalado (nada que restaurar).'
        fr='Le déverrouillage n''est pas installé (rien à restaurer).'
        ar='فتح اللعبة غير مثبت (لا يوجد شيء لاستعادته).'
        ru='Разблокировка не установлена (нечего восстанавливать).'
    }
    'mc_started' = @{
        en='Minecraft started.'
        zh='Minecraft 已启动。'
        hi='Minecraft शुरू हो गया।'
        es='Minecraft iniciado.'
        fr='Minecraft lancé.'
        ar='تم تشغيل Minecraft.'
        ru='Minecraft запущен.'
    }
    'mc_start_failed' = @{
        en='Could not start Minecraft automatically. Open it from the Start Menu.'
        zh='无法自动启动 Minecraft。请从开始菜单打开。'
        hi='Minecraft स्वचालित रूप से शुरू नहीं हो सका। स्टार्ट मेनू से खोलें।'
        es='No se pudo iniciar Minecraft automáticamente. Ábrelo desde el menú Inicio.'
        fr='Impossible de démarrer Minecraft automatiquement. Ouvrez-le depuis le menu Démarrer.'
        ar='تعذّر تشغيل Minecraft تلقائيًا. افتحه من قائمة ابدأ.'
        ru='Не удалось запустить Minecraft автоматически. Откройте его из меню «Пуск».'
    }
    'state_unlocked' = @{
        en='Minecraft is already UNLOCKED.'
        zh='Minecraft 已经解锁。'
        hi='Minecraft पहले से अनलॉक है।'
        es='Minecraft ya está DESBLOQUEADO.'
        fr='Minecraft est déjà DÉBLOQUÉ.'
        ar='Minecraft مفتوح بالفعل.'
        ru='Minecraft уже РАЗБЛОКИРОВАН.'
    }
    'state_unlocked_hint' = @{
        en='If you want, choose [1] to remove the unlock and go back to Trial.'
        zh='如果需要，请选择 [1] 移除解锁并恢复到试用版。'
        hi='चाहें तो अनलॉक हटाने और ट्रायल पर वापस जाने के लिए [1] चुनें।'
        es='Si quieres, elige [1] para eliminar el desbloqueo y volver a la prueba.'
        fr='Si vous voulez, choisissez [1] pour supprimer le déverrouillage et revenir à l''essai.'
        ar='إذا أردت، اختر [1] لإزالة فتح اللعبة والعودة إلى النسخة التجريبية.'
        ru='Если хотите, выберите [1], чтобы удалить разблокировку и вернуться к пробной версии.'
    }
    'state_trial' = @{
        en='Minecraft is in TRIAL mode.'
        zh='Minecraft 处于试用版模式。'
        hi='Minecraft ट्रायल मोड में है।'
        es='Minecraft está en modo PRUEBA.'
        fr='Minecraft est en mode ESSAI.'
        ar='Minecraft في وضع النسخة التجريبية.'
        ru='Minecraft в пробном режиме.'
    }
    'state_trial_hint' = @{
        en='Choose [1] to unlock the full game.'
        zh='选择 [1] 解锁完整版游戏。'
        hi='पूरा गेम अनलॉक करने के लिए [1] चुनें।'
        es='Elige [1] para desbloquear el juego completo.'
        fr='Choisissez [1] pour déverrouiller le jeu complet.'
        ar='اختر [1] لفتح اللعبة الكاملة.'
        ru='Выберите [1], чтобы разблокировать полную игру.'
    }
    'menu_title' = @{
        en='Available Options'
        zh='可用选项'
        hi='उपलब्ध विकल्प'
        es='Opciones disponibles'
        fr='Options disponibles'
        ar='الخيارات المتاحة'
        ru='Доступные параметры'
    }
    'menu_1_install' = @{
        en='Install unlock'
        zh='安装解锁'
        hi='अनलॉक स्थापित करें'
        es='Instalar desbloqueo'
        fr='Installer le déverrouillage'
        ar='تثبيت فتح اللعبة'
        ru='Установить разблокировку'
    }
    'menu_1_remove' = @{
        en='Remove unlock (back to Trial)'
        zh='移除解锁（恢复试用版）'
        hi='अनलॉक हटाएँ (ट्रायल पर वापस)'
        es='Eliminar desbloqueo (volver a prueba)'
        fr='Supprimer le déverrouillage (revenir à l''essai)'
        ar='إزالة فتح اللعبة (العودة إلى النسخة التجريبية)'
        ru='Удалить разблокировку (вернуться к пробной версии)'
    }
    'menu_2_reinstall' = @{
        en='Reinstall unlock'
        zh='重新安装解锁'
        hi='अनलॉक फिर से स्थापित करें'
        es='Reinstalar desbloqueo'
        fr='Réinstaller le déverrouillage'
        ar='إعادة تثبيت فتح اللعبة'
        ru='Переустановить разблокировку'
    }
    'menu_0' = @{
        en='Exit'
        zh='退出'
        hi='बाहर'
        es='Salir'
        fr='Quitter'
        ar='خروج'
        ru='Выход'
    }
    'choose_option' = @{
        en='Choose an option'
        zh='请选择一个选项'
        hi='एक विकल्प चुनें'
        es='Elige una opción'
        fr='Choisissez une option'
        ar='اختر خيارًا'
        ru='Выберите вариант'
    }
    'invalid_option' = @{
        en='Invalid option.'
        zh='无效选项。'
        hi='अमान्य विकल्प।'
        es='Opción no válida.'
        fr='Option invalide.'
        ar='خيار غير صالح.'
        ru='Неверный вариант.'
    }
    'press_enter' = @{
        en='Press Enter to continue...'
        zh='按 Enter 键继续...'
        hi='जारी रखने के लिए Enter दबाएँ...'
        es='Pulse Enter para continuar...'
        fr='Appuyez sur Entrée pour continuer...'
        ar='اضغط Enter للمتابعة...'
        ru='Нажмите Enter для продолжения...'
    }
    'arch_line' = @{
        en='Detected game build: {0} (Machine={1})'
        zh='检测到的游戏构建：{0}（Machine={1}）'
        hi='गेम बिल्ड पहचाना गया: {0} (Machine={1})'
        es='Build del juego detectado: {0} (Machine={1})'
        fr='Build du jeu détecté : {0} (Machine={1})'
        ar='إصدار اللعبة المكتشف: {0} (Machine={1})'
        ru='Обнаружена сборка игры: {0} (Machine={1})'
    }
    'arch_unknown' = @{
        en='Could not read the game build from the executable, assuming x64.'
        zh='无法从可执行文件读取游戏构建，将按 x64 处理。'
        hi='एक्ज़ीक्यूटेबल से गेम बिल्ड नहीं पढ़ा जा सका, x64 मान लिया जा रहा है।'
        es='No se pudo leer la build del juego desde el ejecutable, se asume x64.'
        fr='Impossible de lire la build du jeu depuis l''exécutable, x64 supposé.'
        ar='تعذر قراءة إصدار اللعبة من الملف التنفيذي، سيتم افتراض x64.'
        ru='Не удалось прочитать сборку игры из исполняемого файла, используется x64.'
    }
    'arm64_detected' = @{
        en='[ARM64] Windows on ARM PC detected: using the native ARM64 unlocker (BETA).'
        zh='[ARM64] 检测到 Windows on ARM 电脑：使用原生 ARM64 解锁器（测试版）。'
        hi='[ARM64] Windows on ARM पीसी पाया गया: नेटिव ARM64 अनलॉकर का उपयोग हो रहा है (बीटा)।'
        es='[ARM64] PC con Windows on ARM detectado: usando el unlocker ARM64 nativo (BETA).'
        fr='[ARM64] PC Windows on ARM détecté : utilisation de l''unlocker ARM64 natif (BETA).'
        ar='[ARM64] تم اكتشاف جهاز Windows on ARM: سيتم استخدام أداة الفتح الأصلية ARM64 (نسخة تجريبية).'
        ru='[ARM64] Обнаружен ПК с Windows on ARM: используется нативный ARM64 анлокер (БЕТА).'
    }
    'arm64_no_release' = @{
        en='[ARM64] The ARM64 build has not been published in this release yet.'
        zh='[ARM64] 此版本尚未发布 ARM64 构建。'
        hi='[ARM64] ARM64 बिल्ड अभी इस रिलीज़ में प्रकाशित नहीं हुआ है।'
        es='[ARM64] La build ARM64 aún no ha sido publicada en esta release.'
        fr='[ARM64] La build ARM64 n''est pas encore publiée dans cette release.'
        ar='[ARM64] لم يتم نشر إصدار ARM64 في هذا الإصدار بعد.'
        ru='[ARM64] Сборка ARM64 еще не опубликована в этом релизе.'
    }
    'arm64_hash_skipped' = @{
        en='[ARM64] Hash verification is unavailable in this beta phase.'
        zh='[ARM64] 此测试阶段无法进行哈希校验。'
        hi='[ARM64] इस बीटा चरण में हैश सत्यापन उपलब्ध नहीं है।'
        es='[ARM64] La verificación de hash no está disponible en esta fase beta.'
        fr='[ARM64] La vérification de hash n''est pas disponible dans cette phase bêta.'
        ar='[ARM64] التحقق من التجزئة غير متاح في هذه المرحلة التجريبية.'
        ru='[ARM64] Проверка хеша недоступна на этой бета-стадии.'
    }
    'track_releases' = @{
        en='Track new releases at {0}'
        zh='在此查看新版本：{0}'
        hi='नए रिलीज़ यहाँ देखें: {0}'
        es='Consulta las nuevas releases en {0}'
        fr='Suivez les nouvelles releases sur {0}'
        ar='تابع الإصدارات الجديدة على {0}'
        ru='Следите за новыми релизами здесь: {0}'
    }
    'state_unlocked_v' = @{
        en='Minecraft is already UNLOCKED ({0}).'
        es='Minecraft ya está DESBLOQUEADO ({0}).'
        zh='Minecraft 已经解锁（{0}）。'
        hi='Minecraft पहले से अनलॉक है ({0})।'
        fr='Minecraft est déjà DÉBLOQUÉ ({0}).'
        ar='Minecraft مفتوح بالفعل ({0}).'
        ru='Minecraft уже РАЗБЛОКИРОВАН ({0}).'
    }
    'state_older_hint' = @{
        en='Installed unlock ({0}) is older than this menu ({1}) - use [2] to update.'
        es='El desbloqueo instalado ({0}) es más antiguo que este menú ({1}) - usa [2] para actualizar.'
        zh='已安装的解锁（{0}）比当前菜单（{1}）旧 - 请使用 [2] 更新。'
        hi='स्थापित अनलॉक ({0}) इस मेनू ({1}) से पुराना है - अपडेट के लिए [2] उपयोग करें।'
        fr='Le déverrouillage installé ({0}) est plus ancien que ce menu ({1}) - utilisez [2] pour mettre à jour.'
        ar='الفتح المثبّت ({0}) أقدم من هذه القائمة ({1}) - استخدم [2] للتحديث.'
        ru='Установленная разблокировка ({0}) старее этого меню ({1}) - используйте [2] для обновления.'
    }
    'tested_warning' = @{
        en='Warning: game version {0} has NOT been tested with this unlocker yet. If anything fails, please report it on Discord.'
        es='Aviso: la versión del juego {0} aún NO ha sido probada con este unlocker. Si algo falla, repórtalo en Discord.'
        zh='警告：游戏版本 {0} 尚未经过此解锁器测试。如有问题，请在 Discord 上报告。'
        hi='चेतावनी: गेम संस्करण {0} का अभी इस अनलॉकर से परीक्षण नहीं हुआ है। यदि कुछ विफल हो तो Discord पर रिपोर्ट करें।'
        fr='Avertissement : la version {0} du jeu n''a pas encore été testée avec ce déverrouilleur. En cas de problème, signalez-le sur Discord.'
        ar='تحذير: إصدار اللعبة {0} لم يُختبر بعد مع هذا الفاتح. إذا حدثت أي مشكلة، يُرجى الإبلاغ عنها على Discord.'
        ru='Внимание: версия игры {0} ещё не протестирована с этим анлокером. Если что-то не работает, сообщите об этом в Discord.'
    }
    'gate_untested' = @{
        en='Installation BLOCKED: game version {0} has not been tested with this unlocker and would probably not work.'
        es='Instalación BLOQUEADA: la versión del juego {0} no ha sido probada con este unlocker y probablemente no funcionaría.'
        zh='安装已阻止：游戏版本 {0} 尚未经过此解锁器测试，很可能无法工作。'
        hi='इंस्टॉलेशन अवरुद्ध: गेम संस्करण {0} इस अनलॉकर के साथ परीक्षित नहीं है और संभवतः काम नहीं करेगा।'
        fr='Installation BLOQUÉE : la version {0} du jeu n''a pas été testée avec ce déverrouilleur et ne fonctionnerait probablement pas.'
        ar='تم حظر التثبيت: إصدار اللعبة {0} لم يُختبر مع هذا الفاتح وربما لن يعمل.'
        ru='Установка ЗАБЛОКИРОВАНА: версия игры {0} не тестировалась с этим анлокером и, скорее всего, не будет работать.'
    }
    'gate_untested_hint' = @{
        en='Update Minecraft from the Microsoft Store to the supported version and run the installer again.'
        es='Actualiza Minecraft desde la Microsoft Store a la versión compatible y vuelve a ejecutar el instalador.'
        zh='请通过 Microsoft Store 将 Minecraft 更新到受支持的版本，然后重新运行安装程序。'
        hi='Microsoft Store से Minecraft को समर्थित संस्करण में अपडेट करें और इंस्टॉलर फिर से चलाएँ।'
        fr='Mettez à jour Minecraft depuis le Microsoft Store vers la version prise en charge, puis relancez l''installateur.'
        ar='حدّث Minecraft من متجر Microsoft إلى الإصدار المدعوم ثم شغّل المثبّت مرة أخرى.'
        ru='Обновите Minecraft через Microsoft Store до поддерживаемой версии и снова запустите установщик.'
    }
    'cache_used' = @{
        en='Offline: using the local validated copy of the binary ({0}).'
        es='Sin internet: usando la copia local validada del binario ({0}).'
        zh='无网络：使用本地已验证的二进制副本（{0}）。'
        hi='इंटरनेट नहीं: बाइनरी की स्थानीय सत्यापित प्रतिलिपि का उपयोग ({0})।'
        fr='Hors ligne : utilisation de la copie locale validée du binaire ({0}).'
        ar='بدون إنترنت: استخدام النسخة المحلية الموثّقة من الملف الثنائي ({0}).'
        ru='Нет интернета: используется локальная проверенная копия бинарника ({0}).'
    }
    'cache_saved' = @{
        en='Local cache saved for offline reinstall: {0}'
        es='Copia local guardada para reinstalación sin conexión: {0}'
        zh='已保存本地缓存，供离线重装使用：{0}'
        hi='ऑफ़लाइन पुनर्स्थापना के लिए स्थानीय कैश सहेजा गया: {0}'
        fr='Cache local enregistré pour la réinstallation hors ligne : {0}'
        ar='تم حفظ ذاكرة التخزين المؤقت المحلية لإعادة التثبيت دون اتصال: {0}'
        ru='Локальный кэш сохранён для офлайн-переустановки: {0}'
    }
    'menu_4_trouble' = @{
        en='Open troubleshooting guide (web)'
        es='Abrir guía de problemas (web)'
        zh='打开问题排查指南（网页）'
        hi='समस्या समाधान मार्गदर्शिका खोलें (वेब)'
        fr='Ouvrir le guide de dépannage (web)'
        ar='فتح دليل استكشاف الأخطاء (ويب)'
        ru='Открыть руководство по устранению неполадок (веб)'
    }
    'menu_5_discord' = @{
        en='Open community Discord'
        es='Abrir Discord de la comunidad'
        zh='打开社区 Discord'
        hi='समुदाय Discord खोलें'
        fr='Ouvrir le Discord de la communauté'
        ar='فتح Discord المجتمع'
        ru='Открыть Discord сообщества'
    }
    'menu_6_bmc' = @{
        en='Support the project (Buy Me a Coffee)'
        es='Apoyar el proyecto (Buy Me a Coffee)'
        zh='支持本项目（Buy Me a Coffee）'
        hi='परियोजना का समर्थन करें (Buy Me a Coffee)'
        fr='Soutenir le projet (Buy Me a Coffee)'
        ar='دعم المشروع (Buy Me a Coffee)'
        ru='Поддержать проект (Buy Me a Coffee)'
    }
    'diag_title' = @{
        en='Diagnostic report - Minecraft Bedrock Free v{0}'
        es='Informe de diagnóstico - Minecraft Bedrock Free v{0}'
        zh='诊断报告 - Minecraft Bedrock Free v{0}'
        hi='डायग्नोस्टिक रिपोर्ट - Minecraft Bedrock Free v{0}'
        fr='Rapport de diagnostic - Minecraft Bedrock Free v{0}'
        ar='تقرير التشخيص - Minecraft Bedrock Free v{0}'
        ru='Диагностический отчёт - Minecraft Bedrock Free v{0}'
    }
    'diag_os' = @{
        en='OS'
        es='Sistema'
        zh='系统'
        hi='ऑपरेटिंग सिस्टम'
        fr='Système'
        ar='نظام التشغيل'
        ru='Система'
    }
    'diag_ps' = @{
        en='PowerShell'
        es='PowerShell'
        zh='PowerShell'
        hi='PowerShell'
        fr='PowerShell'
        ar='PowerShell'
        ru='PowerShell'
    }
    'diag_admin' = @{
        en='Administrator'
        es='Administrador'
        zh='管理员'
        hi='व्यवस्थापक'
        fr='Administrateur'
        ar='مسؤول'
        ru='Администратор'
    }
    'diag_yes' = @{
        en='yes'
        es='sí'
        zh='是'
        hi='हाँ'
        fr='oui'
        ar='نعم'
        ru='да'
    }
    'diag_no' = @{
        en='no'
        es='no'
        zh='否'
        hi='नहीं'
        fr='non'
        ar='لا'
        ru='нет'
    }
    'diag_content' = @{
        en='Game Content folder'
        es='Carpeta Content del juego'
        zh='游戏 Content 文件夹'
        hi='गेम Content फ़ोल्डर'
        fr='Dossier Content du jeu'
        ar='مجلد Content للعبة'
        ru='Папка Content игры'
    }
    'diag_source' = @{
        en='Install source'
        es='Origen de la instalación'
        zh='安装来源'
        hi='इंस्टॉल स्रोत'
        fr='Source d''installation'
        ar='مصدر التثبيت'
        ru='Источник установки'
    }
    'diag_source_store' = @{
        en='Microsoft Store (UWP)'
        es='Microsoft Store (UWP)'
        zh='Microsoft Store (UWP)'
        hi='Microsoft Store (UWP)'
        fr='Microsoft Store (UWP)'
        ar='Microsoft Store (UWP)'
        ru='Microsoft Store (UWP)'
    }
    'diag_source_gdk' = @{
        en='Xbox App (GDK)'
        es='Xbox App (GDK)'
        zh='Xbox App (GDK)'
        hi='Xbox App (GDK)'
        fr='Xbox App (GDK)'
        ar='Xbox App (GDK)'
        ru='Xbox App (GDK)'
    }
    'diag_source_unknown' = @{
        en='unknown'
        es='desconocida'
        zh='未知'
        hi='अज्ञात'
        fr='inconnue'
        ar='غير معروفة'
        ru='неизвестно'
    }
    'diag_game_version' = @{
        en='Game version'
        es='Versión del juego'
        zh='游戏版本'
        hi='गेम संस्करण'
        fr='Version du jeu'
        ar='إصدار اللعبة'
        ru='Версия игры'
    }
    'diag_game_arch' = @{
        en='Game architecture'
        es='Arquitectura del juego'
        zh='游戏架构'
        hi='गेम आर्किटेक्चर'
        fr='Architecture du jeu'
        ar='بنية اللعبة'
        ru='Архитектура игры'
    }
    'diag_unlock' = @{
        en='Unlock installed'
        es='Desbloqueo instalado'
        zh='已安装的解锁'
        hi='अनलॉक स्थापित'
        fr='Déverrouillage installé'
        ar='الفتح المثبّت'
        ru='Установленная разблокировка'
    }
    'diag_unlock_none' = @{
        en='not installed (Trial)'
        es='no instalado (prueba)'
        zh='未安装（试用版）'
        hi='स्थापित नहीं (ट्रायल)'
        fr='non installé (essai)'
        ar='غير مثبّت (نسخة تجريبية)'
        ru='не установлена (пробная версия)'
    }
    'diag_tested' = @{
        en='Game version vs tested versions'
        es='Versión del juego vs probadas'
        zh='游戏版本 vs 已测试版本'
        hi='गेम संस्करण बनाम परीक्षण किए गए संस्करण'
        fr='Version du jeu vs versions testées'
        ar='إصدار اللعبة مقابل الإصدارات المختبرة'
        ru='Версия игры против протестированных версий'
    }
    'diag_tested_ok' = @{
        en='OK - covered by tested-versions.json'
        es='OK - cubierta por tested-versions.json'
        zh='OK - 已包含在 tested-versions.json 中'
        hi='OK - tested-versions.json द्वारा कवर'
        fr='OK - couverte par tested-versions.json'
        ar='موافق - مغطّى في tested-versions.json'
        ru='OK - покрыта tested-versions.json'
    }
    'diag_tested_bad' = @{
        en='ATTENTION - not in the tested list'
        es='ATENCIÓN - fuera de la lista de probadas'
        zh='注意 - 不在已测试列表中'
        hi='ध्यान दें - परीक्षण सूची में नहीं'
        fr='ATTENTION - hors liste des versions testées'
        ar='انتبه - خارج قائمة الإصدارات المختبرة'
        ru='ВНИМАНИЕ - нет в списке протестированных'
    }
    'diag_tested_unknown' = @{
        en='unavailable (offline or no data)'
        es='indisponible (sin internet o sin datos)'
        zh='不可用（无网络或无数据）'
        hi='अनुपलब्ध (इंटरनेट नहीं या कोई डेटा नहीं)'
        fr='indisponible (hors ligne ou aucune donnée)'
        ar='غير متاح (بدون إنترنت أو بدون بيانات)'
        ru='недоступно (нет интернета или данных)'
    }
    'diag_av' = @{
        en='Defender exclusions (mbu/Minecraft)'
        es='Exclusiones de Defender (mbu/Minecraft)'
        zh='Defender 排除项（mbu/Minecraft）'
        hi='Defender बहिष्करण (mbu/Minecraft)'
        fr='Exclusions Defender (mbu/Minecraft)'
        ar='استثناءات Defender (mbu/Minecraft)'
        ru='Исключения Defender (mbu/Minecraft)'
    }
    'diag_av_none' = @{
        en='none found'
        es='ninguna encontrada'
        zh='未找到'
        hi='कोई नहीं मिला'
        fr='aucune trouvée'
        ar='لم يتم العثور على أي منها'
        ru='не найдено'
    }
    'diag_cache' = @{
        en='Offline binary cache'
        es='Caché offline del binario'
        zh='二进制文件离线缓存'
        hi='बाइनरी ऑफ़लाइन कैश'
        fr='Cache hors ligne du binaire'
        ar='ذاكرة التخزين المؤقت للملف الثنائي دون اتصال'
        ru='Офлайн-кэш бинарника'
    }
    'diag_cache_ok' = @{
        en='present and valid ({0})'
        es='presente y válida ({0})'
        zh='存在且有效（{0}）'
        hi='मौजूद और मान्य ({0})'
        fr='présente et valide ({0})'
        ar='موجودة وصالحة ({0})'
        ru='есть и действителен ({0})'
    }
    'diag_cache_bad' = @{
        en='present BUT with a different hash than the current binary'
        es='presente PERO con hash distinto del binario actual'
        zh='存在但与当前二进制文件的哈希不同'
        hi='मौजूद लेकिन वर्तमान बाइनरी से भिन्न हैश के साथ'
        fr='présente MAIS avec un hash différent du binaire actuel'
        ar='موجودة لكن بتجزئة مختلفة عن الملف الثنائي الحالي'
        ru='есть, НО с хешем, отличным от текущего бинарника'
    }
    'diag_cache_none' = @{
        en='missing (created on next install)'
        es='ausente (se creará en la próxima instalación)'
        zh='缺失（下次安装时创建）'
        hi='अनुपस्थित (अगली स्थापना पर बनेगा)'
        fr='absente (créée à la prochaine installation)'
        ar='غير موجودة (ستُنشأ في التثبيت التالي)'
        ru='отсутствует (будет создан при следующей установке)'
    }
    'install_content_dir' = @{
        en='Content folder: {0}'
        es='Carpeta Content: {0}'
        fr='Dossier Content : {0}'
        zh='Content 文件夹：{0}'
        hi='Content फ़ोल्डर: {0}'
        ar='مجلد Content: {0}'
        ru='Папка Content: {0}'
    }
    'diag_winmm_hash' = @{
        en='winmm hash'
        es='hash de winmm'
        fr='hash winmm'
        zh='winmm 哈希'
        hi='winmm हैश'
        ar='تجزئة winmm'
        ru='хеш winmm'
    }
    'diag_machine_unreadable' = @{
        en='unreadable'
        es='ilegible'
        fr='illisible'
        zh='不可读'
        hi='अपठनीय'
        ar='غير قابل للقراءة'
        ru='нечитаемо'
    }
    'diag_cand_label' = @{
        en='[candidate]'
        es='[candidato]'
        fr='[candidat]'
        zh='[候选]'
        hi='[उम्मीदवार]'
        ar='[مرشح]'
        ru='[кандидат]'
    }
    'diag_cand_present' = @{
        en='winmm.dll present'
        es='winmm.dll presente'
        fr='winmm.dll présent'
        zh='winmm.dll 存在'
        hi='winmm.dll मौजूद'
        ar='winmm.dll موجود'
        ru='winmm.dll присутствует'
    }
    'diag_cand_absent' = @{
        en='no winmm.dll'
        es='sin winmm.dll'
        fr='pas de winmm.dll'
        zh='没有 winmm.dll'
        hi='winmm.dll नहीं'
        ar='لا يوجد winmm.dll'
        ru='нет winmm.dll'
    }
    'diag_cand_used' = @{
        en='used folder'
        es='carpeta usada'
        fr='dossier utilisé'
        zh='使用的文件夹'
        hi='उपयोग किया गया फ़ोल्डर'
        ar='المجلد المستخدم'
        ru='используемая папка'
    }
    'diag_reason' = @{
        en='Reason'
        es='Motivo'
        fr='Motif'
        zh='原因'
        hi='कारण'
        ar='السبب'
        ru='Причина'
    }
    'diag_date' = @{
        en='Report date'
        es='Fecha del informe'
        fr='Date du rapport'
        zh='报告日期'
        hi='रिपोर्ट दिनांक'
        ar='تاريخ التقرير'
        ru='Дата отчёта'
    }
    'diag_os_arch' = @{
        en='OS architecture'
        es='Arquitectura del SO'
        fr='Architecture du systeme'
        zh='操作系统架构'
        hi='ओएस आर्किटेक्चर'
        ar='بنية نظام التشغيل'
        ru='Архитектура ОС'
    }
    'diag_cpu' = @{
        en='CPU'
        es='CPU'
        fr='CPU'
        zh='CPU'
        hi='CPU'
        ar='CPU'
        ru='CPU'
    }
    'diag_pkg' = @{
        en='Store package'
        es='Paquete de la Store'
        fr='Package Store'
        zh='商店程序包'
        hi='स्टोर पैकेज'
        ar='حزمة المتجر'
        ru='Пакет Store'
    }
    'diag_defender' = @{
        en='Defender (RTP/engine/signature)'
        es='Defender (RTP/motor/firma)'
        fr='Defender (RTP/moteur/signature)'
        zh='Defender（实时/引擎/签名）'
        hi='Defender (RTP/इंजन/हस्ताक्षर)'
        ar='Defender (RTP/المحرك/التوقيع)'
        ru='Defender (RTP/движок/подпись)'
    }
    'diag_defender_none' = @{
        en='unavailable'
        es='no disponible'
        fr='indisponible'
        zh='不可用'
        hi='अनुपलब्ध'
        ar='غير متاح'
        ru='недоступно'
    }
    'diag_sac' = @{
        en='Smart App Control'
        es='Smart App Control'
        fr='Smart App Control'
        zh='Smart App Control'
        hi='Smart App Control'
        ar='Smart App Control'
        ru='Smart App Control'
    }
    'diag_sac_off' = @{
        en='off'
        es='desactivado'
        fr='desactive'
        zh='已关闭'
        hi='बंद'
        ar='متوقف'
        ru='отключен'
    }
    'diag_sac_on' = @{
        en='ON (blocks the unlocker)'
        es='ACTIVADO (bloquea el desbloqueo)'
        fr='ACTIVE (bloque le deverrouilleur)'
        zh='已开启（会阻止解锁器）'
        hi='चालू (अनलॉकर को ब्लॉक करता है)'
        ar='قيد التشغيل (يحظر الفاتح)'
        ru='ВКЛЮЧЕН (блокирует анлокер)'
    }
    'diag_sac_eval' = @{
        en='evaluation (also blocks)'
        es='evaluacion (tambien bloquea)'
        fr='evaluation (bloque aussi)'
        zh='评估模式（同样会阻止）'
        hi='मूल्यांकन (ब्लॉक भी करता है)'
        ar='تقييم (يحظر أيضًا)'
        ru='оценка (тоже блокирует)'
    }
    'diag_sac_unknown' = @{
        en='unavailable'
        es='no disponible'
        fr='indisponible'
        zh='不可用'
        hi='अनुपलब्ध'
        ar='غير متاح'
        ru='недоступно'
    }
    'sac_warn_title' = @{
        en='Smart App Control is ON.'
        es='Smart App Control esta ACTIVADO.'
        fr='Smart App Control est ACTIVE.'
        zh='Smart App Control 已开启。'
        hi='Smart App Control चालू है।'
        ar='Smart App Control قيد التشغيل.'
        ru='Smart App Control ВКЛЮЧЕН.'
    }
    'sac_warn_body' = @{
        en='Smart App Control blocks files without a digital signature. The unlocker winmm.dll is unsigned, so with it ON Minecraft will not open unlocked (it stays in Trial). Turn Smart App Control off before installing.'
        es='Smart App Control bloquea archivos sin firma digital. El winmm.dll del desbloqueo no tiene firma, asi que con el activado Minecraft no abrira desbloqueado (se queda en la prueba). Desactiva Smart App Control antes de instalar.'
        fr='Smart App Control bloque les fichiers sans signature numerique. Le winmm.dll du deverrouillage n''est pas signe, donc avec lui actif Minecraft ne s''ouvrira pas deverrouille (il reste en essai). Desactivez Smart App Control avant d''installer.'
        zh='Smart App Control 会阻止没有数字签名的文件。解锁器的 winmm.dll 没有签名，因此开启它后 Minecraft 将无法以解锁状态打开（仍为试用版）。安装前请关闭 Smart App Control。'
        hi='Smart App Control बिना डिजिटल हस्ताक्षर वाली फ़ाइलों को ब्लॉक करता है। अनलॉकर का winmm.dll अहस्ताक्षरित है, इसलिए इसे चालू रखने पर Minecraft अनलॉक होकर नहीं खुलेगा (ट्रायल में ही रहेगा)। इंस्टॉल करने से पहले Smart App Control बंद करें।'
        ar='يمنع Smart App Control الملفات غير الموقعة رقميًا. ملف winmm.dll الخاص بالفتح غير موقّع، لذا مع تفعيله لن يفتح Minecraft مفتوحًا (سيبقى في النسخة التجريبية). أوقف تشغيل Smart App Control قبل التثبيت.'
        ru='Smart App Control блокирует файлы без цифровой подписи. winmm.dll анлокера не подписан, поэтому при включенном SAC Minecraft не откроется разблокированным (останется в пробной версии). Отключите Smart App Control перед установкой.'
    }
    'sac_ask' = @{
        en='Do you want to open the Smart App Control settings to turn it off now? (Y for yes, N for no)'
        es='Desea abrir la configuracion de Smart App Control para desactivarlo ahora? (S para si, N para no)'
        fr='Voulez-vous ouvrir les parametres de Smart App Control pour le desactiver maintenant ? (O pour oui, N pour non)'
        zh='是否立即打开 Smart App Control 设置以将其关闭？(S=是，N=否)'
        hi='क्या आप अभी Smart App Control सेटिंग्स खोलकर इसे बंद करना चाहते हैं? (S=हाँ, N=नहीं)'
        ar='هل تريد فتح إعدادات Smart App Control لإيقاف تشغيله الآن؟ (S=نعم، N=لا)'
        ru='Открыть параметры Smart App Control, чтобы отключить его сейчас? (S=да, N=нет)'
    }
    'sac_opened' = @{
        en='Smart App Control settings opened. Turn Smart App Control off and run the installer again.'
        es='Configuracion de Smart App Control abierta. Desactiva Smart App Control y vuelve a ejecutar el instalador.'
        fr='Parametres de Smart App Control ouverts. Desactivez Smart App Control et relancez l''installateur.'
        zh='已打开 Smart App Control 设置。请将其关闭后重新运行安装程序。'
        hi='Smart App Control सेटिंग्स खुल गईं। Smart App Control बंद करें और इंस्टॉलर फिर से चलाएँ।'
        ar='تم فتح إعدادات Smart App Control. أوقف تشغيله وشغّل المثبّت مرة أخرى.'
        ru='Параметры Smart App Control открыты. Отключите Smart App Control и запустите установщик снова.'
    }
    'sac_open_fail' = @{
        en='Could not open the settings. Open it manually: Windows Security > App & browser control > Smart App Control settings.'
        es='No se pudo abrir la configuracion. Abrela manualmente: Seguridad de Windows > App y control del navegador > Smart App Control settings.'
        fr='Impossible d''ouvrir les parametres. Ouvrez-les manuellement : Securite Windows > Controle d''application et de navigateur > Smart App Control settings.'
        zh='无法打开设置。请手动打开：Windows 安全中心 > 应用和浏览器控制 > Smart App Control 设置。'
        hi='सेटिंग्स नहीं खोली जा सकीं। मैन्युअल रूप से खोलें: Windows Security > App & browser control > Smart App Control settings।'
        ar='تعذّر فتح الإعدادات. افتحها يدويًا: أمان Windows > التحكم في التطبيق والمتصفح > Smart App Control settings.'
        ru='Не удалось открыть параметры. Откройте вручную: «Безопасность Windows» > «Управление приложениями и браузером» > Smart App Control settings.'
    }
    'sac_continue' = @{
        en='Continuing with the installation anyway. If the game does not open unlocked, turn Smart App Control off and try again.'
        es='Continuando con la instalacion de todos modos. Si el juego no abre desbloqueado, desactiva Smart App Control e intenta de nuevo.'
        fr='Poursuite de l''installation quand meme. Si le jeu ne s''ouvre pas deverrouille, desactivez Smart App Control et reessayez.'
        zh='仍将继续安装。如果游戏无法以解锁状态打开，请关闭 Smart App Control 后重试。'
        hi='फिर भी इंस्टॉल जारी रखा जा रहा है। यदि गेम अनलॉक होकर नहीं खुलता, तो Smart App Control बंद करके फिर से प्रयास करें।'
        ar='المتابعة في التثبيت على أي حال. إذا لم يفتح Minecraft مفتوحًا، فأوقف تشغيل Smart App Control وحاول مرة أخرى.'
        ru='Продолжаем установку в любом случае. Если игра не откроется разблокированной, отключите Smart App Control и попробуйте снова.'
    }
    'sac_ask_off' = @{
        en='Do you want to turn Smart App Control off now? (Y for yes, N for no)'
        es='Desea desactivar Smart App Control ahora? (S para si, N para no)'
        fr='Voulez-vous desactiver Smart App Control maintenant ? (O pour oui, N pour non)'
        zh='是否立即关闭 Smart App Control？(S=是，N=否)'
        hi='क्या आप अभी Smart App Control बंद करना चाहते हैं? (S=हाँ, N=नहीं)'
        ar='هل تريد إيقاف تشغيل Smart App Control الآن؟ (S=نعم، N=لا)'
        ru='Отключить Smart App Control сейчас? (S=да, N=нет)'
    }
    'sac_off_ok' = @{
        en='Smart App Control turned off. Continuing the installation...'
        es='Smart App Control desactivado. Continuando con la instalacion...'
        fr='Smart App Control desactive. Poursuite de l''installation...'
        zh='Smart App Control 已关闭。继续安装...'
        hi='Smart App Control बंद हो गया। इंस्टॉल जारी...'
        ar='تم إيقاف تشغيل Smart App Control. متابعة التثبيت...'
        ru='Smart App Control отключен. Продолжаем установку...'
    }
    'sac_off_reboot_hint' = @{
        en='Windows may need a restart for this to apply. If the game does not open, restart your PC and run the installer again.'
        es='Es posible que Windows necesite un reinicio para aplicar el cambio. Si el juego no abre, reinicia el PC y vuelve a ejecutar el instalador.'
        fr='Windows devra peut-etre redemarrer pour appliquer le changement. Si le jeu ne s''ouvre pas, redemarrez le PC et relancez l''installateur.'
        zh='Windows 可能需要重启才能生效。如果游戏无法打开，请重启电脑并重新运行安装程序。'
        hi='इसे लागू करने के लिए Windows को पुनः आरंभ की आवश्यकता हो सकती है। यदि गेम नहीं खुलता, तो पीसी पुनः प्रारंभ करें और इंस्टॉलर फिर से चलाएँ।'
        ar='قد يحتاج Windows إلى إعادة تشغيل لتطبيق هذا التغيير. إذا لم يفتح Minecraft، فأعد تشغيل الكمبيوتر وشغّل المثبّت مرة أخرى.'
        ru='Для применения может потребоваться перезагрузка Windows. Если игра не откроется, перезагрузите ПК и снова запустите установщик.'
    }
    'sac_off_need_reboot' = @{
        en='Could not apply the Smart App Control change. Restart your PC and run the installer again.'
        es='No se pudo aplicar el cambio de Smart App Control. Reinicia el PC y vuelve a ejecutar el instalador.'
        fr='Impossible d''appliquer le changement de Smart App Control. Redemarrez le PC et relancez l''installateur.'
        zh='无法应用 Smart App Control 更改。请重启电脑并重新运行安装程序。'
        hi='Smart App Control परिवर्तन लागू नहीं किया जा सका। पीसी पुनः प्रारंभ करें और इंस्टॉलर फिर से चलाएँ।'
        ar='تعذّر تطبيق تغيير Smart App Control. أعد تشغيل الكمبيوتر وشغّل المثبّت مرة أخرى.'
        ru='Не удалось применить изменение Smart App Control. Перезагрузите ПК и снова запустите установщик.'
    }
    'sac_off_write_fail' = @{
        en='Could not WRITE the Smart App Control registry key (access denied). A restart will NOT fix this. Check that an antivirus/policy is not protecting the registry, run as administrator and try again - or turn it off via Windows Security: App & browser control > Smart App Control settings.'
        es='No se pudo ESCRIBIR la clave de registro de Smart App Control (acceso denegado). Un reinicio NO lo arregla. Verifica que un antivirus/politica no proteja el registro, ejecuta como administrador e intenta de nuevo - o desactívalo en Seguridad de Windows: App y control del navegador > Smart App Control settings.'
        fr='Impossible d''ECRIRE la cle de registre de Smart App Control (acces refuse). Un redemarrage NE corrige PAS cela. Verifiez qu''un antivirus/une strategie ne protege pas le registre, lancez en tant qu''administrateur et reessayez - ou desactivez-le via Securite Windows : Controle d''application et de navigateur > Smart App Control settings.'
        zh='无法写入 Smart App Control 注册表键（拒绝访问）。重启无法解决此问题。请检查是否有杀毒软件/策略保护注册表，以管理员身份运行后重试，或在 Windows 安全中心关闭：应用和浏览器控制 > Smart App Control 设置。'
        hi='Smart App Control रजिस्ट्री कुंजी लिखने में विफल (पहुँच अस्वीकृत)। रीस्टार्ट से यह ठीक नहीं होगा। जाँचें कि कोई एंटीवायरस/नीति रजिस्ट्री की रक्षा न कर रहा हो, व्यवस्थापक के रूप में चलाएँ और पुनः प्रयास करें - या Windows Security से बंद करें: App & browser control > Smart App Control settings।'
        ar='تعذّرت كتابة مفتاح التسجيل الخاص بـ Smart App Control (تم رفض الوصول). إعادة التشغيل لن تحل المشكلة. تحقق من عدم حماية تسجيل بواسطة برنامج مكافحة فيروسات/سياسة، وشغّل كمسؤول وأعد المحاولة - أو أوقفه من أمان Windows: التحكم في التطبيق والمتصفح > إعدادات Smart App Control.'
        ru='Не удалось ЗАПИСАТЬ ключ реестра Smart App Control (отказано в доступе). Перезагрузка это НЕ исправит. Проверьте, не защищает ли реестр антивирус/политика, запустите от имени администратора и повторите - или отключите через Безопасность Windows: Управление приложениями и браузером > Smart App Control settings.'
    }
    'sac_skip_launch' = @{
        en='Smart App Control was turned off, but Windows only allows Minecraft after a restart. The game was NOT opened. Restart your PC and run the installer again.'
        es='Smart App Control se desactivo, pero Windows solo permite Minecraft despues de reiniciar. El juego NO se abrio. Reinicia el PC y vuelve a ejecutar el instalador.'
        fr='Smart App Control a ete desactive, mais Windows ne libere Minecraft qu''apres un redemarrage. Le jeu n''a PAS ete ouvert. Redemarrez le PC et relancez l''installateur.'
        zh='Smart App Control 已关闭，但 Windows 需重启后才能运行 Minecraft。游戏未打开。请重启电脑并重新运行安装程序。'
        hi='Smart App Control बंद हो गया, लेकिन Windows पुनः आरंभ के बाद ही Minecraft को अनुमति देता है। गेम नहीं खोला गया। पीसी पुनः प्रारंभ करें और इंस्टॉलर फिर से चलाएँ।'
        ar='تم إيقاف تشغيل Smart App Control، لكن Windows يسمح بتشغيل Minecraft بعد إعادة التشغيل فقط. لم يتم فتح اللعبة. أعد تشغيل الكمبيوتر وشغّل المثبّت مرة أخرى.'
        ru='Smart App Control отключен, но Windows разрешает Minecraft только после перезагрузки. Игра НЕ открыта. Перезагрузите ПК и снова запустите установщик.'
    }
    'err_acl_admin' = @{
        en='The Minecraft folder is still blocked for writing EVEN with administrator permission applied. This is usually caused by a third-party antivirus (ransomware/protected-folders protection) or a security policy. Check which antivirus is installed, allow/exclude the Minecraft folder in it, and run the installer again.'
        es='La carpeta de Minecraft sigue bloqueada para escritura INCLUSO con permiso de administrador aplicado. Normalmente lo causa un antivirus de terceros (proteccion anti-ransomware o carpeta protegida) o una politica de seguridad. Comprueba que antivirus esta instalado, permite/excluye la carpeta de Minecraft en el y vuelve a ejecutar el instalador.'
        fr='Le dossier Minecraft reste bloque en ecriture MEME avec la permission administrateur appliquee. C''est generalement cause par un antivirus tiers (protection anti-ransomware ou dossiers proteges) ou une strategie de securite. Verifiez quel antivirus est installe, autorisez/excluez le dossier Minecraft dans celui-ci, puis relancez l''installateur.'
        zh='即使已获得管理员权限，Minecraft 文件夹仍然无法写入。这通常是由第三方杀毒软件（勒索软件/受保护文件夹防护）或安全策略导致的。请检查安装了哪个杀毒软件，在其中允许/排除 Minecraft 文件夹，然后重新运行安装程序。'
        hi='Minecraft फ़ोल्डर अभी भी लेखन के लिए अवरुद्ध है, प्रशासक अनुमति लागू होने के बावजूद भी। यह आमतौर पर थर्ड-पार्टी एंटीवायरस (रैंसमवेयर/संरक्षित-फ़ोल्डर सुरक्षा) या सुरक्षा नीति के कारण होता है। जाँचें कि कौन सा एंटीवायरस स्थापित है, उसमें Minecraft फ़ोल्डर को अनुमति दें/बहिष्कृत करें, और इंस्टॉलर फिर से चलाएँ।'
        ar='مجلد Minecraft لا يزال محظورًا ضد الكتابة حتى مع تطبيق إذن المسؤول. عادةً ما يسبب هذا برنامج مكافحة فيروسات تابع لجهة خارجية (حماية من برامج الفدية/المجلدات المحمية) أو سياسة أمان. تحقق من برنامج مكافحة الفيروسات المثبت، واسمح/استبعد مجلد Minecraft فيه، ثم شغّل المثبّت مرة أخرى.'
        ru='Папка Minecraft по-прежнему заблокирована для записи, ДАЖЕ с применёнными правами администратора. Обычно это вызвано сторонним антивирусом (защита от шифровальщиков или защищённые папки) или политикой безопасности. Проверьте, какой антивирус установлен, разрешите/исключите папку Minecraft в нём и снова запустите установщик.'
    }
    'diag_avs' = @{
        en='Registered antivirus products (SecurityCenter2)'
        es='Antivirus registrados (SecurityCenter2)'
        fr='Antivirus enregistres (SecurityCenter2)'
        zh='已注册的杀毒软件 (SecurityCenter2)'
        hi='पंजीकृत एंटीवायरस उत्पाद (SecurityCenter2)'
        ar='برامج مكافحة الفيروسات المسجلة (SecurityCenter2)'
        ru='Зарегистрированные антивирусы (SecurityCenter2)'
    }
    'diag_avs_none' = @{
        en='no product registered'
        es='ningun producto registrado'
        fr='aucun produit enregistre'
        zh='未注册任何产品'
        hi='कोई उत्पाद पंजीकृत नहीं'
        ar='لا يوجد منتج مسجل'
        ru='нет зарегистрированных продуктов'
    }
    'diag_avs_unavail' = @{
        en='unavailable'
        es='no disponible'
        fr='indisponible'
        zh='不可用'
        hi='अनुपलब्ध'
        ar='غير متاح'
        ru='недоступно'
    }
    'diag_av_unavail' = @{
        en='unavailable (could not query Windows Defender)'
        es='no disponible (no se pudo consultar Windows Defender)'
        fr='indisponible (impossible d''interroger Windows Defender)'
        zh='不可用（无法查询 Windows Defender）'
        hi='अनुपलब्ध (Windows Defender से जानकारी नहीं मिली)'
        ar='غير متاح (تعذّر الاستعلام عن Windows Defender)'
        ru='недоступно (не удалось опросить Защитник Windows)'
    }
    'diag_cfa' = @{
        en='Controlled folder access (Defender)'
        es='Acceso controlado a carpetas (Defender)'
        fr='Acces controle aux dossiers (Defender)'
        zh='受控文件夹访问 (Defender)'
        hi='नियंत्रित फ़ोल्डर पहुँच (Defender)'
        ar='الوصول المتحكم به إلى المجلدات (Defender)'
        ru='Контролируемый доступ к папкам (Defender)'
    }
    'diag_cfa_on' = @{
        en='ON (blocks writes from untrusted apps)'
        es='ACTIVADO (bloquea escrituras de apps no confiables)'
        fr='ACTIF (bloque les ecritures d''apps non approuvees)'
        zh='已开启（阻止不受信任的应用写入）'
        hi='चालू (अविश्वसनीय ऐप्स से लेखन रोकता है)'
        ar='قيد التشغيل (يحظر الكتابة من التطبيقات غير الموثوقة)'
        ru='ВКЛЮЧЕН (блокирует запись из ненадёжных приложений)'
    }
    'diag_cfa_off' = @{
        en='off'
        es='desactivado'
        fr='desactive'
        zh='已关闭'
        hi='बंद'
        ar='متوقف'
        ru='отключен'
    }
    'diag_cfa_unavail' = @{
        en='unavailable'
        es='no disponible'
        fr='indisponible'
        zh='不可用'
        hi='अनुपलब्ध'
        ar='غير متاح'
        ru='недоступно'
    }
    'diag_acl_deny_removed' = @{
        en='deny ACEs removed'
        es='ACEs de denegacion eliminados'
        fr='ACE de refus supprimes'
        zh='已移除拒绝 ACE'
        hi='अस्वीकृत ACE हटाए गए'
        ar='تمت إزالة إدخالات رفض ACE'
        ru='запрещающие ACE удалены'
    }
    'diag_search' = @{
        en='Minecraft Content search state'
        es='Estado de la busqueda de Content'
        fr='Etat de la recherche de Content'
        zh='Minecraft Content 搜索状态'
        hi='Minecraft Content खोज स्थिति'
        ar='حالة البحث عن Content'
        ru='Состояние поиска Content'
    }
    'diag_search_pkg' = @{
        en='Microsoft.MinecraftUWP package'
        es='Paquete Microsoft.MinecraftUWP'
        fr='Package Microsoft.MinecraftUWP'
        zh='Microsoft.MinecraftUWP 程序包'
        hi='Microsoft.MinecraftUWP पैकेज'
        ar='حزمة Microsoft.MinecraftUWP'
        ru='Пакет Microsoft.MinecraftUWP'
    }
    'diag_search_noappx' = @{
        en='no package registered'
        es='ningun paquete registrado'
        fr='aucun package enregistre'
        zh='未注册任何程序包'
        hi='कोई पैकेज पंजीकृत नहीं'
        ar='لا توجد حزمة مسجلة'
        ru='нет зарегистрированных пакетов'
    }
    'diag_search_proc' = @{
        en='Minecraft.Windows process'
        es='Proceso Minecraft.Windows'
        fr='Processus Minecraft.Windows'
        zh='Minecraft.Windows 进程'
        hi='Minecraft.Windows प्रक्रिया'
        ar='عملية Minecraft.Windows'
        ru='Процесс Minecraft.Windows'
    }
    'diag_search_proc_none' = @{
        en='not running'
        es='no esta ejecutandose'
        fr='ne tourne pas'
        zh='未运行'
        hi='चालू नहीं'
        ar='غير قيد التشغيل'
        ru='не запущен'
    }
    'diag_probe_missing' = @{
        en='does not exist'
        es='no existe'
        fr='n''existe pas'
        zh='不存在'
        hi='मौजूद नहीं'
        ar='غير موجود'
        ru='не существует'
    }
    'diag_probe_noexe' = @{
        en='exists, no Minecraft.Windows.exe'
        es='existe, sin Minecraft.Windows.exe'
        fr='existe, sans Minecraft.Windows.exe'
        zh='存在，但没有 Minecraft.Windows.exe'
        hi='मौजूद है, Minecraft.Windows.exe नहीं'
        ar='موجود، بدون Minecraft.Windows.exe'
        ru='существует, без Minecraft.Windows.exe'
    }
    'report_trigger_install_error' = @{
        en='The installer ran into an error.'
        es='El instalador encontró un error.'
        fr='L''installateur a rencontré une erreur.'
        zh='安装程序遇到错误。'
        hi='इंस्टॉलर को एक त्रुटि मिली।'
        ar='واجه المثبّت خطأ.'
        ru='Установщик столкнулся с ошибкой.'
    }
    'report_trigger_start_failed' = @{
        en='Minecraft did not open after installing.'
        es='Minecraft no se abrió después de la instalación.'
        fr='Minecraft ne s''est pas ouvert après l''installation.'
        zh='安装后 Minecraft 未能打开。'
        hi='इंस्टॉल करने के बाद Minecraft नहीं खुला।'
        ar='لم يفتح Minecraft بعد التثبيت.'
        ru='Minecraft не открылся после установки.'
    }
    'report_trigger_game_crashed' = @{
        en='Minecraft opened and closed right away.'
        es='Minecraft se abrió y se cerró de inmediato.'
        fr='Minecraft s''est ouvert puis s''est fermé aussitôt.'
        zh='Minecraft 打开后立即关闭。'
        hi='Minecraft खुला और तुरंत बंद हो गया।'
        ar='تم فتح Minecraft وإغلاقه فورًا.'
        ru='Minecraft открылся и сразу закрылся.'
    }
    'corrupt_winmm_found' = @{
        en='A corrupted or incompatible winmm.dll was detected in the game (possible cause of the Bad Image 0xc0e90007 error).'
        es='Se detectó un winmm.dll corrupto o incompatible en el juego (posible causa del error Bad Image 0xc0e90007).'
        fr='Un winmm.dll corrompu ou incompatible a été détecté dans le jeu (cause possible de l''erreur Bad Image 0xc0e90007).'
        zh='检测到游戏中的 winmm.dll 已损坏或不兼容（可能是 Bad Image 0xc0e90007 错误的原因）。'
        hi='गेम में एक दूषित या असंगत winmm.dll मिला (Bad Image 0xc0e90007 त्रुटि का संभावित कारण)।'
        ar='تم اكتشاف winmm.dll تالف أو غير متوافق في اللعبة (سبب محتمل لخطأ Bad Image 0xc0e90007).'
        ru='Обнаружен поврежденный или несовместимый winmm.dll в игре (возможная причина ошибки Bad Image 0xc0e90007).'
    }
    'report_ask' = @{
        en='Do you want to send the report to the developer to help fix the problem? (Y for yes, N for no)'
        es='¿Desea enviar el informe al desarrollador para ayudar a corregir el problema? (S para sí, N para no)'
        fr='Voulez-vous envoyer le rapport au développeur pour aider à corriger le problème ? (O pour oui, N pour non)'
        zh='是否将报告发送给开发者以帮助修复问题？(S=发送，N=不发送)'
        hi='क्या आप समस्या ठीक करने में मदद के लिए रिपोर्ट डेवलपर को भेजना चाहते हैं? (S=हाँ, N=नहीं)'
        ar='هل تريد إرسال التقرير إلى المطور للمساعدة في إصلاح المشكلة؟ (S=نعم، N=لا)'
        ru='Отправить отчёт разработчику, чтобы помочь исправить проблему? (S=да, N=нет)'
    }
    'report_sent' = @{
        en='Report sent to the developer. Thank you!'
        es='Informe enviado al desarrollador. ¡Gracias!'
        fr='Rapport envoyé au développeur. Merci !'
        zh='报告已发送给开发者。谢谢！'
        hi='रिपोर्ट डेवलपर को भेज दी गई। धन्यवाद!'
        ar='تم إرسال التقرير إلى المطور. شكرًا!'
        ru='Отчёт отправлен разработчику. Спасибо!'
    }
    'report_not_sent' = @{
        en='OK, the report was not sent.'
        es='De acuerdo, el informe no se envió.'
        fr='D''accord, le rapport n''a pas été envoyé.'
        zh='好的，报告未发送。'
        hi='ठीक है, रिपोर्ट नहीं भेजी गई।'
        ar='حسنًا، لم يتم إرسال التقرير.'
        ru='Хорошо, отчёт не отправлен.'
    }
    'report_send_fail' = @{
        en='Could not send the report automatically.'
        es='No se pudo enviar el informe automáticamente.'
        fr='Impossible d''envoyer le rapport automatiquement.'
        zh='无法自动发送报告。'
        hi='रिपोर्ट स्वचालित रूप से नहीं भेजी जा सकी।'
        ar='تعذّر إرسال التقرير تلقائيًا.'
        ru='Не удалось отправить отчёт автоматически.'
    }
    'report_av_removed' = @{
        en='winmm.dll was removed or corrupted right after installing (antivirus?).'
        es='winmm.dll se eliminó o corrompió justo después de instalar (¿antivirus?).'
        fr='winmm.dll a été supprimé ou corrompu juste après l''installation (antivirus ?).'
        zh='winmm.dll 在安装后立即被删除或损坏（杀毒软件？）。'
        hi='इंस्टॉल करने के तुरंत बाद winmm.dll हटा दिया गया या दूषित हो गया (एंटीवायरस?)।'
        ar='تم حذف winmm.dll أو إتلافه مباشرة بعد التثبيت (مكافح فيروسات؟).'
        ru='winmm.dll был удалён или повреждён сразу после установки (антивирус?).'
    }
    'report_checking' = @{
        en='Checking that Minecraft opened correctly...'
        es='Comprobando que Minecraft se abrió correctamente...'
        fr='Vérification de l''ouverture correcte de Minecraft...'
        zh='正在检查 Minecraft 是否正常打开...'
        hi='यह जाँचा जा रहा है कि Minecraft सही ढंग से खुला...'
        ar='جارٍ التحقق من فتح Minecraft بشكل صحيح...'
        ru='Проверяем, что Minecraft открылся корректно...'
    }
}

function T {
    param([string]$Key)
    if ($Script:Lang -eq 'pt' -and $Script:PT.ContainsKey($Key)) {
        return $Script:PT[$Key]
    }
    $entry = $Script:I18N[$Key]
    if ($entry) {
        if ($entry[$Script:Lang]) {
            return $entry[$Script:Lang]
        }
        if ($entry['en']) {
            return $entry['en']
        }
    }
    return $Key
}

function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host "   __  __ _                            __ _   " -ForegroundColor Cyan
    Write-Host "  |  \/  (_)_ __   ___  ___ _ __ __ _ / _| |_ " -ForegroundColor Cyan
    Write-Host "  | |\/| | | '_ \ / _ \/ __| '__/ _' | |_| __|" -ForegroundColor Cyan
    Write-Host "  | |  | | | | | |  __/ (__| | | (_| |  _| |_ " -ForegroundColor Cyan
    Write-Host "  |_|  |_|_|_| |_|\___|\___|_|  \__,_|_|  \__|" -ForegroundColor Cyan
    Write-Host "     ____           _                 _        " -ForegroundColor Cyan
    Write-Host "    | __ )  ___  __| |_ __ ___   ___| | __    " -ForegroundColor Cyan
    Write-Host "    |  _ \ / _ \/ _' | '__/ _ \ / __| |/ /    " -ForegroundColor Cyan
    Write-Host "    | |_) |  __/ (_| | | | (_) | (__|   <     " -ForegroundColor Cyan
    Write-Host "    |____/ \___|\__,_|_|  \___/ \___|_|\_\    " -ForegroundColor Cyan
    Write-Host "                     Unlocker by CoelhoFZ      " -ForegroundColor Cyan
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host "                         v$Script:Version (PowerShell)" -ForegroundColor DarkGray
    Write-Host "  $(T 'banner_build_note')" -ForegroundColor Yellow
    Write-Host ""
}

function Get-TimeGreeting {
    $hour = (Get-Date).Hour
    if ($hour -ge 6 -and $hour -lt 12) {
        return T 'greet_morning'
    }
    elseif ($hour -ge 12 -and $hour -lt 18) {
        return T 'greet_afternoon'
    }
    else {
        return T 'greet_evening'
    }
}

function Get-MinecraftCandidates {
    $list = New-Object System.Collections.Generic.List[string]
    try {
        $appx = Get-AppxPackage -Name 'Microsoft.MinecraftUWP*' -AllUsers -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $appx) {
            $appx = Get-AppxPackage -Name 'Microsoft.MinecraftUWP*' -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if ($appx -and $appx.InstallLocation) {
            $list.Add($appx.InstallLocation)
            $sub = Join-Path $appx.InstallLocation 'Content'
            if ($sub -ne $appx.InstallLocation) {
                $list.Add($sub)
            }
        }
    } catch { }
    $list.Add('C:\XboxGames\Minecraft for Windows\Content')
    return $list
}

function Find-MinecraftContent {
    try {
        $proc = Get-Process Minecraft.Windows -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($proc -and $proc.Path) {
            $dir = Split-Path $proc.Path -Parent
            if ((Test-Path $dir) -and (Test-Path (Join-Path $dir 'Minecraft.Windows.exe'))) {
                return $dir
            }
        }
    } catch { }
    foreach ($c in Get-MinecraftCandidates) {
        if ((Test-Path $c) -and (Test-Path (Join-Path $c 'Minecraft.Windows.exe'))) {
            return $c
        }
    }
    $hasAppx = $false
    try {
        $appx = Get-AppxPackage -Name 'Microsoft.MinecraftUWP*' -ErrorAction SilentlyContinue | Select-Object -First 1
        $hasAppx = [bool]($appx -and $appx.InstallLocation)
    } catch { }
    if ($hasAppx) {
        throw (T 'err_package_incomplete')
    }
    throw (T 'err_content_not_found')
}

function Test-DirectoryWritable {
    param([string]$Path)
    $Script:LastProbeError = $null
    $probe = Join-Path $Path ('.mbu-wtest-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $fs = [IO.File]::Open($probe, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $fs.Dispose()
        try {
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        } catch { }
        return $true
    } catch {
        $Script:LastProbeError = $_.Exception.Message
        try {
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        } catch { }
        return $false
    }
}

function Invoke-AclCmd {
    param([string]$Name, [string]$Exe, [string[]]$CmdArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = (& $Exe @CmdArgs 2>&1 | Out-String).Trim()
        $code = [int]$LASTEXITCODE
    } catch {
        $out = $_.Exception.Message
        $code = -1
    } finally {
        $ErrorActionPreference = $prev
    }
    if ($code -eq 0 -or -not $out) {
        return ($Name + '=' + $code)
    }
    $one = ($out -replace '\r?\n', ' | ').Trim()
    if ($one.Length -gt 200) {
        $one = $one.Substring(0, 200)
    }
    return ($Name + '=' + $code + ', ' + $Name + 'Err=' + $one)
}

function Ensure-ContentWritable {
    param([string]$Content)
    $diag = New-Object System.Collections.Generic.List[string]
    $adm = '*S-1-5-32-544'
    $sys = '*S-1-5-18'
    $user = $null
    try {
        $user = '*' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    } catch { }

    $ok = $false
    $diag.Add((Invoke-AclCmd 'takeown' 'takeown.exe' @('/f', $Content)))
    $diag.Add((Invoke-AclCmd 'grantAdm' 'icacls.exe' @($Content, '/grant', ($adm + ':(OI)(CI)F'))))
    $ok = Test-DirectoryWritable -Path $Content
    $diag.Add('probe1=' + $(if ($ok) {
        'ok'
    } else {
        'fail (' + $Script:LastProbeError + ')'
    }))
    if (-not $ok -and $user) {
        $diag.Add((Invoke-AclCmd 'grantUser' 'icacls.exe' @($Content, '/grant', ($user + ':(OI)(CI)F'))))
        $diag.Add((Invoke-AclCmd 'grantSys' 'icacls.exe' @($Content, '/grant', ($sys + ':(OI)(CI)F'))))
        $ok = Test-DirectoryWritable -Path $Content
        $diag.Add('probe2=' + $(if ($ok) {
            'ok'
        } else {
            'fail (' + $Script:LastProbeError + ')'
        }))
    }
    if (-not $ok) {
        $diag.Add((Invoke-AclCmd 'removeAdm' 'icacls.exe' @($Content, '/remove', $adm)))
        $diag.Add((Invoke-AclCmd 'reGrantAdm' 'icacls.exe' @($Content, '/grant', ($adm + ':(OI)(CI)F'))))
        $ok = Test-DirectoryWritable -Path $Content
        $diag.Add('probe3=' + $(if ($ok) {
            'ok'
        } else {
            'fail (' + $Script:LastProbeError + ')'
        }))
    }
    if (-not $ok) {
        $denyRemoved = $false
        try {
            $acl = Get-Acl -LiteralPath $Content
            foreach ($ace in @($acl.Access)) {
                if ($ace.AccessControlType -eq [Security.AccessControl.AccessControlType]::Deny -and $ace.IsInherited -eq $false) {
                    $acl.RemoveAccessRuleSpecific($ace) | Out-Null
                    $denyRemoved = $true
                }
            }
            if ($denyRemoved) {
                Set-Acl -LiteralPath $Content -AclObject $acl
            }
        } catch { }
        $diag.Add('denyRemoved=' + $(if ($denyRemoved) {
            'yes'
        } else {
            'no'
        }))
        $diag.Add((Invoke-AclCmd 'reTakeown' 'takeown.exe' @('/f', $Content)))
        $diag.Add((Invoke-AclCmd 'reGrantAdm2' 'icacls.exe' @($Content, '/grant', ($adm + ':(OI)(CI)F'))))
        if ($user) {
            $diag.Add((Invoke-AclCmd 'reGrantUser' 'icacls.exe' @($Content, '/grant', ($user + ':(OI)(CI)F'))))
        }
        $diag.Add((Invoke-AclCmd 'reGrantSys' 'icacls.exe' @($Content, '/grant', ($sys + ':(OI)(CI)F'))))
        $ok = Test-DirectoryWritable -Path $Content
        $diag.Add('probe4=' + $(if ($ok) {
            'ok'
        } else {
            'fail (' + $Script:LastProbeError + ')'
        }))
    }
    $winmm = Join-Path $Content 'winmm.dll'
    if ($ok -and (Test-Path $winmm)) {
        Set-ItemProperty -Path $winmm -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        & takeown.exe /f $winmm 2>&1 | Out-Null
        $diag.Add((Invoke-AclCmd 'takeownFile' 'takeown.exe' @('/f', $winmm)))
        $diag.Add((Invoke-AclCmd 'grantFile' 'icacls.exe' @($winmm, '/grant', ($adm + ':(F)'))))
    }
    $Script:AclDiag = ($diag -join ', ')
    return $ok
}

function Get-InstalledUnlockLabel {
    try {
        $content = Find-MinecraftContent
    } catch {
        return $null
    }
    $winmm = Join-Path $content 'winmm.dll'
    if (-not (Test-Path $winmm)) {
        return $null
    }
    $actual = Get-SafeFileHash -Path $winmm
    if (-not $actual) {
        return $null
    }
    if ($unlockBuildLabels.ContainsKey($actual)) {
        return $unlockBuildLabels[$actual]
    }
    if ($unlockBuildLabelsArm64.ContainsKey($actual)) {
        return $unlockBuildLabelsArm64[$actual]
    }
    return ('<hash:' + $actual.Substring(0, 12) + '>')
}

function Get-GameVersion {
    param([string]$Content)
    if (-not $Content) {
        try {
            $Content = Find-MinecraftContent
        } catch {
            return $null
        }
    }
    $exe = Join-Path $Content 'Minecraft.Windows.exe'
    if (Test-Path $exe) {
        try {
            $fv = (Get-Item $exe -ErrorAction Stop).VersionInfo.FileVersion
            if ($fv) {
                return [string]$fv
            }
        } catch { }
    }
    try {
        $appx = Get-AppxPackage -Name 'Microsoft.MinecraftUWP*' -ErrorAction Stop | Select-Object -First 1
        if ($appx -and $appx.Version) {
            return [string]$appx.Version
        }
    } catch { }
    return $null
}

function Get-TestedVersionData {
    if ($null -ne $Script:TestedVersionData) {
        return $Script:TestedVersionData
    }
    $Script:TestedVersionData = $false
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $tmp = Join-Path (Get-TempDir) 'mbu-tested-versions.json'
        Invoke-WebRequest -UseBasicParsing -Uri "$base/tested-versions.json" -OutFile $tmp -TimeoutSec 8
        $Script:TestedVersionData = Get-Content $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    } catch { }
    return $Script:TestedVersionData
}

function Test-GameVersionTested {
    param([string]$Version)
    $data = Get-TestedVersionData
    if (-not $data -or -not $data.tested) {
        return $null
    }
    return [bool]($data.tested.PSObject.Properties.Name -contains $Version)
}

function Test-UnlockCache {
    $cached = Join-Path $cacheDir 'winmm.dll'
    if (-not (Test-Path $cached)) {
        return $null
    }
    $h = Get-SafeFileHash -Path $cached
    if ($h -eq $expectedHash) {
        return $cached
    }
    return $null
}

function Test-UnlockInstalled {
    $info = @{
        installed = $false
        hash = $null
        isArm64 = $false
        label = $null
        version = $null
    }
    try {
        $content = Find-MinecraftContent
    } catch {
        return $info
    }
    $winmm = Join-Path $content 'winmm.dll'
    if (-not (Test-Path $winmm)) {
        return $info
    }
    try {
        $actual = Get-SafeFileHash -Path $winmm
        $info.hash = $actual
        $machine = Get-PeMachineType -Path (Join-Path $content 'Minecraft.Windows.exe')
        if (-not $machine) {
            $info.installed = ($knownUnlockHashes -contains $actual) -or
                              ($knownUnlockHashesArm64 -contains $actual) -or
                              ($expectedHash -eq $actual) -or
                              ($expectedHashArm64 -eq $actual)
            $info.label = Get-InstalledUnlockLabel
            return $info
        }
        if ($machine -eq 0xAA64) {
            $info.isArm64 = $true
            $info.installed = ($knownUnlockHashesArm64 -contains $actual) -or ($expectedHashArm64 -eq $actual)
        } else {
            $info.installed = ($knownUnlockHashes -contains $actual) -or ($expectedHash -eq $actual)
        }
        if ($info.installed) {
            $info.label = Get-InstalledUnlockLabel
            $info.version = Get-GameVersion -Content $content
        }
    } catch { }
    return $info
}

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SafeFileHash {
    param([string]$Path)
    try {
        $h = Get-FileHash -Path $Path -Algorithm SHA256 -ErrorAction Stop
        if ($h -and $h.Hash) {
            return $h.Hash.ToLowerInvariant()
        }
    } catch { }
    return $null
}

function Test-MotW {
    param([string]$Path)
    try {
        $z = Get-Item -LiteralPath $Path -Stream Zone.Identifier -ErrorAction Stop
        if ($z) {
            return 'yes'
        }
    } catch { }
    return 'no'
}

function Test-CfaEnabled {
    try {
        $cfa = (Get-MpPreference -ErrorAction Stop).EnableControlledFolderAccess
        return ($cfa -eq 1)
    } catch {
        return $false
    }
}

function Add-DefenderExclusions {
    param([string[]]$Paths)
    $effective = @()
    $attemptedNow = @($Paths | Where-Object {
        $_
    })
    $attemptedNow += 'Minecraft.Windows.exe'
    $Script:DefenderExclAttempted = @(@($Script:DefenderExclAttempted) + $attemptedNow | Select-Object -Unique)
    foreach ($p in $Paths) {
        if (-not $p) {
            continue
        }
        try {
            Add-MpPreference -ExclusionPath $p -ErrorAction Stop
            $effective += $p
        } catch { }
    }
    try {
        Add-MpPreference -ExclusionProcess 'Minecraft.Windows.exe' -ErrorAction Stop
        $effective += 'Minecraft.Windows.exe'
    } catch { }
    $Script:DefenderExclEffective = @(@($Script:DefenderExclEffective) + $effective | Select-Object -Unique)
    return $effective
}

function Repair-UnlockSwapSidecars {
    param([string]$Content)
    $winmm = Join-Path $Content 'winmm.dll'
    try {
        $sidecars = @(Get-ChildItem -LiteralPath $Content -Filter 'winmm.dll.mbu-prev-*' -Force -ErrorAction SilentlyContinue)
    } catch {
        $sidecars = @()
    }
    foreach ($f in $sidecars) {
        try {
            if (Test-Path -LiteralPath $winmm) {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
            } else {
                Move-Item -LiteralPath $f.FullName -Destination $winmm -Force -ErrorAction Stop
            }
        } catch { }
    }
}

function Undo-UnlockSwap {
    param([string]$Content)
    $prev = $Script:SwapPrevDll
    if (-not $prev -or -not (Test-Path -LiteralPath $prev)) {
        return $false
    }
    $winmm = Join-Path $Content 'winmm.dll'
    try {
        Remove-Item -LiteralPath $winmm -Force -ErrorAction SilentlyContinue
        Move-Item -LiteralPath $prev -Destination $winmm -Force -ErrorAction Stop
        $Script:SwapPrevDll = $null
        return $true
    } catch {
        return $false
    }
}

function Clear-UnlockSwapPrev {
    param([string]$Content)
    $prev = $Script:SwapPrevDll
    $Script:SwapPrevDll = $null
    try {
        if ($prev -and (Test-Path -LiteralPath $prev)) {
            Remove-Item -LiteralPath $prev -Force -ErrorAction SilentlyContinue
        }
    } catch { }
}

function Get-ThirdPartyAvNames {
    $names = New-Object System.Collections.Generic.List[string]
    try {
        $avs = Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName 'AntiVirusProduct' -ErrorAction Stop
        foreach ($av in @($avs)) {
            $name = [string]$av.displayName
            if (-not $name) {
                continue
            }
            if ($name -match 'Windows Defender|Microsoft Defender') {
                continue
            }
            $rtpOn = $false
            try {
                $ps = [int]$av.productState
                $rtpOn = ((($ps -shr 12) -band 0xF) -in @(1, 2))
            } catch { }
            if ($rtpOn -and -not $names.Contains($name)) {
                $names.Add($name)
            }
        }
    } catch { }
    return @($names)
}

function Write-UnlockDllAtomic {
    param([string]$SourceDll, [string]$Content, [string]$CheckHash)
    $winmm = Join-Path $Content 'winmm.dll'
    $Script:LastOpErrorRecord = $null
    $Script:SwapPrevDll = $null
    $Script:SwapDiag = New-Object System.Collections.Generic.List[string]
    Remove-Item (Join-Path $Content 'winmm.dll.new') -Force -ErrorAction SilentlyContinue
    Repair-UnlockSwapSidecars -Content $Content
    $prevSeen = 'none'
    if (Test-Path $winmm) {
        try {
            $prevSeen = [string](Get-SafeFileHash -Path $winmm)
        } catch {
            $prevSeen = 'unreadable'
        }
        if ($prevSeen.Length -gt 12) {
            $prevSeen = $prevSeen.Substring(0, 12)
        }
    }
    $Script:SwapDiag.Add("prev=$prevSeen")
    $swapDone = $false
    $lastErr = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $stagedDll = Join-Path $Content ('winmm.dll.new-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $prevDll = Join-Path $Content ('winmm.dll.mbu-prev-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $prevMoved = $false
        try {
            Copy-Item $SourceDll $stagedDll -Force -ErrorAction Stop
            if ($CheckHash -and (Get-SafeFileHash -Path $stagedDll) -ne $CheckHash) {
                throw (T 'err_copy_corrupt')
            }
            if (Test-Path $winmm) {
                Move-Item $winmm $prevDll -Force -ErrorAction Stop
                $prevMoved = $true
                $Script:SwapPrevDll = $prevDll
            }
            if (Test-Path $winmm) {
                throw (T 'err_replace')
            }
            Move-Item $stagedDll $winmm -Force -ErrorAction Stop
            $swapDone = $true
            break
        } catch {
            $lastErr = $_.Exception
            if (-not $Script:LastOpErrorRecord) {
                $Script:LastOpErrorRecord = $_
            }
            if ($prevMoved -and -not (Test-Path $winmm)) {
                try {
                    Move-Item $prevDll $winmm -Force -ErrorAction Stop
                    $Script:SwapPrevDll = $null
                } catch {
                    $Script:SwapDiag.Add("rollback=fail attempt=$attempt kept=$([IO.Path]::GetFileName($prevDll))")
                }
            }
            if ($attempt -lt 3) {
                $null = Ensure-ContentWritable -Content $Content
                Start-Sleep -Seconds 2
            }
        } finally {
            if (-not $swapDone) {
                Remove-Item $stagedDll -Force -ErrorAction SilentlyContinue
            }
        }
    }
    if ($swapDone) {
        $kept = 'no'
        if ($Script:SwapPrevDll -and (Test-Path -LiteralPath $Script:SwapPrevDll)) {
            $kept = 'yes'
        }
        $Script:SwapDiag.Add("published=$attempt prev-kept=$kept")
        return
    }
    $finalState = if (Test-Path $winmm) {
        'prev-restored'
    } else {
        'no-winmm'
    }
    $Script:SwapDiag.Add("failed attempts=3 final=$finalState")
    $denied = $false
    try {
        $denied = ($lastErr -is [System.UnauthorizedAccessException])
    } catch { }
    if (-not $denied) {
        $denied = ("$lastErr" -match 'denied|negado')
    }
    if ($denied) {
        $avs = Get-ThirdPartyAvNames
        $who = if ($avs.Count -gt 0) {
            ($avs -join ', ')
        } else {
            T 'av_generic_name'
        }
        throw ((T 'err_write_blocked') -replace '\{0\}', $who)
    }
    throw $lastErr
}

function Show-ThirdPartyAvWarning {
    try {
        $avs = Get-ThirdPartyAvNames
        if ($avs.Count -gt 0) {
            Write-Host ''
            Write-Host ("  " + ((T 'warn_third_party_av') -replace '\{0\}', ($avs -join ', '))) -ForegroundColor Yellow
            Write-Host ''
        }
    } catch { }
}

function Close-Minecraft {
    $p = Get-Process Minecraft.Windows -ErrorAction SilentlyContinue
    if ($p) {
        Write-Host (T 'closing_mc')
        $p | Stop-Process -Force -ErrorAction SilentlyContinue
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Milliseconds 500
            if (-not (Get-Process Minecraft.Windows -ErrorAction SilentlyContinue)) {
                break
            }
        }
        Start-Sleep -Seconds 1
    }
}

function Get-SmartAppControlState {
    try {
        $v = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -Name 'VerifiedAndReputablePolicyState' -ErrorAction Stop
        return [int]$v
    } catch {
        return 0
    }
}

function Test-SmartAppControlToggleSupported {
    try {
        $nv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $b = [int]$nv.CurrentBuildNumber
        $u = [int]$nv.UBR
    } catch {
        return $false
    }
    if ($b -eq 26100 -and $u -ge 8116) {
        return $true
    }
    if ($b -eq 26200 -and $u -ge 8116) {
        return $true
    }
    if ($b -eq 2800 -and $u -ge 1896) {
        return $true
    }
    return $false
}

function Disable-SmartAppControl {
    $Script:SacWriteFailed = $false
    try {
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -Name 'VerifiedAndReputablePolicyState' -Value 0 -Type DWord -ErrorAction Stop
    } catch {
        $Script:SacWriteFailed = $true
        return $false
    }
    $appliedNow = $false
    try {
        $p = Start-Process CiTool.exe -ArgumentList '-r' -WindowStyle Hidden -PassThru
        if ($p.WaitForExit(10000)) {
            $appliedNow = $true
        } else {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            } catch { }
        }
    } catch { }
    $ok = ((Get-SmartAppControlState) -eq 0)
    $Script:SacNeedsReboot = ($ok -and -not $appliedNow)
    return $ok
}

function Install-Unlocker {
    $Script:SacNeedsReboot = $false
    $Script:SacWriteFailed = $false
    $Script:LastOpErrorRecord = $null
    Show-ThirdPartyAvWarning
    $sac = Get-SmartAppControlState
    if ($sac -eq 1 -or $sac -eq 2) {
        Write-Host ''
        Write-Host "  $(T 'sac_warn_title')" -ForegroundColor Red
        Write-Host "  $(T 'sac_warn_body')"
        if (Test-SmartAppControlToggleSupported) {
            $answer = Read-Host "  $(T 'sac_ask_off')"
            if ($answer -match '^[syo]') {
                if (Disable-SmartAppControl) {
                    Write-Host "  $(T 'sac_off_ok')" -ForegroundColor Green
                    if ($Script:SacNeedsReboot) {
                        Write-Host "  $(T 'sac_off_reboot_hint')" -ForegroundColor Yellow
                    }
                } else {
                    if ($Script:SacWriteFailed) {
                        Write-Host "  $(T 'sac_off_write_fail')" -ForegroundColor Red
                    } else {
                        Write-Host "  $(T 'sac_off_need_reboot')" -ForegroundColor Yellow
                    }
                    return
                }
            } else {
                Write-Host "  $(T 'sac_continue')" -ForegroundColor Yellow
            }
        } else {
            $answer = Read-Host "  $(T 'sac_ask')"
            if ($answer -match '^[syo]') {
                try {
                    Start-Process 'windowsdefender://smartappcontrol'
                    Write-Host "  $(T 'sac_opened')" -ForegroundColor Yellow
                } catch {
                    try {
                        Start-Process 'windowsdefender:'
                    } catch { }
                    Write-Host "  $(T 'sac_open_fail')" -ForegroundColor Yellow
                }
                return
            }
            Write-Host "  $(T 'sac_continue')" -ForegroundColor Yellow
        }
    }
    $content = Find-MinecraftContent
    Write-Host ((T 'install_content_dir') -replace '\{0\}', $content)

    $gateMachine = Get-PeMachineType -Path (Join-Path $content 'Minecraft.Windows.exe')
    if ($gateMachine -ne 0xAA64) {
        $gateVer = Get-GameVersion -Content $content
        if ($gateVer -and (Test-GameVersionTested -Version $gateVer) -eq $false) {
            Write-Host ((T 'gate_untested') -replace '\{0\}', $gateVer) -ForegroundColor Red
            Write-Host (T 'gate_untested_hint') -ForegroundColor Yellow
            return
        }
    }

    if ((Get-PeMachineType -Path (Join-Path $content 'Minecraft.Windows.exe')) -eq 0xAA64) {
        $armPublicado = $true
        try {
            Invoke-WebRequest -UseBasicParsing -Method Head -Uri "$base/release/winmm-arm64.dll" -TimeoutSec 10 | Out-Null
        } catch {
            $stArm = $null
            try {
                $stArm = [int]$_.Exception.Response.StatusCode
            } catch { }
            if ($stArm -eq 404) {
                $armPublicado = $false
            }
        }
        if (-not $armPublicado) {
            Write-Host ''
            Write-Host (T 'arm64_no_release') -ForegroundColor Red
            Write-Host ((T 'track_releases') -replace '\{0\}', 'https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases') -ForegroundColor Yellow
            return
        }
    }

    $tmp = Join-Path (Get-TempDir) 'mbu'
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    if (-not (Test-Path -LiteralPath $tmp -PathType Container)) {
        throw ((T 'err_download_failed') -replace '\{0\}', $tmp)
    }
    $dll = Join-Path $tmp 'winmm.dll'
    try {
        $extraExcl = @()
        foreach ($cand in Get-MinecraftCandidates) {
            if ($cand -and ($cand -ne $content) -and (Test-Path $cand) -and (Test-Path (Join-Path $cand 'Minecraft.Windows.exe'))) {
                $extraExcl += $cand
            }
        }
        $excluded = Add-DefenderExclusions -Paths (@($tmp, $content, $cacheDir) + $extraExcl)
        if ($excluded.Count -gt 0) {
            Write-Host ((T 'av_exclusion_ok') -replace '\{0\}', ($excluded -join ', '))
        } else {
            Write-Host ((T 'av_exclusion_fail') -replace '\{0\}', "$tmp`n$content") -ForegroundColor Yellow
        }
        $machine = Get-PeMachineType -Path (Join-Path $content 'Minecraft.Windows.exe')
        $machineReadOk = ($machine -ne 0)
        if (-not $machineReadOk) {
            $machine = 0x8664
        }
        $isArm = ($machine -eq 0xAA64)
        $archLabel = if ($machine -eq 0xAA64) {
            'ARM64'
        } elseif ($machine -eq 0x8664) {
            'x64'
        } elseif ($machine -eq 0x014C) {
            'x86'
        } else {
            'unknown'
        }
        $machineHex = '0x{0:X4}' -f $machine
        if ($machineReadOk) {
            Write-Host (((T 'arch_line') -replace '\{0\}', $archLabel) -replace '\{1\}', $machineHex)
        } else {
            Write-Host (T 'arch_unknown') -ForegroundColor Yellow
        }
        if ($isArm) {
            Write-Host (T 'arm64_detected') -ForegroundColor Cyan
        }
        $checkHash = if ($isArm) {
            $expectedHashArm64
        } else {
            $expectedHash
        }
        Write-Host (T 'downloading_bin')
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $remoteDll = if ($isArm) {
            "$base/release/winmm-arm64.dll"
        } else {
            "$base/release/winmm.dll"
        }
        Start-Sleep -Seconds 2
        $actual = $null
        $netErr = $null
        $Script:DownloadDiag = New-Object System.Collections.Generic.List[string]
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            Remove-Item $dll -Force -ErrorAction SilentlyContinue
            try {
                Invoke-WebRequest -UseBasicParsing -Uri $remoteDll -OutFile $dll -TimeoutSec 20
                Unblock-File $dll -ErrorAction SilentlyContinue
                $Script:DownloadDiag.Add("t$attempt motw=" + (Test-MotW -Path $dll))
            } catch {
                $netErr = $_.Exception.Message
                $code = $null
                try {
                    $code = [int]$_.Exception.Response.StatusCode
                } catch { }
                $transient = ($code -in @(408, 429, 502, 503, 504)) -or
                             ($netErr -match '50[234]|429|408|timed out|Unable to connect|The connection was closed|The remote name could not be resolved')
                if ($transient -and $attempt -lt 3) {
                    Write-Host (((T 'retry_download') -replace '\{0\}', [string]$attempt) -replace '\{1\}', '3') -ForegroundColor Yellow
                    Start-Sleep -Seconds (3 * $attempt)
                    continue
                }
                $cached = if ($isArm) {
                    $null
                } else {
                    Test-UnlockCache
                }
                if ($cached) {
                    Copy-Item $cached $dll -Force
                    Unblock-File $dll -ErrorAction SilentlyContinue
                    Write-Host ((T 'cache_used') -replace '\{0\}', $cached) -ForegroundColor Yellow
                    $Script:DownloadDiag.Add("t$attempt cache-after-net-error")
                } else {
                    if ($isArm) {
                        Write-Host (T 'arm64_no_release') -ForegroundColor Red
                        Write-Host ((T 'track_releases') -replace '\{0\}', 'https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases') -ForegroundColor Yellow
                    }
                    if ($transient) {
                        throw (T 'err_download_unavailable')
                    }
                    throw ((T 'err_download_failed') -replace '\{0\}', $netErr)
                }
            }
            try {
                if ((Test-Path $dll) -and ((Get-Item $dll -Force -ErrorAction Stop).Length -gt 0)) {
                    $actual = Get-SafeFileHash -Path $dll
                }
            } catch {
                $actual = $null
            }
            if ($actual) {
                $Script:DownloadDiag.Add("t$attempt ok")
                break
            }
            $Script:DownloadDiag.Add("t$attempt missing/empty/hash-unreadable")
            $cacheNow = if ($isArm) {
                $null
            } else {
                Test-UnlockCache
            }
            if ($cacheNow) {
                Copy-Item $cacheNow $dll -Force
                Unblock-File $dll -ErrorAction SilentlyContinue
                try {
                    if ((Test-Path $dll) -and ((Get-Item $dll -Force -ErrorAction Stop).Length -gt 0)) {
                        $actual = Get-SafeFileHash -Path $dll
                    }
                } catch {
                    $actual = $null
                }
                if ($actual) {
                    Write-Host ((T 'cache_used') -replace '\{0\}', $cacheNow) -ForegroundColor Yellow
                    $Script:DownloadDiag.Add("t$attempt cache-ok")
                    break
                }
                $Script:DownloadDiag.Add("t$attempt cache-blocked")
            }
            if ($attempt -lt 3) {
                Write-Host (((T 'av_retrying') -replace '\{0\}', [string]$attempt) -replace '\{1\}', '3') -ForegroundColor Yellow
                $null = Add-DefenderExclusions -Paths @($tmp, $content)
                Start-Sleep -Seconds 5
            }
        }
        if (-not $actual) {
            $blockedMsg = (T 'err_av_blocked') -replace '\{0\}', ($excluded -join ', ')
            if (Test-CfaEnabled) {
                $blockedMsg = $blockedMsg + ' ' + (T 'av_cfa_hint')
            }
            throw $blockedMsg
        }
        if ($checkHash) {
            if ($actual -ne $checkHash) {
                throw ((T 'err_hash_invalid') -replace '\{0\}', $actual)
            }
        } elseif ($isArm) {
            Write-Host (T 'arm64_hash_skipped') -ForegroundColor Yellow
        }

        Close-Minecraft

        if (-not (Ensure-ContentWritable -Content $content)) {
            if (Test-IsAdmin) {
                throw (T 'err_acl_admin')
            }
            throw (T 'err_acl')
        }

        $winmm = Join-Path $content 'winmm.dll'
        $isKnownUnlock = $false
        if (Test-Path $winmm) {
            try {
                $installedHash = Get-SafeFileHash -Path $winmm
                $isKnownUnlock = (($knownUnlockHashes -contains $installedHash) -or
                                  ($knownUnlockHashesArm64 -contains $installedHash) -or
                                  ($expectedHash -eq $installedHash) -or
                                  ($expectedHashArm64 -eq $installedHash))
            } catch { }
        }
        if ((Test-Path $winmm) -and -not (Test-Path (Join-Path $content 'winmm.dll.orig')) -and -not $isKnownUnlock) {
            Copy-Item $winmm (Join-Path $content 'winmm.dll.orig') -Force
            Write-Host (T 'backup_orig')
        }

        foreach ($f in @('dlllist.txt','unlock-CoelhoFZ.dll','unlock-CoelhoFZ.ini','unlocker-CoelhoFZ.dll','unlocker-CoelhoFZ.ini','XGameCore.GDK.dll','XGameCore.GDK.ini')) {
            Remove-Item (Join-Path $content $f) -Force -ErrorAction SilentlyContinue
        }

        $null = Write-UnlockDllAtomic -SourceDll $dll -Content $content -CheckHash $checkHash
        if ($checkHash -and (Get-SafeFileHash -Path $winmm) -ne $checkHash) {
            if (-not (Undo-UnlockSwap -Content $content)) {
                $orig = Join-Path $content 'winmm.dll.orig'
                if (Test-Path $orig) {
                    Remove-Item $winmm -Force -ErrorAction SilentlyContinue
                    Copy-Item $orig $winmm -Force -ErrorAction SilentlyContinue
                }
            }
            throw (T 'err_av_quarantine')
        }
        Clear-UnlockSwapPrev -Content $content
        if (-not $isArm) {
            try {
                New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
                Copy-Item $winmm (Join-Path $cacheDir 'winmm.dll') -Force
                Write-Host ((T 'cache_saved') -replace '\{0\}', $cacheDir) -ForegroundColor DarkGray
            } catch { }
        }
        Write-Host (T 'install_ok')
        Send-DownloadHit
        if ($Script:SacNeedsReboot) {
            Write-Host (T 'sac_skip_launch') -ForegroundColor Yellow
            return
        }
        $mc = Start-Minecraft
        if (-not $mc.opened) {
            $sfReason = Get-WinmmCorruptHint -Content $content
            Send-MbuFailureReport -Trigger 'start_failed' -Reason $sfReason
            return
        }
        Write-Host (T 'report_checking')
        Start-Sleep -Seconds 3
        try {
            $after = Get-SafeFileHash -Path (Join-Path $content 'winmm.dll')
            if ($checkHash -and ($after -ne $checkHash)) {
                Send-MbuFailureReport -Trigger 'install_error' -Reason (T 'report_av_removed')
                return
            }
        } catch { }
        if (Test-PostLaunchCrash -MinecraftProcess $mc.proc) {
            $gcReason = Get-CrashDetailInfo -MinecraftProcess $mc.proc
            $gcHint = Get-WinmmCorruptHint -Content $content
            if ($gcHint) {
                $gcReason = $gcReason + ' | ' + $gcHint
            }
            Send-MbuFailureReport -Trigger 'game_crashed' -Reason $gcReason
        }
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}

function Remove-MbuLocalTraces {
    param([string]$Content)
    if ($Content) {
        try {
            foreach ($s in @(Get-ChildItem -LiteralPath $Content -Filter 'winmm.dll.mbu-prev-*' -Force -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $s.FullName -Force -ErrorAction SilentlyContinue
            }
        } catch { }
    }
    $tmpMbu = Join-Path (Get-TempDir) 'mbu'
    $rawMbu = $null
    try {
        if ($env:TEMP) {
            $rawMbu = Join-Path $env:TEMP 'mbu'
        }
    } catch { }
    $alvos = @($cacheDir, $tmpMbu)
    if ($rawMbu -and ($rawMbu -ne $tmpMbu)) {
        $alvos += $rawMbu
    }
    if ($Content) {
        $alvos += $Content
    }
    foreach ($p in @($cacheDir, $tmpMbu, $rawMbu)) {
        try {
            if ($p -and (Test-Path -LiteralPath $p)) {
                Remove-Item -Recurse -Force $p -ErrorAction SilentlyContinue
            }
        } catch { }
    }
    try {
        $pref = Get-MpPreference -ErrorAction Stop
        foreach ($p in @($pref.ExclusionPath)) {
            if ($p -and ($alvos -contains $p)) {
                try {
                    Remove-MpPreference -ExclusionPath $p -ErrorAction Stop
                } catch { }
            }
        }
        foreach ($p in @($pref.ExclusionProcess)) {
            if ($p -and ($p -match 'Minecraft\.Windows\.exe')) {
                try {
                    Remove-MpPreference -ExclusionProcess $p -ErrorAction Stop
                } catch { }
            }
        }
    } catch { }
}

function Restore-Original {
    $Script:LastOpErrorRecord = $null
    $content = Find-MinecraftContent
    Close-Minecraft

    $winmm = Join-Path $content 'winmm.dll'
    $orig = Join-Path $content 'winmm.dll.orig'

    if (-not (Test-UnlockInstalled) -and -not (Test-Path $orig)) {
        Write-Host (T 'nothing_to_restore')
        return
    }

    $removed = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $null = Ensure-ContentWritable -Content $content
        Remove-Item $winmm -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $winmm)) {
            $removed = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $removed) {
        throw (T 'err_replace')
    }

    if (Test-Path $orig) {
        Move-Item $orig $winmm -Force
        if (-not (Test-Path $winmm)) {
            throw (T 'err_replace')
        }
        Write-Host (T 'restored_ok')
    } else {
        Write-Host (T 'removed_ok')
    }

    Remove-MbuLocalTraces -Content $content
    Write-Host (T 'unlock_removed')
    Start-Minecraft
}

function Send-DownloadHit {
    try {
        Invoke-WebRequest -UseBasicParsing -Uri 'https://mbu-download-counter.xgobg2020.workers.dev/hit' -Method Post -TimeoutSec 5 | Out-Null
    } catch { }
}

function Start-Minecraft {
    $opened = $false
    $proc = $null
    try {
        $content = Find-MinecraftContent
        $appx = Get-AppxPackage -Name 'Microsoft.MinecraftUWP*' -ErrorAction SilentlyContinue | Select-Object -First 1
        $isStore = $appx -and ($content -eq $appx.InstallLocation)
        if ($isStore) {
            $appId = 'Game'
            try {
                $m = Get-AppxPackageManifest -Package $appx.PackageFullName -ErrorAction Stop
                $id = $m.Package.Applications.Application | Select-Object -First 1 -ExpandProperty Id
                if ($id) {
                    $appId = $id
                }
            } catch { }
            Start-Process "shell:AppsFolder\$($appx.PackageFamilyName)!$appId" -ErrorAction Stop
        } else {
            $exe = Join-Path $content 'Minecraft.Windows.exe'
            if (Test-Path $exe) {
                $proc = Start-Process -FilePath $exe -WorkingDirectory $content -PassThru -ErrorAction Stop
            } else {
                throw 'Executavel nao encontrado'
            }
        }
        $opened = $true
    } catch { }
    if (-not $opened) {
        try {
            Start-Process 'minecraft:' -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            if (Get-Process Minecraft.Windows -ErrorAction SilentlyContinue) {
                $opened = $true
            }
        } catch { }
    }
    if ($opened) {
        Write-Host (T 'mc_started')
    } else {
        Write-Host (T 'mc_start_failed')
    }
    return @{
        opened = $opened
        proc = $proc
    }
}

function Get-DefenderMbuExclusions {
    $found = @()
    $ok = $false
    try {
        $pref = Get-MpPreference -ErrorAction Stop
        $ok = $true
        $needles = @('\\mbu', 'XboxGames\\Minecraft', 'MinecraftUWP', 'Minecraft.Windows')
        foreach ($p in @($pref.ExclusionPath)) {
            if ($p -and ($needles | Where-Object {
                $p -match $_
            })) {
                $found += $p
            }
        }
        foreach ($p in @($pref.ExclusionProcess)) {
            if ($p -and ($needles | Where-Object {
                $p -match $_
            })) {
                $found += "proc: $p"
            }
        }
    } catch { }
    return [pscustomobject]@{
        ok    = $ok
        found = @($found)
    }
}

function Get-DiagReportText {
    param([string]$Reason = '', [System.Management.Automation.ErrorRecord]$ErrorRecord = $null)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(((T 'diag_title') -replace '\{0\}', $Script:Version))
    if ($Reason) {
        $lines.Add("$(T 'diag_reason'): $Reason")
    }
    try {
        $lines.Add("[temp] used=$(Get-TempDir) env=$env:TEMP tmp=$env:TMP local=$env:LOCALAPPDATA uprof=$env:USERPROFILE sysroot=$env:SystemRoot")
    } catch { }
    try {
        if ($Script:DownloadDiag -and $Script:DownloadDiag.Count -gt 0) {
            $lines.Add('[dl] ' + ($Script:DownloadDiag -join ' | '))
        }
    } catch { }
    try {
        $Script:ThirdPartyAv = @(Get-ThirdPartyAvNames)
    } catch {
        $Script:ThirdPartyAv = @()
    }
    try {
        if ($Script:SwapDiag -and $Script:SwapDiag.Count -gt 0) {
            $lines.Add('[swap] ' + (@($Script:SwapDiag | Select-Object -Unique) -join ' | '))
        }
    } catch { }
    try {
        $att = @($Script:DefenderExclAttempted)
        if ($att.Count -gt 0) {
            $eff = @($Script:DefenderExclEffective)
            $effTxt = 'none'
            if ($eff.Count -gt 0) {
                $effTxt = ($eff -join ', ')
            }
            $lines.Add('[defender] auto-exclusion attempted=' + ($att -join ', ') + ' effective=' + $effTxt)
        } else {
            $lines.Add('[defender] auto-exclusion not attempted')
        }
    } catch { }
    try {
        $threatNames = @{ }
        foreach ($th in @(Get-MpThreat -ErrorAction SilentlyContinue)) {
            try {
                $threatNames[[string]$th.ThreatID] = [string]$th.ThreatName
            } catch { }
        }
        $dets = @(Get-MpThreatDetection -ErrorAction SilentlyContinue)
        if ($dets.Count -gt 0) {
            $detParts = foreach ($det in ($dets | Select-Object -Last 3)) {
                $tid = ''
                $nm = '?'
                $res = ''
                $when = '?'
                try {
                    $tid = [string]$det.ThreatID
                } catch { }
                if ($tid -and $threatNames.ContainsKey($tid)) {
                    $nm = [string]$threatNames[$tid]
                } elseif ($tid) {
                    $nm = $tid
                }
                try {
                    $res = [string](@($det.Resources) | Select-Object -First 1)
                } catch { }
                try {
                    if ($det.InitialDetectionTime) {
                        $when = $det.InitialDetectionTime.ToString('MM-dd HH:mm')
                    }
                } catch { }
                "$nm @ $when -> $res"
            }
            $lines.Add('[threat] ' + ($detParts -join ' | '))
        } else {
            if (@($Script:ThirdPartyAv).Count -gt 0) {
                $lines.Add('[threat] none (Defender only, third-party AV active: ' + ($Script:ThirdPartyAv -join ', ') + ', its blocks do not appear here)')
            } else {
                $lines.Add('[threat] none')
            }
        }
    } catch { }
    try {
        $cfaEv = @(Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-Windows Defender/Operational'
            Id = 1123, 1124
            StartTime = (Get-Date).AddDays(-2)
        } -ErrorAction SilentlyContinue)
        if ($cfaEv.Count -gt 0) {
            $cfaWhen = '?'
            try {
                $cfaWhen = $cfaEv[0].TimeCreated.ToString('MM-dd HH:mm')
            } catch { }
            $lines.Add("[cfa] $($cfaEv.Count) blocked/audited event(s), latest $cfaWhen")
        } elseif (@($Script:ThirdPartyAv).Count -gt 0) {
            $lines.Add('[cfa] no Defender events (third-party AV active: ' + ($Script:ThirdPartyAv -join ', ') + ', not covered by this log)')
        }
    } catch { }
    $opRecord = $null
    try {
        if ($Script:LastOpErrorRecord) {
            $opRecord = $Script:LastOpErrorRecord
        }
    } catch { }
    $rec = if ($opRecord) {
        $opRecord
    } else {
        $ErrorRecord
    }
    if ($rec) {
        try {
            $inv = $rec.InvocationInfo
            $cmd = if ($inv -and $inv.MyCommand) {
                [string]$inv.MyCommand.Name
            } else {
                '?'
            }
            $src = if ($inv -and $inv.ScriptName) {
                [IO.Path]::GetFileName([string]$inv.ScriptName)
            } else {
                '?'
            }
            $lineNo = if ($inv) {
                [string]$inv.ScriptLineNumber
            } else {
                '0'
            }
            $cat = ''
            try {
                $cat = "$($rec.CategoryInfo.Category)/$($rec.CategoryInfo.Activity)"
            } catch { }
            $target = ''
            try {
                if ($rec.CategoryInfo.TargetName) {
                    $target = " target=$($rec.CategoryInfo.TargetName)"
                }
            } catch { }
            $detail = "[error] id=$($rec.FullyQualifiedErrorId) cmd=$cmd src=$src line=$lineNo cat=$cat$target"
            if ($detail.Length -gt 300) {
                $detail = $detail.Substring(0, 300)
            }
            $lines.Add($detail)
        } catch { }
    }
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $osLine = "$($os.Caption) build $($os.BuildNumber)"
    } catch {
        $osLine = 'Windows (unknown)'
    }
    try {
        $psLine = $PSVersionTable.PSVersion.ToString()
    } catch {
        $psLine = '?'
    }
    $isAdmin = Test-IsAdmin
    $yesNo = {
        param($b) if ($b) {
            T 'diag_yes'
        } else {
            T 'diag_no'
        }
    }
    $lines.Add("$(T 'diag_os'): $osLine")
    $lines.Add("$(T 'diag_ps'): $psLine")
    $lines.Add("$(T 'diag_admin'): $(& $yesNo $isAdmin)")
    $lines.Add("$(T 'diag_date'): $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz'))")
    try {
        if ($os -and $os.OSArchitecture) {
            $lines.Add("$(T 'diag_os_arch'): $($os.OSArchitecture) (session $env:PROCESSOR_ARCHITECTURE)")
        }
    } catch { }
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($cpu -and $cpu.Name) {
            $cpuArch = '0x{0:X}' -f ([int]$cpu.Architecture)
            $lines.Add("$(T 'diag_cpu'): $($cpu.Name.Trim()) (Arch=$cpuArch)")
        }
    } catch { }
    $gameVer = $null
    try {
        $content = Find-MinecraftContent
        $appx = Get-AppxPackage -Name 'Microsoft.MinecraftUWP*' -ErrorAction SilentlyContinue | Select-Object -First 1
        $source = if ($appx -and ($content -eq $appx.InstallLocation)) {
            T 'diag_source_store'
        }
                  elseif ($content -like 'C:\XboxGames*') {
            T 'diag_source_gdk'
        }
                  else {
            T 'diag_source_unknown'
        }
        $lines.Add("$(T 'diag_content'): $content")
        $lines.Add("$(T 'diag_source'): $source")
        if ($appx -and $appx.PackageFullName) {
            $lines.Add("$(T 'diag_pkg'): $($appx.PackageFullName) | Arch=$($appx.Architecture) | v$($appx.Version)")
        }
        $machine = Get-PeMachineType -Path (Join-Path $content 'Minecraft.Windows.exe')
        $arch = if ($machine -eq 0xAA64) {
            'ARM64'
        } elseif ($machine -eq 0x8664) {
            'x64'
        } elseif ($machine -eq 0x014C) {
            'x86'
        } else {
            '?'
        }
        $gameVer = Get-GameVersion -Content $content
        if ($gameVer) {
            $lines.Add("$(T 'diag_game_version'): $gameVer")
        }
        $lines.Add("$(T 'diag_game_arch'): $arch (Machine=$(if ($machine) { '0x{0:X4}' -f $machine } else { T 'diag_machine_unreadable' }))")
        foreach ($cand in Get-MinecraftCandidates) {
            if (-not (Test-Path $cand)) {
                continue
            }
            if (-not (Test-Path (Join-Path $cand 'Minecraft.Windows.exe'))) {
                continue
            }
            $cwm = Join-Path $cand 'winmm.dll'
            $cstateKey = if (Test-Path $cwm) {
                'diag_cand_present'
            } else {
                'diag_cand_absent'
            }
            $cmark = if ($cand -eq $content) {
                '  ' + (T 'diag_cand_used')
            } else {
                ''
            }
            $lines.Add("$(T 'diag_cand_label') $cand  ($(T $cstateKey))$cmark")
        }
        $wst = Get-WinmmDiskState -Content $content
        $wline = '[winmm] ' + $(if ($wst.present) {
            'present'
        } else {
            'absent'
        })
        if ($wst.present) {
            $wline += ', size=' + $wst.size + 'B, sha=' + $wst.hash + ', pe=' + $wst.peLabel
            $worig = Join-Path $content 'winmm.dll.orig'
            $match = 'unknown'
            if ($wst.hash -eq $expectedHash) {
                $match = 'expected'
            }
            elseif ($knownUnlockHashes -contains $wst.hash -or $knownUnlockHashesArm64 -contains $wst.hash -or $expectedHashArm64 -eq $wst.hash) {
                $match = 'known'
            }
            elseif ((Test-Path $worig) -and ((Get-SafeFileHash -Path $worig) -eq $wst.hash)) {
                $match = 'orig'
            }
            $wline += ', match=' + $match
            if ($match -eq 'unknown' -or -not $wst.peValid) {
                $wline += '  [corrupt/unknown - possible Bad Image]'
            }
        }
        $lines.Add($wline)
    } catch {
        $lines.Add("$(T 'diag_content'): $($_.Exception.Message)")
        $lines.Add("$(T 'diag_search'):")
        try {
            $probeAppx = Get-AppxPackage -Name 'Microsoft.MinecraftUWP*' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($probeAppx -and $probeAppx.InstallLocation) {
                $lines.Add("  $(T 'diag_search_pkg'): $($probeAppx.PackageFullName) | Arch=$($probeAppx.Architecture) | v$($probeAppx.Version) | $($probeAppx.InstallLocation)")
            } else {
                $lines.Add("  $(T 'diag_search_pkg'): $(T 'diag_search_noappx')")
            }
        } catch { }
        foreach ($probe in Get-MinecraftCandidates) {
            try {
                if (-not (Test-Path -LiteralPath $probe)) {
                    $lines.Add("  $(T 'diag_cand_label') $probe : $(T 'diag_probe_missing')")
                } elseif (-not (Test-Path -LiteralPath (Join-Path $probe 'Minecraft.Windows.exe'))) {
                    $lines.Add("  $(T 'diag_cand_label') $probe : $(T 'diag_probe_noexe')")
                }
            } catch { }
        }
        try {
            $probeProc = Get-Process Minecraft.Windows -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($probeProc) {
                $pp = try {
                    $probeProc.Path
                } catch {
                    '?'
                }
                $lines.Add("  $(T 'diag_search_proc'): $(T 'diag_yes') ($pp)")
            } else {
                $lines.Add("  $(T 'diag_search_proc'): $(T 'diag_search_proc_none')")
            }
        } catch { }
    }
    $state = Test-UnlockInstalled
    $unlockLine = if ($state.installed) {
        if ($state.label) {
            $state.label
        } else {
            "$(T 'diag_yes') ($($state.hash))"
        }
    } else {
        T 'diag_unlock_none'
    }
    $lines.Add("$(T 'diag_unlock'): $unlockLine")
    if ($state.hash) {
        $lines.Add("  $(T 'diag_winmm_hash'): $($state.hash)")
    }
    $tested = if ($gameVer) {
        Test-GameVersionTested -Version $gameVer
    } else {
        $null
    }
    $testedLine = if ($null -eq $tested -or -not $gameVer) {
        T 'diag_tested_unknown'
    }
                  elseif ($tested) {
        T 'diag_tested_ok'
    }
                  else {
        T 'diag_tested_bad'
    }
    $lines.Add("$(T 'diag_tested'): $testedLine")
    $exclInfo = Get-DefenderMbuExclusions
    $exclLine = if (-not $exclInfo.ok) {
        T 'diag_av_unavail'
    } elseif ($exclInfo.found.Count -gt 0) {
        $exclInfo.found -join ', '
    } else {
        T 'diag_av_none'
    }
    $lines.Add("$(T 'diag_av'): $exclLine")
    $cached = Test-UnlockCache
    $cacheLine = if ($cached) {
        (T 'diag_cache_ok') -replace '\{0\}', $cached
    } elseif (Test-Path (Join-Path $cacheDir 'winmm.dll')) {
        T 'diag_cache_bad'
    } else {
        T 'diag_cache_none'
    }
    $lines.Add("$(T 'diag_cache'): $cacheLine")
    try {
        $ms = Get-MpComputerStatus -ErrorAction Stop
        $rtp = if ($ms.RealTimeProtectionEnabled) {
            T 'diag_yes'
        } else {
            T 'diag_no'
        }
        $eng = if ($ms.AMEngineVersion) {
            $ms.AMEngineVersion
        } else {
            '?'
        }
        $sig = if ($ms.AntivirusSignatureVersion) {
            $ms.AntivirusSignatureVersion
        } else {
            '?'
        }
        $sigDate = '?'
        try {
            if ($ms.AntivirusSignatureLastUpdated) {
                $sigDate = $ms.AntivirusSignatureLastUpdated.ToString('yyyy-MM-dd')
            }
        } catch { }
        $lines.Add("$(T 'diag_defender'): RTP $rtp, engine $eng, sig $sig ($sigDate)")
    } catch {
        $lines.Add("$(T 'diag_defender'): $(T 'diag_defender_none')")
    }
    try {
        $sac = Get-SmartAppControlState
        $sacLabel = if ($sac -eq 1) {
            T 'diag_sac_on'
        } elseif ($sac -eq 2) {
            T 'diag_sac_eval'
        } elseif ($sac -eq 0) {
            T 'diag_sac_off'
        } else {
            T 'diag_sac_unknown'
        }
        $lines.Add("$(T 'diag_sac'): $sacLabel")
    } catch { }
    try {
        $avs = Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName 'AntiVirusProduct' -ErrorAction Stop
        if ($avs) {
            $avParts = foreach ($av in $avs) {
                $state = '?'
                try {
                    $ps = [int]$av.productState
                    $rtpOn = (($ps -shr 12) -band 0xF) -in @(1, 2)
                    $state = if ($rtpOn) {
                        'RTP on'
                    } else {
                        'RTP off'
                    }
                } catch { }
                "$($av.displayName) ($state)"
            }
            $lines.Add("$(T 'diag_avs'): $($avParts -join ', ')")
        } else {
            $lines.Add("$(T 'diag_avs'): $(T 'diag_avs_none')")
        }
    } catch {
        $lines.Add("$(T 'diag_avs'): $(T 'diag_avs_unavail')")
    }
    try {
        $cfa = (Get-MpPreference -ErrorAction Stop).EnableControlledFolderAccess
        $cfaLabel = if ($cfa -eq 1) {
            T 'diag_cfa_on'
        } elseif ($cfa -eq 0) {
            T 'diag_cfa_off'
        } else {
            T 'diag_cfa_unavail'
        }
        $lines.Add("$(T 'diag_cfa'): $cfaLabel")
    } catch {
        $lines.Add("$(T 'diag_cfa'): $(T 'diag_cfa_unavail')")
    }
    if ($Script:AclDiag) {
        $lines.Add('[acl] ' + $Script:AclDiag)
    }
    return ($lines -join "`n")
}

function Test-WindowsCrashEvent {
    try {
        $since = (Get-Date).AddMinutes(-2)
        $hit = Get-WinEvent -FilterHashtable @{
            LogName = 'Application'
            StartTime = $since
        } -ErrorAction SilentlyContinue |
            Where-Object {
            $_.ProviderName -in @('Application Error', 'Windows Error Reporting') -and ($_.Message -match 'Minecraft.Windows')
        } |
            Select-Object -First 1
        return ($null -ne $hit)
    } catch {
        return $false
    }
}

function Test-PostLaunchCrash {
    param($MinecraftProcess)
    $gdk = $null -ne $MinecraftProcess
    $everSeen = $false
    try {
        $deadline = (Get-Date).AddSeconds(20)
    } catch {
        return $false
    }
    while ((Get-Date) -lt $deadline) {
        if ($gdk) {
            try {
                $MinecraftProcess.Refresh()
                if ($MinecraftProcess.HasExited) {
                    return ($MinecraftProcess.ExitCode -ne 0)
                }
            } catch {
                return $false
            }
        } elseif (Get-Process Minecraft.Windows -ErrorAction SilentlyContinue) {
            $everSeen = $true
        } elseif ($everSeen) {
            return (Test-WindowsCrashEvent)
        }
        Start-Sleep -Seconds 1
    }
    if ($gdk) {
        return $false
    }
    if (Get-Process Minecraft.Windows -ErrorAction SilentlyContinue) {
        return $false
    }
    return (Test-WindowsCrashEvent)
}

function Get-CrashDetailInfo {
    param($MinecraftProcess)
    try {
        if ($null -ne $MinecraftProcess) {
            $MinecraftProcess.Refresh()
            if ($MinecraftProcess.HasExited) {
                $code = [uint32]$MinecraftProcess.ExitCode
                if ($code) {
                    return ('exit code: 0x{0:X8}' -f $code)
                }
            }
        }
    } catch { }
    try {
        $since = (Get-Date).AddMinutes(-5)
        $evt = Get-WinEvent -FilterHashtable @{
            LogName = 'Application'
            StartTime = $since
        } -ErrorAction SilentlyContinue |
            Where-Object {
            $_.ProviderName -in @('Application Error', 'Windows Error Reporting') -and ($_.Message -match 'Minecraft.Windows')
        } |
            Select-Object -First 1
        if ($evt) {
            $msg = ($evt.Message -replace '\s+', ' ').Trim()
            if ($msg.Length -gt 400) {
                $msg = $msg.Substring(0, 400) + '...'
            }
            return $msg
        }
    } catch { }
    return ''
}

function Test-PriorUnlockEvidence {
    try {
        if (Test-Path (Join-Path $cacheDir 'winmm.dll')) {
            return $true
        }
    } catch { }
    try {
        if ((Get-DefenderMbuExclusions).found.Count -gt 0) {
            return $true
        }
    } catch { }
    return $false
}

function Get-WinmmDiskState {
    param([string]$Content)
    $info = @{
        present = $false
        size = 0
        hash = $null
        peMachine = 0
        peValid = $false
        peLabel = '?'
    }
    try {
        if (-not $Content -or -not (Test-Path -LiteralPath $Content)) {
            return $info
        }
        $winmm = Join-Path $Content 'winmm.dll'
        if (-not (Test-Path -LiteralPath $winmm)) {
            return $info
        }
        $info.present = $true
        try {
            $info.size = (Get-Item -LiteralPath $winmm -ErrorAction Stop).Length
        } catch {
            $info.size = -1
        }
        $info.hash = Get-SafeFileHash -Path $winmm
        $info.peMachine = Get-PeMachineType -Path $winmm
        if ($info.peMachine -eq 0xAA64) {
            $info.peValid = $true
            $info.peLabel = 'ARM64'
        }
        elseif ($info.peMachine -eq 0x8664) {
            $info.peValid = $true
            $info.peLabel = 'x64'
        }
        elseif ($info.peMachine -eq 0x014C) {
            $info.peValid = $true
            $info.peLabel = 'x86'
        }
        elseif ($info.peMachine -eq 0) {
            $info.peLabel = 'invalid/truncated'
        }
        elseif ($info.peMachine) {
            $info.peLabel = '0x{0:X4}' -f $info.peMachine
        }
    } catch { }
    return $info
}

function Get-WinmmCorruptHint {
    param([string]$Content)
    try {
        $w = Get-WinmmDiskState -Content $Content
        if (-not $w.present -or -not $w.hash) {
            return ''
        }
        $parts = @()
        if (-not $w.peValid) {
            $parts += ('winmm.dll not a valid PE (size ' + $w.size + ' B) - truncated/corrupt?')
        } else {
            $gm = Get-PeMachineType -Path (Join-Path $Content 'Minecraft.Windows.exe')
            if ($gm -and $w.peMachine -and ($gm -ne $w.peMachine)) {
                $parts += ('PE arch ' + $w.peLabel + ' but game PE arch differs')
            }
        }
        if ($parts.Count -eq 0) {
            return ''
        }
        return ($parts -join ' | ')
    } catch {
        return ''
    }
}

function Get-LateCorruptReason {
    try {
        $c = Find-MinecraftContent
        $w = Get-WinmmDiskState -Content $c
        if (-not $w.present) {
            return ''
        }
        $known = ($knownUnlockHashes -contains $w.hash) -or
                 ($knownUnlockHashesArm64 -contains $w.hash) -or
                 ($expectedHashArm64 -eq $w.hash) -or
                 ($expectedHash -eq $w.hash)
        if ($known) {
            return ''
        }
        $orig = Join-Path $c 'winmm.dll.orig'
        if ((Test-Path $orig) -and ((Get-SafeFileHash -Path $orig) -eq $w.hash)) {
            return ''
        }
        $hint = Get-WinmmCorruptHint -Content $c
        if ($hint) {
            return $hint
        }
        if ((Test-Path $orig) -and $w.peValid) {
            return ('winmm.dll present but not a released unlock and not the .orig backup (size ' + $w.size + ' B)')
        }
        return ''
    } catch {
        return ''
    }
}

function Send-MbuFailureReport {
    param([string]$Trigger, [string]$Reason = '', [string]$Title = '', [System.Management.Automation.ErrorRecord]$ErrorRecord = $null)
    try {
        if ($Trigger -eq 'install_error' -and $Reason -eq (T 'err_content_not_found') -and -not (Test-PriorUnlockEvidence)) {
            return
        }
        Write-Host ''
        if ($Title) {
            Write-Host ("  " + $Title) -ForegroundColor Yellow
        } else {
            Write-Host ("  " + (T ('report_trigger_' + $Trigger))) -ForegroundColor Yellow
        }
        $answer = Read-Host ("  " + (T 'report_ask'))
        if ($answer -notmatch '^[syo]') {
            Write-Host ("  " + (T 'report_not_sent')) -ForegroundColor DarkGray
            return
        }
        $report = Get-DiagReportText -Reason $Reason -ErrorRecord $ErrorRecord
        $os = 'Windows (unknown)'
        try {
            $c = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $os = "$($c.Caption) build $($c.BuildNumber)"
        } catch { }
        $body = @{
            v       = $Script:Version
            os      = $os
            lang    = $Script:Lang
            trigger = $Trigger
            reason  = $Reason
            report  = $report
        } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri $reportEndpoint -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 10 | Out-Null
        Write-Host ("  " + (T 'report_sent')) -ForegroundColor Green
    } catch {
        Write-Host ("  " + (T 'report_send_fail')) -ForegroundColor Yellow
    }
}

if ($env:MBU_NO_LOOP -eq '1') {
    return
}

$Script:LateCorruptShown = $false

while ($true) {
    Show-Banner
    $greeting = Get-TimeGreeting
    $state = Test-UnlockInstalled
    $isInstalled = $state.installed

    if (-not $isInstalled -and -not $Script:LateCorruptShown) {
        $Script:LateCorruptShown = $true
        $lateReason = Get-LateCorruptReason
        if ($lateReason) {
            Send-MbuFailureReport -Trigger 'game_crashed' -Title (T 'corrupt_winmm_found') -Reason $lateReason
        }
    }

    Write-Host ''
    if ($isInstalled) {
        $label = if ($state.label) {
            $state.label
        } else {
            $Script:Version
        }
        Write-Host "  $greeting! $((T 'state_unlocked_v') -replace '\{0\}', $label)" -ForegroundColor Green
        if ($state.label -and ($state.label -match '^v') -and ($state.label.TrimStart('v') -ne $Script:Version)) {
            Write-Host "  $((T 'state_older_hint') -replace '\{0\}', $state.label -replace '\{1\}', $Script:Version)" -ForegroundColor Yellow
        } else {
            Write-Host "  $(T 'state_unlocked_hint')" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  $greeting! $(T 'state_trial')" -ForegroundColor Yellow
        Write-Host "  $(T 'state_trial_hint')" -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host "  $(T 'menu_title'):" -ForegroundColor Green
    if ($isInstalled) {
        Write-Host "    [1] $(T 'menu_1_remove')"
        Write-Host "    [2] $(T 'menu_2_reinstall')"
    } else {
        Write-Host "    [1] $(T 'menu_1_install')"
    }
    Write-Host "    [3] $(T 'menu_4_trouble')"
    Write-Host "    [4] $(T 'menu_5_discord')"
    Write-Host "    [5] $(T 'menu_6_bmc')"
    Write-Host "    [0] $(T 'menu_0')"
    Write-Host ''
    $choice = Read-Host "  $(T 'choose_option')"
    switch ($choice) {
        '1' {
            try {
                if ($isInstalled) {
                    Restore-Original
                } else {
                    Install-Unlocker
                }
            } catch {
                Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
                Send-MbuFailureReport -Trigger 'install_error' -Reason $_.Exception.Message -ErrorRecord $_
            }
        }
        '2' {
            try {
                if ($isInstalled) {
                    Install-Unlocker
                }
            } catch {
                Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
                Send-MbuFailureReport -Trigger 'install_error' -Reason $_.Exception.Message -ErrorRecord $_
            }
        }
        '3' {
            try {
                Start-Process $urls['troubleshooting']
            } catch {
                Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        '4' {
            try {
                Start-Process $urls['discord']
            } catch {
                Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        '5' {
            try {
                Start-Process $urls['donate']
            } catch {
                Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        '0' {
            return
        }
        default {
            Write-Host "  $(T 'invalid_option')" -ForegroundColor Yellow
        }
    }
    if ($choice -eq '0') {
        break
    }
    Write-Host ''
    Read-Host "  $(T 'press_enter')"
}
