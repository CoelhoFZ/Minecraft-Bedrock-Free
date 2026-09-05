# menu.ps1 - Minecraft Bedrock Free - menu interativo (open source, GPLv3).
# Suporte a 8 idiomas (pt/en/es/fr/zh/hi/ar/ru) com deteccao automatica.
#
# IMPORTANTE: o i.ps1 (bootstrap via irm | iex) e o install.bat validam o hash
# SHA256 DESTE arquivo antes de executa-lo. Qualquer edicao aqui muda o hash e
# quebra AMBOS os caminhos de entrada ate que ele seja atualizado em: (1) a
# variavel $menuHash no i.ps1 e (2) o hash fixado no install.bat. O hash e
# calculado sobre o conteudo normalizado (todos os bytes 0x0D removidos, BOM
# preservado) - imune a CRLF vs LF. Apos editar, gere o hash com:
#   python3 -c "import hashlib; print(hashlib.sha256(open('menu.ps1','rb').read().replace(b'\r', b'')).hexdigest())"
# e cole o resultado no i.ps1 ($menuHash) e no install.bat ($menuHashPin).
$ErrorActionPreference = 'Stop'
$Script:Version = '4.6.0'
# Base URL sobrescrevivel (forks/testes em VM): mesma variavel que o i.ps1 ja
# respeita. Afeta menu, binario e tested-versions.json.
$base = if ($env:MBU_BASE_URL) { $env:MBU_BASE_URL.TrimEnd('/') } else {
    'https://raw.githubusercontent.com/CoelhoFZ/Minecraft-Bedrock-Free/main'
}
$expectedHash = 'f387b5f6b9717800a8511d554d37023472e4f2dbd60bc74a44205e640ce02d7e'
# Hashes de TODOS os unlocks validos ja publicados (rebuilds anteriores). O estado
# "desbloqueado" vale para QUALQUER hash desta lista: quem instalou com um DLL
# antigo continua desbloqueado (o jogo abre), mesmo que o binario atual seja mais
# novo. Ao rebuildar o binario: adicionar o hash antigo aqui e manter o
# $expectedHash = hash novo (instalacao/download continua exigindo o atual).
$knownUnlockHashes = @(
    'f387b5f6b9717800a8511d554d37023472e4f2dbd60bc74a44205e640ce02d7e', # atual (rebuild 3df891c)
    'f7b1408c36590abbfcb5310cf98c1efb1fa16f3a54a9387df56b1441de90335b', # rebuild 7334f82 (pix key)
    '86689c9724be7f391ba9bd1f4ef8dddaa73baec0b76b9c73bebef89f37b76e97'  # v4.3.0 (a2ec0d4)
)

# ---- Windows-on-ARM (beta) ----
# O loader do Windows so carrega DLL da MESMA arquitetura do processo: em PC
# arm64 com o pacote arm64 da Store, um winmm.dll x64 nem e mapeado. Com o
# suporte a ARM64 a release passa a ter tambem release/winmm-arm64.dll e o
# instalador escolhe o binario correto lendo o campo Machine do PE do jogo.
# Hash da variante arm64: preenchido quando sair a primeira release; vazio =
# verificacao fica desligada so nessa variante (com aviso na tela).
$expectedHashArm64 = '7a74d63cec0654c50044c55c144dc59f710ded8ccada4f0bd1dc28f557f13f46'
# Hashes validos INSTALAVEIS por arquitetura. O unlock e idempotente por arqu:
# um PC arm64 so carrega winmm-arm64.dll e um x64 so winmm.dll. Guardamos a
# lista da arquitetura do JOGO instalado (nao da sessao) para que o estado
# "desbloqueado" em cada arquitetura seja reconhecido corretamente - o teste
# de estado (Test-UnlockInstalled) consulta apenas a lista da arqu. atual.
# Ao publicar novo binario de uma arqu, adicionar o hash antigo aqui (mesma
# regra do x64).
$knownUnlockHashesArm64 = @(
    '7a74d63cec0654c50044c55c144dc59f710ded8ccada4f0bd1dc28f557f13f46'  # atual (build native ARM64)
)
# Rotulo de build por hash: o estado "DESBLOQUEADO (vX.Y.Z)" e o diagnostico
# mostram QUAL versao do unlock esta instalada, e o menu avisa quando ela e
# mais antiga que o proprio menu. Manter em sincronia com as listas acima
# (hash atual rotula com a versao do menu, abaixo).
$unlockBuildLabels = @{
    # Binario atual: segue o MESMO hash desde a v4.4.2 (4.5.0 e 4.6.0 foram
    # releases de scripts, sem rebuild). Rotular com a versao do MENU evita falso aviso
    # de "unlock mais antigo". Ao rebuildar: mover este hash p/ historico.
    'f387b5f6b9717800a8511d554d37023472e4f2dbd60bc74a44205e640ce02d7e' = 'v4.6.0'
    'f7b1408c36590abbfcb5310cf98c1efb1fa16f3a54a9387df56b1441de90335b' = 'v4.4.1'
    '86689c9724be7f391ba9bd1f4ef8dddaa73baec0b76b9c73bebef89f37b76e97' = 'v4.3.0'
}
$unlockBuildLabelsArm64 = @{
    '7a74d63cec0654c50044c55c144dc59f710ded8ccada4f0bd1dc28f557f13f46' = 'v4.4.2'
}
# Cache local do binario ja validado (reinstalacao OFFLINE): o instalador
# guarda o winmm aprovado aqui apos o hash conferir, e o usa quando o
# download falhar (sem internet / AV comendo o download).
$cacheDir = Join-Path $env:LOCALAPPDATA 'mbu-cache'
# Versoes do JOGO testadas (tested-versions.json no repo): buscado UMA vez
# por sessao. $null = ainda nao buscou; $false = indisponivel (offline/404).
$Script:TestedVersionData = $null
# Atalhos do menu (opcoes 4/5/6).
$urls = @{
    'troubleshooting' = 'https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/blob/main/TROUBLESHOOTING.md'
    'discord'         = 'https://discord.gg/u3S4gFgK6M'
    'donate'          = 'https://buymeacoffee.com/coelhofz'
}
function Get-PeMachineType {
    param([string]$Path)
    try {
        if (-not (Test-Path $Path)) { return 0 }
        $fs = [IO.File]::OpenRead($Path)
        try {
            $br = New-Object IO.BinaryReader($fs)
            $fs.Position = 0x3C
            $peOff = $br.ReadInt32()
            $fs.Position = $peOff + 4
            return [UInt16]$br.ReadUInt16()   # 0x8664=x64 | 0xAA64=ARM64
        } finally { $fs.Dispose() }
    } catch { return 0 }
}

function Resolve-MbuLanguage {
    $candidates = New-Object System.Collections.Generic.List[string]
    try { if ($env:MBU_LANG) { $candidates.Add([string]$env:MBU_LANG) } } catch { }
    try { $candidates.Add((Get-UICulture).Name) } catch { }
    try { $candidates.Add((Get-Culture).Name) } catch { }
    try {
        $userLanguages = Get-WinUserLanguageList -ErrorAction SilentlyContinue
        foreach ($language in $userLanguages) {
            try { if ($language.LanguageTag) { $candidates.Add([string]$language.LanguageTag) } } catch { }
            try { if ($language.EnglishName) { $candidates.Add([string]$language.EnglishName) } } catch { }
            try { if ($language.NativeName) { $candidates.Add([string]$language.NativeName) } } catch { }
        }
    } catch { }
    foreach ($regPath in @('HKCU:\Control Panel\International', 'HKCU:\Control Panel\Desktop', 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language')) {
        try {
            $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            foreach ($prop in @('LocaleName', 'sLanguage', 'Locale', 'PreferredUILanguages')) {
                $value = $props.$prop
                if ($value -is [array]) {
                    foreach ($item in $value) { if ($item) { $candidates.Add([string]$item) } }
                } elseif ($value) {
                    $candidates.Add([string]$value)
                }
            }
        } catch { }
    }
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $value = $candidate.Trim().ToLowerInvariant()
        switch -Wildcard ($value) {
            'en*' { return 'en' }
            '*english*' { return 'en' }
            'pt*' { return 'pt' }
            '*portugu*' { return 'pt' }
            '*brasil*' { return 'pt' }
            '*brazil*' { return 'pt' }
            'zh*' { return 'zh' }
            '*chinese*' { return 'zh' }
            'hi*' { return 'hi' }
            '*hindi*' { return 'hi' }
            'es*' { return 'es' }
            '*spanish*' { return 'es' }
            '*espanol*' { return 'es' }
            '*español*' { return 'es' }
            'fr*' { return 'fr' }
            '*french*' { return 'fr' }
            '*francais*' { return 'fr' }
            '*français*' { return 'fr' }
            'ar*' { return 'ar' }
            '*arabic*' { return 'ar' }
            'ru*' { return 'ru' }
            '*russian*' { return 'ru' }
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
    'err_hash_invalid'   = 'Hash do winmm.dll invalido: {0}'
    'err_acl'            = 'Nao foi possivel tomar posse da pasta do Minecraft. Rode como administrador.'
    'err_copy_corrupt'   = 'Falha ao copiar winmm.dll (copia corrompida/bloqueada). Verifique se o antivirus nao bloqueou e tente de novo.'
    'err_replace'        = 'Nao foi possivel substituir winmm.dll (Access denied ou arquivo em uso). Feche o Minecraft e rode como administrador.'
    'err_av_quarantine'  = 'O winmm.dll foi corrompido/removido pelo antivirus logo apos a copia. Adicione uma exclusao para a pasta do Minecraft e rode de novo.'
    'err_av_blocked'     = 'O antivirus bloqueou o download do winmm.dll mesmo com a exclusao automatica. Abra a Seguranca do Windows, va em Protecao contra virus e ameacas, abra o Historico de protecao, localize o winmm.dll bloqueado e escolha Permitir ou Restaurar. Depois adicione manualmente as exclusoes para: {0}. Se voce usa outro antivirus, adicione as mesmas exclusoes nele. Rode o instalador de novo.'
    'av_retrying'        = 'O antivirus pode ter removido o arquivo baixado. Tentando novamente ({0}/{1})...'
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
    'cache_used'         = 'Sem internet: usando copia local validada do binario ({0}).'
    'cache_saved'        = 'Copia local salva para reinstalacao offline: {0}'
    'menu_3_diag'        = 'Diagnostico (copia relatorio p/ o Discord)'
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
    'diag_cache'         = 'Cache offline do binario'
    'diag_cache_ok'      = 'presente e valido ({0})'
    'diag_cache_bad'     = 'presente MAS com hash diferente do binario atual'
    'diag_cache_none'    = 'ausente (sera criada na proxima instalacao)'
    'diag_clipboard_ok'  = 'Relatorio copiado para a area de transferencia - cole no canal de suporte do Discord.'
    'diag_clipboard_fail'= 'Nao foi possivel copiar automaticamente (copie da tela acima).'
}

$Script:I18N = @{
    'err_acl' = @{ en='Could not take ownership of the Minecraft folder. Run as administrator.'; es='No se pudo tomar posesion de la carpeta de Minecraft. Ejecuta como administrador.'; zh='无法取得 Minecraft 文件夹的所有权。请以管理员身份运行。'; hi='Minecraft फ़ोल्डर का स्वामित्व नहीं लिया जा सका। व्यवस्थापक के रूप में चलाएँ।'; fr='Impossible de prendre possession du dossier Minecraft. Exécutez en tant qu''administrateur.'; ar='تعذّر الحصول على ملكية مجلد Minecraft. شغّل كمسؤول.'; ru='Не удалось получить права на папку Minecraft. Запустите от имени администратора.' }
    'err_copy_corrupt' = @{ en='Failed to copy winmm.dll (corrupted/blocked copy). Check if your antivirus blocked it and try again.'; es='Error al copiar winmm.dll (copia corrupta/bloqueada). Comprueba si tu antivirus lo bloqueo e intentalo de nuevo.'; zh='复制 winmm.dll 失败（副本损坏或受阻）。请检查杀毒软件是否阻止，然后重试。'; hi='winmm.dll की प्रतिलिपि विफल (दूषित/अवरुद्ध प्रतिलिपि)। जाँचें कि क्या आपके एंटीवायरस ने इसे रोका और फिर से प्रयास करें।'; fr='Échec de la copie de winmm.dll (copie corrompue/bloquée). Vérifiez que votre antivirus ne l''a pas bloquée et réessayez.'; ar='فشل نسخ winmm.dll (نسخة تالفة/محظورة). تحقق مما إذا كان برنامج مكافحة الفيروسات قد حظرها وحاول مرة أخرى.'; ru='Не удалось скопировать winmm.dll (копия повреждена/заблокирована). Проверьте, не заблокировал ли его антивирус, и попробуйте снова.' }
    'err_replace' = @{ en='Could not replace winmm.dll (access denied or file in use). Close Minecraft and run as administrator.'; es='No se pudo reemplazar winmm.dll (acceso denegado o archivo en uso). Cierra Minecraft y ejecuta como administrador.'; zh='无法替换 winmm.dll（访问被拒绝或文件被占用）。请关闭 Minecraft 并以管理员身份运行。'; hi='winmm.dll को प्रतिस्थापित नहीं किया जा सका (पहुँच अस्वीकृत या फ़ाइल उपयोग में)। Minecraft बंद करें और व्यवस्थापक के रूप में चलाएँ।'; fr='Impossible de remplacer winmm.dll (accès refusé ou fichier utilisé). Fermez Minecraft et exécutez en tant qu''administrateur.'; ar='تعذّر استبدال winmm.dll (تم رفض الوصول أو الملف قيد الاستخدام). أغلق Minecraft وشغّل كمسؤول.'; ru='Не удалось заменить winmm.dll (отказано в доступе или файл используется). Закройте Minecraft и запустите от имени администратора.' }
    'err_av_quarantine' = @{ en='winmm.dll was corrupted/removed by antivirus right after copying. Add an exclusion for the Minecraft folder and run again.'; es='winmm.dll fue corrompido/eliminado por el antivirus justo despues de copiarlo. Anade una exclusion para la carpeta de Minecraft y vuelve a intentarlo.'; zh='winmm.dll 刚复制完就被杀毒软件破坏/删除。请为 Minecraft 文件夹添加排除项后重新运行。'; hi='प्रतिलिपि के तुरंत बाद एंटीवायरस ने winmm.dll को दूषित/हटा दिया। Minecraft फ़ोल्डर के लिए बहिष्करण जोड़ें और फिर से चलाएँ।'; fr='winmm.dll a été corrompu/supprimé par l''antivirus juste après la copie. Ajoutez une exclusion pour le dossier Minecraft et relancez.'; ar='تم إتلاف/حذف winmm.dll بواسطة مكافح الفيروسات بعد النسخ مباشرة. أضف استثناءً لمجلد Minecraft وأعد التشغيل.'; ru='Антивирус повредил/удалил winmm.dll сразу после копирования. Добавьте исключение для папки Minecraft и запустите снова.' }
    'err_av_blocked' = @{ en='Your antivirus blocked the downloaded winmm.dll even with the automatic exclusion. Open Windows Security, go to Virus & threat protection, open Protection history, find the blocked winmm.dll and choose Allow or Restore. Then add the exclusions manually for: {0}. If you use another antivirus, add the same exclusions there too. Run the installer again.'; es='Tu antivirus bloqueo la descarga de winmm.dll incluso con la exclusion automatica. Abra Seguridad de Windows, vaya a Proteccion contra virus y amenazas, abra el Historial de proteccion, encuentre el winmm.dll bloqueado y elija Permitir o Restaurar. Despues anada manualmente las exclusiones para: {0}. Si usa otro antivirus, anada las mismas exclusiones alli tambien. Ejecute el instalador de nuevo.'; zh='即使已自动添加排除项，杀毒软件仍阻止了下载的 winmm.dll。请打开 Windows 安全中心，进入“病毒和威胁防护”，打开“保护历史记录”，找到被阻止的 winmm.dll 并选择“允许”或“还原”。然后手动为以下路径添加排除项：{0}。如果你使用其他杀毒软件，请在其中添加相同的排除项。重新运行安装程序。'; hi='स्वचालित बहिष्करण के बावजूद आपके एंटीवायरस ने डाउनलोड किए गए winmm.dll को अवरुद्ध कर दिया। Windows Security खोलें, Virus & threat protection पर जाएँ, Protection history खोलें, अवरुद्ध winmm.dll ढूँढें और Allow या Restore चुनें। फिर इनके लिए मैन्युअल रूप से बहिष्करण जोड़ें: {0}। यदि आप कोई अन्य एंटीवायरस उपयोग करते हैं, तो उसमें भी वही बहिष्करण जोड़ें। इंस्टॉलर फिर से चलाएँ।'; fr='Votre antivirus a bloqué le winmm.dll téléchargé malgré l''exclusion automatique. Ouvrez Sécurité Windows, allez dans Protection contre les virus et menaces, ouvrez l''historique de protection, trouvez le winmm.dll bloqué et choisissez Autoriser ou Restaurer. Ajoutez ensuite manuellement les exclusions pour : {0}. Si vous utilisez un autre antivirus, ajoutez-y les mêmes exclusions. Relancez l''installateur.'; ar='حظر مكافح الفيروسات لديك ملف winmm.dll الذي تم تنزيله حتى مع الاستثناء التلقائي. افتح أمان Windows، وانتقل إلى الحماية من الفيروسات والتهديدات، وافتح سجل الحماية، وابحث عن winmm.dll المحظور واختر السماح أو الاستعادة. ثم أضف الاستثناءات يدويًا لهذه المسارات: {0}. إذا كنت تستخدم مكافح فيروسات آخر، أضف نفس الاستثناءات إليه أيضًا. شغّل المثبّت مرة أخرى.'; ru='Ваш антивирус заблокировал загруженный winmm.dll, даже несмотря на автоматическое исключение. Откройте «Безопасность Windows», перейдите в «Защита от вирусов и угроз», откройте «Журнал защиты», найдите заблокированный winmm.dll и выберите «Разрешить» или «Восстановить». Затем добавьте исключения вручную для: {0}. Если вы используете другой антивирус, добавьте такие же исключения и в него. Запустите установщик снова.' }
    'av_retrying' = @{ en='The antivirus may have removed the downloaded file. Retrying ({0}/{1})...'; es='El antivirus pudo haber eliminado el archivo descargado. Reintentando ({0}/{1})...'; zh='杀毒软件可能已删除下载的文件。正在重试（{0}/{1}）...'; hi='एंटीवायरस ने डाउनलोड की गई फ़ाइल हटा दी हो सकती है। पुनः प्रयास ({0}/{1})...'; fr='L''antivirus a peut-être supprimé le fichier téléchargé. Nouvel essai ({0}/{1})...'; ar='ربما حذف مكافح الفيروسات الملف الذي تم تنزيله. إعادة المحاولة ({0}/{1})...'; ru='Возможно, антивирус удалил загруженный файл. Повторная попытка ({0}/{1})...' }
    'av_exclusion_ok' = @{ en='Windows Defender exclusion added for: {0}'; pt='Exclusao do Windows Defender adicionada para: {0}'; es='Exclusion de Windows Defender anadida para: {0}'; zh='已为以下路径添加 Windows Defender 排除项：{0}'; hi='इनके लिए Windows Defender बहिष्करण जोड़ा गया: {0}'; fr='Exclusion Windows Defender ajoutée pour : {0}'; ar='تمت إضافة استثناء Windows Defender لهذه المسارات: {0}'; ru='Исключение Защитника Windows добавлено для: {0}' }
    'av_exclusion_fail' = @{ en='Could not add the Windows Defender exclusion automatically. Run as administrator or add it manually: {0}'; pt='Nao foi possivel adicionar a exclusao do Windows Defender automaticamente. Rode como administrador ou adicione manualmente: {0}'; es='No se pudo anadir la exclusion de Windows Defender automaticamente. Ejecuta como administrador o anadela manualmente: {0}'; zh='无法自动添加 Windows Defender 排除项。请以管理员身份运行或手动添加：{0}'; hi='Windows Defender बहिष्करण स्वचालित रूप से नहीं जोड़ा जा सका। व्यवस्थापक के रूप में चलाएँ या मैन्युअल रूप से जोड़ें: {0}'; fr='Impossible d''ajouter automatiquement l''exclusion Windows Defender. Exécutez en tant qu''administrateur ou ajoutez-la manuellement : {0}'; ar='تعذّر إضافة استثناء Windows Defender تلقائيًا. شغّل كمسؤول أو أضفه يدويًا: {0}'; ru='Не удалось автоматически добавить исключение Защитника Windows. Запустите от имени администратора или добавьте вручную: {0}' }
    'greet_morning' = @{ en='Good morning'; zh='早上好'; hi='सुप्रभात'; es='Buenos días'; fr='Bonjour'; ar='صباح الخير'; ru='Доброе утро' }
    'greet_afternoon' = @{ en='Good afternoon'; zh='下午好'; hi='शुभ दोपहर'; es='Buenas tardes'; fr='Bon après-midi'; ar='مساء الخير'; ru='Добрый день' }
    'greet_evening' = @{ en='Good evening'; zh='晚上好'; hi='शुभ संध्या'; es='Buenas noches'; fr='Bonsoir'; ar='مساء النور'; ru='Добрый вечер' }
    'banner_build_note' = @{ en='Official Store/Xbox App build (current version) only. No 3rd-party launchers or older versions.'; zh='仅支持官方 Store/Xbox App 版本（当前版本）。不支持第三方启动器或旧版本。'; hi='केवल आधिकारिक Store/Xbox App बिल्ड (वर्तमान संस्करण)। कोई तृतीय-पक्ष लॉन्चर या पुराना संस्करण नहीं।'; es='Solo el build oficial de Store/Xbox App (version actual). Sin launchers de terceros ni versiones antiguas.'; fr='Uniquement le build officiel Store/Xbox App (version actuelle). Pas de launchers tiers ni d''anciennes versions.'; ar='فقط إصدار Store/Xbox App الرسمي (النسخة الحالية). لا توجد مشغلات طرف ثالث أو إصدارات قديمة.'; ru='Только официальная сборка Store/Xbox App (текущая версия). Без сторонних лаунчеров и старых версий.' }
    'err_content_not_found' = @{ en='Minecraft Content folder not found. Install Minecraft from the Xbox App or the Microsoft Store and try again.'; zh='未找到 Minecraft Content 文件夹。请从 Xbox 应用安装 Minecraft。'; hi='Minecraft Content फ़ोल्डर नहीं मिला। Xbox App से Minecraft इंस्टॉल करें।'; es='No se encontró la carpeta Content de Minecraft. Instala Minecraft desde la Xbox App.'; fr='Dossier Content de Minecraft introuvable. Installez Minecraft depuis l''application Xbox.'; ar='لم يتم العثور على مجلد Content الخاص بـ Minecraft. ثبّت Minecraft من تطبيق Xbox.'; ru='Папка Content Minecraft не найдена. Установите Minecraft из приложения Xbox.' }
    'err_package_incomplete' = @{ en='Minecraft package found but the game executable is missing. Reinstall Minecraft and try again.'; zh='找到 Minecraft 包，但缺少游戏可执行文件。请重新安装 Minecraft 后再试。'; hi='Minecraft पैकेज मिला, लेकिन गेम एक्ज़ीक्यूटेबल गायब है। Minecraft फिर से इंस्टॉल करके देखें。'; es='Se encontró el paquete de Minecraft, pero falta el ejecutable del juego. Reinstala Minecraft e inténtalo de nuevo.'; fr='Le package Minecraft est présent, mais l''exécutable du jeu est manquant. Réinstallez Minecraft et réessayez.'; ar='تم العثور على حزمة Minecraft، لكن ملف تشغيل اللعبة مفقود. أعد تثبيت Minecraft وحاول مرة أخرى.'; ru='Пакет Minecraft найден, но исполняемый файл игры отсутствует. Переустановите Minecraft и попробуйте снова.' }
    'closing_mc' = @{ en='Closing Minecraft...'; zh='正在关闭 Minecraft...'; hi='Minecraft बंद किया जा रहा है...'; es='Cerrando Minecraft...'; fr='Fermeture de Minecraft...'; ar='جارٍ إغلاق Minecraft...'; ru='Закрытие Minecraft...' }
    'downloading_bin' = @{ en='Downloading the binary (winmm.dll)...'; zh='正在下载二进制文件 (winmm.dll)...'; hi='बाइनरी डाउनलोड हो रही है (winmm.dll)...'; es='Descargando el binario (winmm.dll)...'; fr='Téléchargement du binaire (winmm.dll)...'; ar='جارٍ تنزيل الملف الثنائي (winmm.dll)...'; ru='Загрузка бинарного файла (winmm.dll)...' }
    'err_hash_invalid' = @{ en='Invalid winmm.dll hash: {0}'; zh='winmm.dll 哈希无效: {0}'; hi='winmm.dll का हैश अमान्य: {0}'; es='Hash de winmm.dll inválido: {0}'; fr='Hash de winmm.dll invalide : {0}'; ar='تجزئة winmm.dll غير صالحة: {0}'; ru='Неверный хеш winmm.dll: {0}' }
    'backup_orig' = @{ en='Backup of the original winmm saved as winmm.dll.orig'; zh='已将原始 winmm 备份为 winmm.dll.orig'; hi='मूल winmm का बैकअप winmm.dll.orig के रूप में सहेजा गया'; es='Copia de seguridad del winmm original en winmm.dll.orig'; fr='Sauvegarde du winmm original dans winmm.dll.orig'; ar='تم حفظ نسخة احتياطية من winmm الأصلي باسم winmm.dll.orig'; ru='Резервная копия оригинального winmm сохранена в winmm.dll.orig' }
    'install_ok' = @{ en='OK - unlock installed.'; zh='OK - 解锁已安装。'; hi='OK - अनलॉक स्थापित हो गया।'; es='OK - desbloqueo instalado.'; fr='OK - déverrouillage installé.'; ar='تم تثبيت فتح اللعبة.'; ru='OK - разблокировка установлена.' }
    'restored_ok' = @{ en='Original winmm restored.'; zh='已还原原始 winmm。'; hi='मूल winmm पुनर्स्थापित हो गया।'; es='winmm original restaurado.'; fr='winmm original restauré.'; ar='تمت استعادة winmm الأصلي.'; ru='Оригинальный winmm восстановлен.' }
    'removed_ok' = @{ en='winmm.dll removed (the game will use the system one).'; zh='已移除 winmm.dll (游戏将使用系统自带的)。'; hi='winmm.dll हटा दिया गया (गेम सिस्टम वाला उपयोग करेगा)।'; es='winmm.dll eliminado (el juego usará el del sistema).'; fr='winmm.dll supprimé (le jeu utilisera celui du système).'; ar='تمت إزالة winmm.dll (ستستخدم اللعبة ملف النظام).'; ru='winmm.dll удалён (игра будет использовать системный).' }
    'unlock_removed' = @{ en='Unlock removed.'; zh='解锁已移除。'; hi='अनलॉक हटा दिया गया।'; es='Desbloqueo eliminado.'; fr='Déverrouillage supprimé.'; ar='تمت إزالة فتح اللعبة.'; ru='Разблокировка удалена.' }
    'nothing_to_restore' = @{ en='The unlock is not installed (nothing to restore).'; zh='解锁未安装（没有可还原的内容）。'; hi='अनलॉक स्थापित नहीं है (पुनर्स्थापित करने के लिए कुछ नहीं)।'; es='El desbloqueo no está instalado (nada que restaurar).'; fr='Le déverrouillage n''est pas installé (rien à restaurer).'; ar='فتح اللعبة غير مثبت (لا يوجد شيء لاستعادته).'; ru='Разблокировка не установлена (нечего восстанавливать).' }
    'mc_started' = @{ en='Minecraft started.'; zh='Minecraft 已启动。'; hi='Minecraft शुरू हो गया।'; es='Minecraft iniciado.'; fr='Minecraft lancé.'; ar='تم تشغيل Minecraft.'; ru='Minecraft запущен.' }
    'mc_start_failed' = @{ en='Could not start Minecraft automatically. Open it from the Start Menu.'; zh='无法自动启动 Minecraft。请从开始菜单打开。'; hi='Minecraft स्वचालित रूप से शुरू नहीं हो सका। स्टार्ट मेनू से खोलें।'; es='No se pudo iniciar Minecraft automáticamente. Ábrelo desde el menú Inicio.'; fr='Impossible de démarrer Minecraft automatiquement. Ouvrez-le depuis le menu Démarrer.'; ar='تعذّر تشغيل Minecraft تلقائيًا. افتحه من قائمة ابدأ.'; ru='Не удалось запустить Minecraft автоматически. Откройте его из меню «Пуск».' }
    'state_unlocked' = @{ en='Minecraft is already UNLOCKED.'; zh='Minecraft 已经解锁。'; hi='Minecraft पहले से अनलॉक है।'; es='Minecraft ya está DESBLOQUEADO.'; fr='Minecraft est déjà DÉBLOQUÉ.'; ar='Minecraft مفتوح بالفعل.'; ru='Minecraft уже РАЗБЛОКИРОВАН.' }
    'state_unlocked_hint' = @{ en='If you want, choose [1] to remove the unlock and go back to Trial.'; zh='如果需要，请选择 [1] 移除解锁并恢复到试用版。'; hi='चाहें तो अनलॉक हटाने और ट्रायल पर वापस जाने के लिए [1] चुनें।'; es='Si quieres, elige [1] para eliminar el desbloqueo y volver a la prueba.'; fr='Si vous voulez, choisissez [1] pour supprimer le déverrouillage et revenir à l''essai.'; ar='إذا أردت، اختر [1] لإزالة فتح اللعبة والعودة إلى النسخة التجريبية.'; ru='Если хотите, выберите [1], чтобы удалить разблокировку и вернуться к пробной версии.' }
    'state_trial' = @{ en='Minecraft is in TRIAL mode.'; zh='Minecraft 处于试用版模式。'; hi='Minecraft ट्रायल मोड में है।'; es='Minecraft está en modo PRUEBA.'; fr='Minecraft est en mode ESSAI.'; ar='Minecraft في وضع النسخة التجريبية.'; ru='Minecraft в пробном режиме.' }
    'state_trial_hint' = @{ en='Choose [1] to unlock the full game.'; zh='选择 [1] 解锁完整版游戏。'; hi='पूरा गेम अनलॉक करने के लिए [1] चुनें।'; es='Elige [1] para desbloquear el juego completo.'; fr='Choisissez [1] pour déverrouiller le jeu complet.'; ar='اختر [1] لفتح اللعبة الكاملة.'; ru='Выберите [1], чтобы разблокировать полную игру.' }
    'menu_title' = @{ en='Available Options'; zh='可用选项'; hi='उपलब्ध विकल्प'; es='Opciones disponibles'; fr='Options disponibles'; ar='الخيارات المتاحة'; ru='Доступные параметры' }
    'menu_1_install' = @{ en='Install unlock'; zh='安装解锁'; hi='अनलॉक स्थापित करें'; es='Instalar desbloqueo'; fr='Installer le déverrouillage'; ar='تثبيت فتح اللعبة'; ru='Установить разблокировку' }
    'menu_1_remove' = @{ en='Remove unlock (back to Trial)'; zh='移除解锁（恢复试用版）'; hi='अनलॉक हटाएँ (ट्रायल पर वापस)'; es='Eliminar desbloqueo (volver a prueba)'; fr='Supprimer le déverrouillage (revenir à l''essai)'; ar='إزالة فتح اللعبة (العودة إلى النسخة التجريبية)'; ru='Удалить разблокировку (вернуться к пробной версии)' }
    'menu_2_reinstall' = @{ en='Reinstall unlock'; zh='重新安装解锁'; hi='अनलॉक फिर से स्थापित करें'; es='Reinstalar desbloqueo'; fr='Réinstaller le déverrouillage'; ar='إعادة تثبيت فتح اللعبة'; ru='Переустановить разблокировку' }
    'menu_0' = @{ en='Exit'; zh='退出'; hi='बाहर'; es='Salir'; fr='Quitter'; ar='خروج'; ru='Выход' }
    'choose_option' = @{ en='Choose an option'; zh='请选择一个选项'; hi='एक विकल्प चुनें'; es='Elige una opción'; fr='Choisissez une option'; ar='اختر خيارًا'; ru='Выберите вариант' }
    'invalid_option' = @{ en='Invalid option.'; zh='无效选项。'; hi='अमान्य विकल्प।'; es='Opción no válida.'; fr='Option invalide.'; ar='خيار غير صالح.'; ru='Неверный вариант.' }
    'press_enter' = @{ en='Press Enter to continue...'; zh='按 Enter 键继续...'; hi='जारी रखने के लिए Enter दबाएँ...'; es='Pulse Enter para continuar...'; fr='Appuyez sur Entrée pour continuer...'; ar='اضغط Enter للمتابعة...'; ru='Нажмите Enter для продолжения...' }
    'arch_line' = @{ en='Detected game build: {0} (Machine={1})'; zh='检测到的游戏构建：{0}（Machine={1}）'; hi='गेम बिल्ड पहचाना गया: {0} (Machine={1})'; es='Build del juego detectado: {0} (Machine={1})'; fr='Build du jeu détecté : {0} (Machine={1})'; ar='إصدار اللعبة المكتشف: {0} (Machine={1})'; ru='Обнаружена сборка игры: {0} (Machine={1})' }
    'arch_unknown' = @{ en='Could not read the game build from the executable, assuming x64.'; zh='无法从可执行文件读取游戏构建，将按 x64 处理。'; hi='एक्ज़ीक्यूटेबल से गेम बिल्ड नहीं पढ़ा जा सका, x64 मान लिया जा रहा है।'; es='No se pudo leer la build del juego desde el ejecutable, se asume x64.'; fr='Impossible de lire la build du jeu depuis l''exécutable, x64 supposé.'; ar='تعذر قراءة إصدار اللعبة من الملف التنفيذي، سيتم افتراض x64.'; ru='Не удалось прочитать сборку игры из исполняемого файла, используется x64.' }
    'arm64_detected' = @{ en='[ARM64] Windows on ARM PC detected: using the native ARM64 unlocker (BETA).'; zh='[ARM64] 检测到 Windows on ARM 电脑：使用原生 ARM64 解锁器（测试版）。'; hi='[ARM64] Windows on ARM पीसी पाया गया: नेटिव ARM64 अनलॉकर का उपयोग हो रहा है (बीटा)।'; es='[ARM64] PC con Windows on ARM detectado: usando el unlocker ARM64 nativo (BETA).'; fr='[ARM64] PC Windows on ARM détecté : utilisation de l''unlocker ARM64 natif (BETA).'; ar='[ARM64] تم اكتشاف جهاز Windows on ARM: سيتم استخدام أداة الفتح الأصلية ARM64 (نسخة تجريبية).'; ru='[ARM64] Обнаружен ПК с Windows on ARM: используется нативный ARM64 анлокер (БЕТА).' }
    'arm64_no_release' = @{ en='[ARM64] The ARM64 build has not been published in this release yet.'; zh='[ARM64] 此版本尚未发布 ARM64 构建。'; hi='[ARM64] ARM64 बिल्ड अभी इस रिलीज़ में प्रकाशित नहीं हुआ है।'; es='[ARM64] La build ARM64 aún no ha sido publicada en esta release.'; fr='[ARM64] La build ARM64 n''est pas encore publiée dans cette release.'; ar='[ARM64] لم يتم نشر إصدار ARM64 في هذا الإصدار بعد.'; ru='[ARM64] Сборка ARM64 еще не опубликована в этом релизе.' }
    'arm64_hash_skipped' = @{ en='[ARM64] Hash verification is unavailable in this beta phase.'; zh='[ARM64] 此测试阶段无法进行哈希校验。'; hi='[ARM64] इस बीटा चरण में हैश सत्यापन उपलब्ध नहीं है।'; es='[ARM64] La verificación de hash no está disponible en esta fase beta.'; fr='[ARM64] La vérification de hash n''est pas disponible dans cette phase bêta.'; ar='[ARM64] التحقق من التجزئة غير متاح في هذه المرحلة التجريبية.'; ru='[ARM64] Проверка хеша недоступна на этой бета-стадии.' }
    'track_releases' = @{ en='Track new releases at {0}'; zh='在此查看新版本：{0}'; hi='नए रिलीज़ यहाँ देखें: {0}'; es='Consulta las nuevas releases en {0}'; fr='Suivez les nouvelles releases sur {0}'; ar='تابع الإصدارات الجديدة على {0}'; ru='Следите за новыми релизами здесь: {0}' }
    'state_unlocked_v' = @{ en='Minecraft is already UNLOCKED ({0}).'; es='Minecraft ya está DESBLOQUEADO ({0}).'; zh='Minecraft 已经解锁（{0}）。'; hi='Minecraft पहले से अनलॉक है ({0})।'; fr='Minecraft est déjà DÉBLOQUÉ ({0}).'; ar='Minecraft مفتوح بالفعل ({0}).'; ru='Minecraft уже РАЗБЛОКИРОВАН ({0}).' }
    'state_older_hint' = @{ en='Installed unlock ({0}) is older than this menu ({1}) - use [2] to update.'; es='El desbloqueo instalado ({0}) es más antiguo que este menú ({1}) - usa [2] para actualizar.'; zh='已安装的解锁（{0}）比当前菜单（{1}）旧 - 请使用 [2] 更新。'; hi='स्थापित अनलॉक ({0}) इस मेनू ({1}) से पुराना है - अपडेट के लिए [2] उपयोग करें।'; fr='Le déverrouillage installé ({0}) est plus ancien que ce menu ({1}) - utilisez [2] pour mettre à jour.'; ar='الفتح المثبّت ({0}) أقدم من هذه القائمة ({1}) - استخدم [2] للتحديث.'; ru='Установленная разблокировка ({0}) старее этого меню ({1}) - используйте [2] для обновления.' }
    'tested_warning' = @{ en='Warning: game version {0} has NOT been tested with this unlocker yet. If anything fails, please report it on Discord.'; es='Aviso: la versión del juego {0} aún NO ha sido probada con este unlocker. Si algo falla, repórtalo en Discord.'; zh='警告：游戏版本 {0} 尚未经过此解锁器测试。如有问题，请在 Discord 上报告。'; hi='चेतावनी: गेम संस्करण {0} का अभी इस अनलॉकर से परीक्षण नहीं हुआ है। यदि कुछ विफल हो तो Discord पर रिपोर्ट करें।'; fr='Avertissement : la version {0} du jeu n''a pas encore été testée avec ce déverrouilleur. En cas de problème, signalez-le sur Discord.'; ar='تحذير: إصدار اللعبة {0} لم يُختبر بعد مع هذا الفاتح. إذا حدثت أي مشكلة، يُرجى الإبلاغ عنها على Discord.'; ru='Внимание: версия игры {0} ещё не протестирована с этим анлокером. Если что-то не работает, сообщите об этом в Discord.' }
    'cache_used' = @{ en='Offline: using the local validated copy of the binary ({0}).'; es='Sin internet: usando la copia local validada del binario ({0}).'; zh='无网络：使用本地已验证的二进制副本（{0}）。'; hi='इंटरनेट नहीं: बाइनरी की स्थानीय सत्यापित प्रतिलिपि का उपयोग ({0})।'; fr='Hors ligne : utilisation de la copie locale validée du binaire ({0}).'; ar='بدون إنترنت: استخدام النسخة المحلية الموثّقة من الملف الثنائي ({0}).'; ru='Нет интернета: используется локальная проверенная копия бинарника ({0}).' }
    'cache_saved' = @{ en='Local cache saved for offline reinstall: {0}'; es='Copia local guardada para reinstalación sin conexión: {0}'; zh='已保存本地缓存，供离线重装使用：{0}'; hi='ऑफ़लाइन पुनर्स्थापना के लिए स्थानीय कैश सहेजा गया: {0}'; fr='Cache local enregistré pour la réinstallation hors ligne : {0}'; ar='تم حفظ ذاكرة التخزين المؤقت المحلية لإعادة التثبيت دون اتصال: {0}'; ru='Локальный кэш сохранён для офлайн-переустановки: {0}' }
    'menu_3_diag' = @{ en='Diagnostics (copy report for Discord)'; es='Diagnóstico (copiar informe p/ Discord)'; zh='诊断（复制报告以粘贴到 Discord）'; hi='डायग्नोस्टिक्स (Discord के लिए रिपोर्ट कॉपी करें)'; fr='Diagnostic (copier le rapport pour Discord)'; ar='التشخيص (نسخ التقرير إلى Discord)'; ru='Диагностика (скопировать отчёт для Discord)' }
    'menu_4_trouble' = @{ en='Open troubleshooting guide (web)'; es='Abrir guía de problemas (web)'; zh='打开问题排查指南（网页）'; hi='समस्या समाधान मार्गदर्शिका खोलें (वेब)'; fr='Ouvrir le guide de dépannage (web)'; ar='فتح دليل استكشاف الأخطاء (ويب)'; ru='Открыть руководство по устранению неполадок (веб)' }
    'menu_5_discord' = @{ en='Open community Discord'; es='Abrir Discord de la comunidad'; zh='打开社区 Discord'; hi='समुदाय Discord खोलें'; fr='Ouvrir le Discord de la communauté'; ar='فتح Discord المجتمع'; ru='Открыть Discord сообщества' }
    'menu_6_bmc' = @{ en='Support the project (Buy Me a Coffee)'; es='Apoyar el proyecto (Buy Me a Coffee)'; zh='支持本项目（Buy Me a Coffee）'; hi='परियोजना का समर्थन करें (Buy Me a Coffee)'; fr='Soutenir le projet (Buy Me a Coffee)'; ar='دعم المشروع (Buy Me a Coffee)'; ru='Поддержать проект (Buy Me a Coffee)' }
    'diag_title' = @{ en='Diagnostic report - Minecraft Bedrock Free v{0}'; es='Informe de diagnóstico - Minecraft Bedrock Free v{0}'; zh='诊断报告 - Minecraft Bedrock Free v{0}'; hi='डायग्नोस्टिक रिपोर्ट - Minecraft Bedrock Free v{0}'; fr='Rapport de diagnostic - Minecraft Bedrock Free v{0}'; ar='تقرير التشخيص - Minecraft Bedrock Free v{0}'; ru='Диагностический отчёт - Minecraft Bedrock Free v{0}' }
    'diag_os' = @{ en='OS'; es='Sistema'; zh='系统'; hi='ऑपरेटिंग सिस्टम'; fr='Système'; ar='نظام التشغيل'; ru='Система' }
    'diag_ps' = @{ en='PowerShell'; es='PowerShell'; zh='PowerShell'; hi='PowerShell'; fr='PowerShell'; ar='PowerShell'; ru='PowerShell' }
    'diag_admin' = @{ en='Administrator'; es='Administrador'; zh='管理员'; hi='व्यवस्थापक'; fr='Administrateur'; ar='مسؤول'; ru='Администратор' }
    'diag_yes' = @{ en='yes'; es='sí'; zh='是'; hi='हाँ'; fr='oui'; ar='نعم'; ru='да' }
    'diag_no' = @{ en='no'; es='no'; zh='否'; hi='नहीं'; fr='non'; ar='لا'; ru='нет' }
    'diag_content' = @{ en='Game Content folder'; es='Carpeta Content del juego'; zh='游戏 Content 文件夹'; hi='गेम Content फ़ोल्डर'; fr='Dossier Content du jeu'; ar='مجلد Content للعبة'; ru='Папка Content игры' }
    'diag_source' = @{ en='Install source'; es='Origen de la instalación'; zh='安装来源'; hi='इंस्टॉल स्रोत'; fr='Source d''installation'; ar='مصدر التثبيت'; ru='Источник установки' }
    'diag_source_store' = @{ en='Microsoft Store (UWP)'; es='Microsoft Store (UWP)'; zh='Microsoft Store (UWP)'; hi='Microsoft Store (UWP)'; fr='Microsoft Store (UWP)'; ar='Microsoft Store (UWP)'; ru='Microsoft Store (UWP)' }
    'diag_source_gdk' = @{ en='Xbox App (GDK)'; es='Xbox App (GDK)'; zh='Xbox App (GDK)'; hi='Xbox App (GDK)'; fr='Xbox App (GDK)'; ar='Xbox App (GDK)'; ru='Xbox App (GDK)' }
    'diag_source_unknown' = @{ en='unknown'; es='desconocida'; zh='未知'; hi='अज्ञात'; fr='inconnue'; ar='غير معروفة'; ru='неизвестно' }
    'diag_game_version' = @{ en='Game version'; es='Versión del juego'; zh='游戏版本'; hi='गेम संस्करण'; fr='Version du jeu'; ar='إصدار اللعبة'; ru='Версия игры' }
    'diag_game_arch' = @{ en='Game architecture'; es='Arquitectura del juego'; zh='游戏架构'; hi='गेम आर्किटेक्चर'; fr='Architecture du jeu'; ar='بنية اللعبة'; ru='Архитектура игры' }
    'diag_unlock' = @{ en='Unlock installed'; es='Desbloqueo instalado'; zh='已安装的解锁'; hi='अनलॉक स्थापित'; fr='Déverrouillage installé'; ar='الفتح المثبّت'; ru='Установленная разблокировка' }
    'diag_unlock_none' = @{ en='not installed (Trial)'; es='no instalado (prueba)'; zh='未安装（试用版）'; hi='स्थापित नहीं (ट्रायल)'; fr='non installé (essai)'; ar='غير مثبّت (نسخة تجريبية)'; ru='не установлена (пробная версия)' }
    'diag_tested' = @{ en='Game version vs tested versions'; es='Versión del juego vs probadas'; zh='游戏版本 vs 已测试版本'; hi='गेम संस्करण बनाम परीक्षण किए गए संस्करण'; fr='Version du jeu vs versions testées'; ar='إصدار اللعبة مقابل الإصدارات المختبرة'; ru='Версия игры против протестированных версий' }
    'diag_tested_ok' = @{ en='OK - covered by tested-versions.json'; es='OK - cubierta por tested-versions.json'; zh='OK - 已包含在 tested-versions.json 中'; hi='OK - tested-versions.json द्वारा कवर'; fr='OK - couverte par tested-versions.json'; ar='موافق - مغطّى في tested-versions.json'; ru='OK - покрыта tested-versions.json' }
    'diag_tested_bad' = @{ en='ATTENTION - not in the tested list'; es='ATENCIÓN - fuera de la lista de probadas'; zh='注意 - 不在已测试列表中'; hi='ध्यान दें - परीक्षण सूची में नहीं'; fr='ATTENTION - hors liste des versions testées'; ar='انتبه - خارج قائمة الإصدارات المختبرة'; ru='ВНИМАНИЕ - нет в списке протестированных' }
    'diag_tested_unknown' = @{ en='unavailable (offline or no data)'; es='indisponible (sin internet o sin datos)'; zh='不可用（无网络或无数据）'; hi='अनुपलब्ध (इंटरनेट नहीं या कोई डेटा नहीं)'; fr='indisponible (hors ligne ou aucune donnée)'; ar='غير متاح (بدون إنترنت أو بدون بيانات)'; ru='недоступно (нет интернета или данных)' }
    'diag_av' = @{ en='Defender exclusions (mbu/Minecraft)'; es='Exclusiones de Defender (mbu/Minecraft)'; zh='Defender 排除项（mbu/Minecraft）'; hi='Defender बहिष्करण (mbu/Minecraft)'; fr='Exclusions Defender (mbu/Minecraft)'; ar='استثناءات Defender (mbu/Minecraft)'; ru='Исключения Defender (mbu/Minecraft)' }
    'diag_av_none' = @{ en='none found'; es='ninguna encontrada'; zh='未找到'; hi='कोई नहीं मिला'; fr='aucune trouvée'; ar='لم يتم العثور على أي منها'; ru='не найдено' }
    'diag_cache' = @{ en='Offline binary cache'; es='Caché offline del binario'; zh='二进制文件离线缓存'; hi='बाइनरी ऑफ़लाइन कैश'; fr='Cache hors ligne du binaire'; ar='ذاكرة التخزين المؤقت للملف الثنائي دون اتصال'; ru='Офлайн-кэш бинарника' }
    'diag_cache_ok' = @{ en='present and valid ({0})'; es='presente y válida ({0})'; zh='存在且有效（{0}）'; hi='मौजूद और मान्य ({0})'; fr='présente et valide ({0})'; ar='موجودة وصالحة ({0})'; ru='есть и действителен ({0})' }
    'diag_cache_bad' = @{ en='present BUT with a different hash than the current binary'; es='presente PERO con hash distinto del binario actual'; zh='存在但与当前二进制文件的哈希不同'; hi='मौजूद लेकिन वर्तमान बाइनरी से भिन्न हैश के साथ'; fr='présente MAIS avec un hash différent du binaire actuel'; ar='موجودة لكن بتجزئة مختلفة عن الملف الثنائي الحالي'; ru='есть, НО с хешем, отличным от текущего бинарника' }
    'diag_cache_none' = @{ en='missing (created on next install)'; es='ausente (se creará en la próxima instalación)'; zh='缺失（下次安装时创建）'; hi='अनुपस्थित (अगली स्थापना पर बनेगा)'; fr='absente (créée à la prochaine installation)'; ar='غير موجودة (ستُنشأ في التثبيت التالي)'; ru='отсутствует (будет создан при следующей установке)' }
    'diag_clipboard_ok' = @{ en='Report copied to the clipboard - paste it in the Discord support channel.'; es='Informe copiado al portapapeles - pégalo en el canal de soporte de Discord.'; zh='报告已复制到剪贴板 - 请粘贴到 Discord 支持频道。'; hi='रिपोर्ट क्लिपबोर्ड पर कॉपी हो गई - Discord सहायता चैनल में चिपकाएँ।'; fr='Rapport copié dans le presse-papiers - collez-le dans le canal d''assistance Discord.'; ar='تم نسخ التقرير إلى الحافظة - الصقه في قناة دعم Discord.'; ru='Отчёт скопирован в буфер обмена - вставьте его в канал поддержки Discord.' }
    'diag_clipboard_fail' = @{ en='Could not copy automatically (copy from the screen above).'; es='No se pudo copiar automáticamente (copia desde la pantalla de arriba).'; zh='无法自动复制（请从上方屏幕复制）。'; hi='स्वचालित रूप से कॉपी नहीं हो सका (ऊपर स्क्रीन से कॉपी करें)।'; fr='Impossible de copier automatiquement (copiez depuis l''écran ci-dessus).'; ar='تعذّر النسخ تلقائيًا (انسخ من الشاشة أعلاه).'; ru='Не удалось скопировать автоматически (скопируйте с экрана выше).' }
}

function T {
    param([string]$Key)
    if ($Script:Lang -eq 'pt' -and $Script:PT.ContainsKey($Key)) { return $Script:PT[$Key] }
    $entry = $Script:I18N[$Key]
    if ($entry) {
        if ($entry[$Script:Lang]) { return $entry[$Script:Lang] }
        if ($entry['en']) { return $entry['en'] }
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
    if ($hour -ge 6 -and $hour -lt 12) { return T 'greet_morning' }
    elseif ($hour -ge 12 -and $hour -lt 18) { return T 'greet_afternoon' }
    else { return T 'greet_evening' }
}

function Get-MinecraftCandidates {
    # Ordem importa (corrigido na v4.6.0, descoberto com o pacote 1.26.x): o pacote REGISTRADO e a
    # fonte da verdade, e dele que o menu Iniciar e o loader do jogo carregam o
    # winmm.dll. Apos a migracao UWP->GDK pode sobrar um Minecraft.Windows.exe
    # velho em C:\XboxGames\Minecraft for Windows\Content. Instalar nessa copia
    # nao desbloqueia o jogo real (que roda do WindowsApps) e o winmm.dll que o
    # jogo carrega pode ser uma sobra corrompida de instalacao antiga (crash
    # Bad Image 0xc0e90007). Pacote registrado primeiro, C:\XboxGames so como
    # fallback quando o pacote nao esta registrado ou sumiu do disco.
    $list = New-Object System.Collections.Generic.List[string]
    try {
        $appx = Get-AppxPackage -Name 'Microsoft.MinecraftUWP*' -AllUsers -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $appx) {
            $appx = Get-AppxPackage -Name 'Microsoft.MinecraftUWP*' -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if ($appx -and $appx.InstallLocation) {
            $list.Add($appx.InstallLocation)
            $sub = Join-Path $appx.InstallLocation 'Content'
            if ($sub -ne $appx.InstallLocation) { $list.Add($sub) }
        }
    } catch { }
    $list.Add('C:\XboxGames\Minecraft for Windows\Content')
    return $list
}

function Find-MinecraftContent {
    # Jogo RODANDO diz onde o winmm.dll e carregado de verdade: vale mais que
    # qualquer heuristica de caminho.
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
    # Sem exe em nenhum candidato: distingue "pacote registrado sem arquivos"
    # de "Minecraft nao instalado".
    $hasAppx = $false
    try {
        $appx = Get-AppxPackage -Name 'Microsoft.MinecraftUWP*' -ErrorAction SilentlyContinue | Select-Object -First 1
        $hasAppx = [bool]($appx -and $appx.InstallLocation)
    } catch { }
    if ($hasAppx) { throw (T 'err_package_incomplete') }
    throw (T 'err_content_not_found')
}

function Ensure-ContentWritable {
    param([string]$Content)
    # Pasta do pacote (WindowsApps) e protegida (TrustedInstaller): toma posse da
    # pasta e libera escrita para Administradores. Tambem garante o winmm.dll
    # (pode ter ACL restrita ou read-only - issue #45).
    & takeown.exe /f $Content 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { return $false }
    & icacls.exe $Content /grant '*S-1-5-32-544:(OI)(CI)F' 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { return $false }
    $winmm = Join-Path $Content 'winmm.dll'
    if (Test-Path $winmm) {
        Set-ItemProperty -Path $winmm -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        & takeown.exe /f $winmm 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
        & icacls.exe $winmm /grant '*S-1-5-32-544:(F)' 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
    }
    return $true
}

function Get-InstalledUnlockLabel {
    # Versao do unlock instalado, via hash -> rotulo. $null se nao instalado,
    # ou '<hash:12>' se o hash nao for reconhecido (DLL de outro fork?).
    try { $content = Find-MinecraftContent } catch { return $null }
    $winmm = Join-Path $content 'winmm.dll'
    if (-not (Test-Path $winmm)) { return $null }
    $actual = Get-SafeFileHash -Path $winmm
    if (-not $actual) { return $null }
    if ($unlockBuildLabels.ContainsKey($actual)) { return $unlockBuildLabels[$actual] }
    if ($unlockBuildLabelsArm64.ContainsKey($actual)) { return $unlockBuildLabelsArm64[$actual] }
    return ('<hash:' + $actual.Substring(0, 12) + '>')
}

function Get-GameVersion {
    param([string]$Content)
    if (-not $Content) { try { $Content = Find-MinecraftContent } catch { return $null } }
    $exe = Join-Path $Content 'Minecraft.Windows.exe'
    # 1) FileVersion do exe (caminho GDK). Validado em teste real 2026-09-04:
    #    pacotes Store 1.26.x negam leitura do exe (ACL WindowsApps) E o exe
    #    nao tem recurso de versao preenchido (vazio ate via imagem mapeada
    #    do processo rodando) - nessa rota falha sem problema.
    if (Test-Path $exe) {
        try {
            $fv = (Get-Item $exe -ErrorAction Stop).VersionInfo.FileVersion
            if ($fv) { return [string]$fv }
        } catch { }
    }
    # 2) Versao do PACOTE UWP (identidade Microsoft.MinecraftUWP_1.26.4501.0):
    #    sempre legivel, nao depende de ACL do exe. E a fonte da verdade na
    #    Store - mesma chave usada no tested-versions.json.
    try {
        $appx = Get-AppxPackage -Name 'Microsoft.MinecraftUWP*' -ErrorAction Stop | Select-Object -First 1
        if ($appx -and $appx.Version) { return [string]$appx.Version }
    } catch { }
    return $null
}

function Get-TestedVersionData {
    # Busca UMA vez por sessao (cache em $Script:TestedVersionData):
    # hashtable, $false (indisponivel) ou $null (ainda nao tentou).
    if ($null -ne $Script:TestedVersionData) { return $Script:TestedVersionData }
    $Script:TestedVersionData = $false
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $tmp = Join-Path ([IO.Path]::GetTempPath()) 'mbu-tested-versions.json'
        Invoke-WebRequest -UseBasicParsing -Uri "$base/tested-versions.json" -OutFile $tmp -TimeoutSec 8
        $Script:TestedVersionData = Get-Content $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    } catch { }
    return $Script:TestedVersionData
}

function Test-GameVersionTested {
    param([string]$Version)
    # $true = na lista testada; $false = fora da lista; $null = sem dados
    # (offline/404): o chamador escolhe o aviso adequado.
    $data = Get-TestedVersionData
    if (-not $data -or -not $data.tested) { return $null }
    return [bool]($data.tested.PSObject.Properties.Name -contains $Version)
}

function Test-UnlockCache {
    # Cache do binario x64 instalado e batendo com o hash atual? Caminho do
    # arquivo ou $null. (Somentes x64: e a unica variante com reinstalacao
    # offline garantida; arm64 ainda e beta.)
    $cached = Join-Path $cacheDir 'winmm.dll'
    if (-not (Test-Path $cached)) { return $null }
    $h = Get-SafeFileHash -Path $cached
    if ($h -eq $expectedHash) { return $cached }
    return $null
}

function Test-UnlockInstalled {
    # Retorna hashtable: installed, hash, isArm64, label, version.
    $info = @{ installed = $false; hash = $null; isArm64 = $false; label = $null; version = $null }
    try { $content = Find-MinecraftContent } catch { return $info }
    $winmm = Join-Path $content 'winmm.dll'
    if (-not (Test-Path $winmm)) { return $info }
    try {
        $actual = Get-SafeFileHash -Path $winmm
        $info.hash = $actual
        $machine = Get-PeMachineType -Path (Join-Path $content 'Minecraft.Windows.exe')
        if (-not $machine) {
            $info.installed = ($knownUnlockHashes -contains $actual) -or
                              ($knownUnlockHashesArm64 -contains $actual) -or
                              ($expectedHashArm64 -eq $actual)
            $info.label = Get-InstalledUnlockLabel
            return $info
        }
        if ($machine -eq 0xAA64) {
            $info.isArm64 = $true
            $info.installed = ($knownUnlockHashesArm64 -contains $actual) -or ($expectedHashArm64 -eq $actual)
        } else {
            $info.installed = ($knownUnlockHashes -contains $actual)
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
    # SHA256 a prova de antivirus (issue #49): se o arquivo sumiu ou nao pode
    # ser lido porque o AV esta bloqueando, nao explodimos nem derefenciamos
    # null. Retorna $null e quem chama escolhe a mensagem amigavel.
    param([string]$Path)
    try {
        $h = Get-FileHash -Path $Path -Algorithm SHA256 -ErrorAction Stop
        if ($h -and $h.Hash) { return $h.Hash.ToLowerInvariant() }
    } catch { }
    return $null
}

function Add-DefenderExclusions {
    param([string[]]$Paths)
    # Best-effort: adiciona exclusoes do Windows Defender (pastas + processo)
    # para a protecao em tempo real nao barrar a escrita do winmm.dll no %TEMP%
    # nem a copia para a pasta Content. Se falhar (sem admin / Tamper
    # Protection negando), nao quebra o instalador - retorna o que valeu.
    $effective = @()
    foreach ($p in $Paths) {
        if (-not $p) { continue }
        try {
            Add-MpPreference -ExclusionPath $p -ErrorAction Stop
            $effective += $p
        } catch { }
    }
    try {
        Add-MpPreference -ExclusionProcess 'Minecraft.Windows.exe' -ErrorAction Stop
        $effective += 'Minecraft.Windows.exe'
    } catch { }
    return $effective
}

function Close-Minecraft {
    $p = Get-Process Minecraft.Windows -ErrorAction SilentlyContinue
    if ($p) {
        Write-Host (T 'closing_mc')
        $p | Stop-Process -Force -ErrorAction SilentlyContinue
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Milliseconds 500
            if (-not (Get-Process Minecraft.Windows -ErrorAction SilentlyContinue)) { break }
        }
        Start-Sleep -Seconds 1
    }
}

function Install-Unlocker {
    $content = Find-MinecraftContent
    Write-Host "Content: $content"

    # Pasta fixa (nao GUID) para a exclusao do Defender cobrir exatamente o
    # local do download - mesmo padrao da v3.2.0 (%TEMP%\MinecraftBedrockUnlocker).
    # Limpa restos de runs antigos antes de criar.
    $tmp = Join-Path $env:TEMP 'mbu'
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $dll = Join-Path $tmp 'winmm.dll'
    try {
        # Exclusao ANTES do download: sem ela, a protecao em tempo real pode
        # bloquear a escrita do winmm.dll no %TEMP% (erro "contains a virus").
        # Cache incluido nas exclusoes: sem isso o Defender quarentena a copia
        # local logo apos a gravacao (validado em teste real 2026-09-04) e a
        # reinstalacao offline nunca teria o que usar.
        # Exclui tambem outras raizes com exe (ex.: copia antiga em C:\XboxGames
        # ao lado do pacote registrado no WindowsApps): o Defender pode atacar o
        # winmm.dll em qualquer uma delas, nao so na pasta que o instalador usa.
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
            Write-Host ((T 'av_exclusion_fail') -replace '\{0\}', "$tmp ; $content") -ForegroundColor Yellow
        }
        # Arquitetura do JOGO (nunca da sessao PS): campo Machine do PE do exe.
        # Se a leitura falhar, assume x64, o caso dominante, inclusive em PCs
        # WoA onde o jogo costuma rodar como x64 emulado. Chutar ARM64 pela
        # sessao baixou winmm-arm64.dll para jogo x64 e o jogo voltava pra
        # Trial sem crash, pois um DLL ARM64 nao carrega num processo x64.
        $machine = Get-PeMachineType -Path (Join-Path $content 'Minecraft.Windows.exe')
        $machineReadOk = ($machine -ne 0)
        if (-not $machineReadOk) {
            $machine = 0x8664
        }
        $isArm = ($machine -eq 0xAA64)
        $archLabel = if ($isArm) { 'ARM64' } else { 'x64' }
        $machineHex = '0x{0:X4}' -f $machine
        # Aviso proativo de versao do JOGO fora da lista testada (Melhor
        # esforco: sem dados ou sem versao, nao incomoda).
        if (-not $isArm) {
            $gameVer = Get-GameVersion -Content $content
            if ($gameVer) {
                $tested = Test-GameVersionTested -Version $gameVer
                if ($tested -eq $false) {
                    Write-Host (((T 'tested_warning') -replace '\{0\}', $gameVer)) -ForegroundColor Yellow
                }
            }
        }
        if ($machineReadOk) {
            Write-Host (((T 'arch_line') -replace '\{0\}', $archLabel) -replace '\{1\}', $machineHex)
        } else {
            Write-Host (T 'arch_unknown') -ForegroundColor Yellow
        }
        if ($isArm) {
            Write-Host (T 'arm64_detected') -ForegroundColor Cyan
        }
        # Hash esperado para a arquitetura desta instalacao. Usado em TODAS as
        # validacoes de integridade (download, copia atomica e pos-copia) para
        # que um PC ARM nunca seja comparado contra o hash x64 (e vice-versa) -
        # sem isso a instalacao ARM64 falharia nas etapas de copia por comparar
        # com o hash x64.
        $checkHash = if ($isArm) { $expectedHashArm64 } else { $expectedHash }
        Write-Host (T 'downloading_bin')
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $remoteDll = if ($isArm) { "$base/release/winmm-arm64.dll" } else { "$base/release/winmm.dll" }
        # O motor do Defender aplica exclusoes novas de forma assincrona e a
        # protecao na nuvem (block-at-first-sight) pode agir na escrita mesmo
        # com exclusao registrada (issue #49). Da tempo das exclusoes valerem
        # antes do primeiro download e retenta com o arquivo fresco.
        Start-Sleep -Seconds 2
        $actual = $null
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            Remove-Item $dll -Force -ErrorAction SilentlyContinue
            try {
                Invoke-WebRequest -UseBasicParsing -Uri $remoteDll -OutFile $dll
                # IWR marca o arquivo baixado com MotW (Zone.Identifier) e isso
                # reforca o block-at-first-sight do Defender: remove a marcacao.
                Unblock-File $dll -ErrorAction SilentlyContinue
            } catch {
                # Fallback OFFLINE: cache local do binario ja validado (mesma
                # arquitetura). Sem internet, o instalador morria aqui.
                $cached = if ($isArm) { $null } else { Test-UnlockCache }
                if ($cached) {
                    Copy-Item $cached $dll -Force
                    Unblock-File $dll -ErrorAction SilentlyContinue
                    Write-Host ((T 'cache_used') -replace '\{0\}', $cached) -ForegroundColor Yellow
                } else {
                    if ($isArm) {
                        Write-Host (T 'arm64_no_release') -ForegroundColor Red
                        Write-Host ((T 'track_releases') -replace '\{0\}', 'https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases') -ForegroundColor Yellow
                    }
                    throw
                }
            }
            # Arquivo presente, com tamanho e hash legiveis? Se o AV apagou ou
            # travou o arquivo na escrita, algo aqui falharia com erro cru ou
            # null ("You cannot call a method on a null-valued expression").
            try {
                if ((Test-Path $dll) -and ((Get-Item $dll -Force -ErrorAction Stop).Length -gt 0)) {
                    $actual = Get-SafeFileHash -Path $dll
                }
            } catch {
                $actual = $null
            }
            if ($actual) { break }
            if ($attempt -lt 3) {
                Write-Host (((T 'av_retrying') -replace '\{0\}', [string]$attempt) -replace '\{1\}', '3') -ForegroundColor Yellow
                $null = Add-DefenderExclusions -Paths @($tmp, $content)
                Start-Sleep -Seconds 5
            }
        }
        if (-not $actual) {
            throw ((T 'err_av_blocked') -replace '\{0\}', ($excluded -join ', '))
        }
        if ($checkHash) {
            if ($actual -ne $checkHash) { throw ((T 'err_hash_invalid') -replace '\{0\}', $actual) }
        } elseif ($isArm) {
            # Sem hash arm64 publicado ainda (fase beta): so verifica que o
            # arquivo existe e tem tamanho e gera um aviso, nao bloqueia.
            Write-Host (T 'arm64_hash_skipped') -ForegroundColor Yellow
        }

        Close-Minecraft

        # Garante escrita na pasta e no winmm.dll antes de mexer (WindowsApps e
        # protegido por TrustedInstaller; o winmm.dll do jogo pode ter ACL
        # restrita ou read-only - issue #45).
        if (-not (Ensure-ContentWritable -Content $content)) {
            throw (T 'err_acl')
        }

        $winmm = Join-Path $content 'winmm.dll'
        # Backup do original SO se o winmm.dll presente NAO for um unlock nosso
        # (hash conhecido): um DLL antigo do unlocker nao e o "original" do jogo -
        # copia-lo para .orig faria o "remover desbloqueio" restaurar um DLL que
        # continua desbloqueando o jogo.
        $isKnownUnlock = $false
        if (Test-Path $winmm) {
            try {
                $installedHash = Get-SafeFileHash -Path $winmm
                $isKnownUnlock = (($knownUnlockHashes -contains $installedHash) -or
                                  ($knownUnlockHashesArm64 -contains $installedHash) -or
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

        # Copia atomica: grava em .new, valida o hash e so entao substitui o
        # original. Evita deixar um winmm.dll truncado (o Minecraft abriria com
        # "Bad Image" 0xc0e90007).
        $stagedDll = Join-Path $content 'winmm.dll.new'
        Remove-Item $stagedDll -Force -ErrorAction SilentlyContinue
        Copy-Item $dll $stagedDll -Force
        if ($checkHash -and (Get-SafeFileHash -Path $stagedDll) -ne $checkHash) {
            Remove-Item $stagedDll -Force -ErrorAction SilentlyContinue
            throw (T 'err_copy_corrupt')
        }
        if (Test-Path $winmm) {
            Remove-Item $winmm -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $winmm) {
            Remove-Item $stagedDll -Force -ErrorAction SilentlyContinue
            throw (T 'err_replace')
        }
        Move-Item $stagedDll $winmm -Force
        # Antivirus pode quarentenar o DLL logo apos a copia: valida de novo e,
        # se corromper, restaura o original (o jogo volta a rodar como Trial).
        if ($checkHash -and (Get-SafeFileHash -Path $winmm) -ne $checkHash) {
            $orig = Join-Path $content 'winmm.dll.orig'
            if (Test-Path $orig) {
                Remove-Item $winmm -Force -ErrorAction SilentlyContinue
                Copy-Item $orig $winmm -Force -ErrorAction SilentlyContinue
            }
            throw (T 'err_av_quarantine')
        }
        # Cache do binario recem-validado pra reinstalacao offline (x64).
        if (-not $isArm) {
            try {
                New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
                Copy-Item $winmm (Join-Path $cacheDir 'winmm.dll') -Force
                Write-Host ((T 'cache_saved') -replace '\{0\}', $cacheDir) -ForegroundColor DarkGray
            } catch { }
        }
        Write-Host (T 'install_ok')
        Send-DownloadHit
        Start-Minecraft
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}

function Restore-Original {
    $content = Find-MinecraftContent
    Close-Minecraft

    $null = Ensure-ContentWritable -Content $content

    $winmm = Join-Path $content 'winmm.dll'
    $orig = Join-Path $content 'winmm.dll.orig'

    if (-not (Test-UnlockInstalled) -and -not (Test-Path $orig)) {
        Write-Host (T 'nothing_to_restore')
        return
    }

    Remove-Item $winmm -Force -ErrorAction SilentlyContinue
    if (Test-Path $orig) {
        Move-Item $orig $winmm -Force
        Write-Host (T 'restored_ok')
    } else {
        Write-Host (T 'removed_ok')
    }
    Write-Host (T 'unlock_removed')
    Start-Minecraft
}

function Send-DownloadHit {
    # Conta 1 instalacao no contador (Worker + KV). Fire-and-forget: qualquer
    # falha (offline/timeout) e ignorada - nunca quebra nem atrasa o instalador.
    # Nenhum dado pessoal e enviado: apenas um POST anonimo em /hit.
    try {
        Invoke-WebRequest -UseBasicParsing -Uri 'https://mbu-download-counter.xgobg2020.workers.dev/hit' -Method Post -TimeoutSec 5 | Out-Null
    } catch { }
}

function Start-Minecraft {
    $opened = $false
    try {
        $content = Find-MinecraftContent
        $appx = Get-AppxPackage -Name 'Microsoft.MinecraftUWP*' -ErrorAction SilentlyContinue | Select-Object -First 1
        $isStore = $appx -and ($content -eq $appx.InstallLocation)
        if ($isStore) {
            # Store (UWP): AUMID com o AppId real do manifest ("Game", nao "App").
            $appId = 'Game'
            try {
                $m = Get-AppxPackageManifest -Package $appx.PackageFullName -ErrorAction Stop
                $id = $m.Package.Applications.Application | Select-Object -First 1 -ExpandProperty Id
                if ($id) { $appId = $id }
            } catch { }
            Start-Process "shell:AppsFolder\$($appx.PackageFamilyName)!$appId" -ErrorAction Stop
        } else {
            # GDK (Xbox App): abre o executavel direto no Content.
            $exe = Join-Path $content 'Minecraft.Windows.exe'
            if (Test-Path $exe) {
                Start-Process -FilePath $exe -WorkingDirectory $content -ErrorAction Stop
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
            if (Get-Process Minecraft.Windows -ErrorAction SilentlyContinue) { $opened = $true }
        } catch { }
    }
    if ($opened) {
        Write-Host (T 'mc_started')
    } else {
        Write-Host (T 'mc_start_failed')
    }
}

function Get-DefenderMbuExclusions {
    # Exclusoes do Defender relacionadas ao unlocker/ao jogo (best-effort:
    # pode falhar por permissao - retorna lista vazia e o diagnostico mostra
    # "indisponivel" ao inves de quebrar).
    $found = @()
    try {
        $pref = Get-MpPreference -ErrorAction Stop
        $needles = @('\\mbu', 'XboxGames\\Minecraft', 'MinecraftUWP', 'Minecraft.Windows')
        foreach ($p in @($pref.ExclusionPath)) {
            if ($p -and ($needles | Where-Object { $p -match $_ })) { $found += $p }
        }
        foreach ($p in @($pref.ExclusionProcess)) {
            if ($p -and ($needles | Where-Object { $p -match $_ })) { $found += "proc: $p" }
        }
    } catch { }
    return $found
}

function Insert-DiagnosticReport {
    # Relatorio pronto pro Discord: copia pro clipboard (best-effort) e
    # imprime na tela. Nada pessoal: so OS, PS, admin, versao/origem/arc do
    # jogo, estado do unlock, aviso de versao nao testada, exclusoes e cache.
    Show-Banner
    Write-Host "  $(T 'diag_title')" -ForegroundColor Cyan
    Write-Host ''
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add((T 'diag_title'))
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $osLine = "$($os.Caption) build $($os.BuildNumber)"
    } catch { $osLine = 'Windows (unknown)' }
    try { $psLine = $PSVersionTable.PSVersion.ToString() } catch { $psLine = '?' }
    $isAdmin = Test-IsAdmin
    $yesNo = { param($b) if ($b) { T 'diag_yes' } else { T 'diag_no' } }
    $lines.Add("$(T 'diag_os'): $osLine")
    $lines.Add("$(T 'diag_ps'): $psLine")
    $lines.Add("$(T 'diag_admin'): $(& $yesNo $isAdmin)")
    Write-Host "  $(T 'diag_os'): $osLine"
    Write-Host "  $(T 'diag_ps'): $psLine"
    Write-Host "  $(T 'diag_admin'): $(if ($isAdmin) { T 'diag_yes' } else { T 'diag_no' })"
    Write-Host ''
    $gameVer = $null
    try {
        $content = Find-MinecraftContent
        $appx = Get-AppxPackage -Name 'Microsoft.MinecraftUWP*' -ErrorAction SilentlyContinue | Select-Object -First 1
        $source = if ($appx -and ($content -eq $appx.InstallLocation)) { T 'diag_source_store' }
                  elseif ($content -like 'C:\XboxGames*') { T 'diag_source_gdk' }
                  else { T 'diag_source_unknown' }
        $lines.Add("$(T 'diag_content'): $content")
        $lines.Add("$(T 'diag_source'): $source")
        Write-Host "  $(T 'diag_content'): $content"
        Write-Host "  $(T 'diag_source'): $source"
        $machine = Get-PeMachineType -Path (Join-Path $content 'Minecraft.Windows.exe')
        $arch = if ($machine -eq 0xAA64) { 'ARM64' } elseif ($machine -eq 0x8664) { 'x64' } else { '?' }
        $gameVer = Get-GameVersion -Content $content
        if ($gameVer) { $lines.Add("$(T 'diag_game_version'): $gameVer") ; Write-Host "  $(T 'diag_game_version'): $gameVer" }
        $lines.Add("$(T 'diag_game_arch'): $arch (Machine=$(if ($machine) { '0x{0:X4}' -f $machine } else { 'ilegivel' }))")
        Write-Host "  $(T 'diag_game_arch'): $arch"
        # Todas as raizes com exe (copia antiga em C:\XboxGames + pacote
        # registrado): expoe o caso em que o jogo carrega o winmm.dll de uma
        # pasta diferente da que o instalador usaria (crash Bad Image com o
        # unlock verificado na copia errada).
        foreach ($cand in Get-MinecraftCandidates) {
            if (-not (Test-Path $cand)) { continue }
            if (-not (Test-Path (Join-Path $cand 'Minecraft.Windows.exe'))) { continue }
            $cwm = Join-Path $cand 'winmm.dll'
            $cstate = if (Test-Path $cwm) { 'winmm.dll presente' } else { 'sem winmm.dll' }
            $cmark = if ($cand -eq $content) { '  <- pasta usada' } else { '' }
            $cl = "[candidato] $cand  ($cstate)$cmark"
            $lines.Add($cl)
            Write-Host "  $cl"
        }
    } catch {
        $lines.Add("$(T 'diag_content'): $($_.Exception.Message)")
        Write-Host "  $(T 'diag_content'): $($_.Exception.Message)" -ForegroundColor Yellow
    }
    Write-Host ''
    $state = Test-UnlockInstalled
    $unlockLine = if ($state.installed) {
        if ($state.label) { $state.label } else { "$(T 'diag_yes') ($($state.hash))" }
    } else { T 'diag_unlock_none' }
    $lines.Add("$(T 'diag_unlock'): $unlockLine")
    Write-Host "  $(T 'diag_unlock'): $unlockLine"
    if ($state.installed -and $state.label -and ($state.label -match '^v') -and ($state.label.TrimStart('v') -ne $Script:Version)) {
        $lines.Add((T 'state_older_hint') -replace '\{0\}', $state.label -replace '\{1\}', $Script:Version)
        Write-Host "  $((T 'state_older_hint') -replace '\{0\}', $state.label -replace '\{1\}', $Script:Version)" -ForegroundColor Yellow
    }
    if ($state.hash -and -not $state.installed) {
        $lines.Add("  winmm hash: $($state.hash)")
        Write-Host "  winmm hash: $($state.hash)" -ForegroundColor Yellow
    }
    $tested = if ($gameVer) { Test-GameVersionTested -Version $gameVer } else { $null }
    $testedLine = if ($null -eq $tested -or -not $gameVer) { T 'diag_tested_unknown' }
                  elseif ($tested) { T 'diag_tested_ok' }
                  else { T 'diag_tested_bad' }
    $lines.Add("$(T 'diag_tested'): $testedLine")
    Write-Host "  $(T 'diag_tested'): $testedLine"
    $excl = Get-DefenderMbuExclusions
    $exclLine = if ($excl.Count -gt 0) { $excl -join '; ' } else { T 'diag_av_none' }
    $lines.Add("$(T 'diag_av'): $exclLine")
    Write-Host "  $(T 'diag_av'): $exclLine"
    $cached = Test-UnlockCache
    $cacheLine = if ($cached) { (T 'diag_cache_ok') -replace '\{0\}', $cached } elseif (Test-Path (Join-Path $cacheDir 'winmm.dll')) { T 'diag_cache_bad' } else { T 'diag_cache_none' }
    $lines.Add("$(T 'diag_cache'): $cacheLine")
    Write-Host "  $(T 'diag_cache'): $cacheLine"
    Write-Host ''
    $report = $lines -join "`n"
    $copied = $false
    try { Set-Clipboard -Value $report -ErrorAction Stop; $copied = $true } catch { }
    if ($copied) {
        Write-Host "  $(T 'diag_clipboard_ok')" -ForegroundColor Green
    } else {
        Write-Host "  $(T 'diag_clipboard_fail')" -ForegroundColor Yellow
    }
}

# Modo de teste (VM/CI/dot-source): com MBU_NO_LOOP=1 o arquivo apenas define
# as funcoes e sai, sem entrar no loop interativo do menu.
if ($env:MBU_NO_LOOP -eq '1') { return }

while ($true) {
    Show-Banner
    $greeting = Get-TimeGreeting
    $state = Test-UnlockInstalled
    $isInstalled = $state.installed

    Write-Host ''
    if ($isInstalled) {
        $label = if ($state.label) { $state.label } else { $Script:Version }
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
    Write-Host "    [3] $(T 'menu_3_diag')"
    Write-Host "    [4] $(T 'menu_4_trouble')"
    Write-Host "    [5] $(T 'menu_5_discord')"
    Write-Host "    [6] $(T 'menu_6_bmc')"
    Write-Host "    [0] $(T 'menu_0')"
    Write-Host ''
    $choice = Read-Host "  $(T 'choose_option')"
    switch ($choice) {
        '1' { try { if ($isInstalled) { Restore-Original } else { Install-Unlocker } } catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Red } }
        '2' { try { if ($isInstalled) { Install-Unlocker } } catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Red } }
        '3' { try { Insert-DiagnosticReport } catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Red } }
        '4' { try { Start-Process $urls['troubleshooting'] } catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Red } }
        '5' { try { Start-Process $urls['discord'] } catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Red } }
        '6' { try { Start-Process $urls['donate'] } catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Red } }
        '0' { return }
        default { Write-Host "  $(T 'invalid_option')" -ForegroundColor Yellow }
    }
    if ($choice -eq '0') { break }
    Write-Host ''
    Read-Host "  $(T 'press_enter')"
}
