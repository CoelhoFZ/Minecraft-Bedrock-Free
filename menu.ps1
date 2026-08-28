# menu.ps1 - Minecraft Bedrock Free - menu interativo (open source, GPLv3).
# Suporte a 8 idiomas (pt/en/es/fr/zh/hi/ar/ru) com deteccao automatica.
#
# IMPORTANTE: o i.ps1 (bootstrap via irm | iex) valida o hash SHA256 DESTE
# arquivo antes de executa-lo. Qualquer edicao aqui muda o hash e quebra o
# bootstrap ate que o $menuHash no i.ps1 seja atualizado. Apos editar, rode:
#   (Get-FileHash .\menu.ps1 -Algorithm SHA256).Hash.ToLowerInvariant()
# e cole o resultado em i.ps1 (variavel $menuHash).
$ErrorActionPreference = 'Stop'
$Script:Version = '4.4.2'
$base = 'https://raw.githubusercontent.com/CoelhoFZ/Minecraft-Bedrock-Free/main'
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
}

$Script:I18N = @{
    'err_acl' = @{ en='Could not take ownership of the Minecraft folder. Run as administrator.'; es='No se pudo tomar posesion de la carpeta de Minecraft. Ejecuta como administrador.' }
    'err_copy_corrupt' = @{ en='Failed to copy winmm.dll (corrupted/blocked copy). Check if your antivirus blocked it and try again.'; es='Error al copiar winmm.dll (copia corrupta/bloqueada). Comprueba si tu antivirus lo bloqueo e intentalo de nuevo.' }
    'err_replace' = @{ en='Could not replace winmm.dll (access denied or file in use). Close Minecraft and run as administrator.'; es='No se pudo reemplazar winmm.dll (acceso denegado o archivo en uso). Cierra Minecraft y ejecuta como administrador.' }
    'err_av_quarantine' = @{ en='winmm.dll was corrupted/removed by antivirus right after copying. Add an exclusion for the Minecraft folder and run again.'; es='winmm.dll fue corrompido/eliminado por el antivirus justo despues de copiarlo. Anade una exclusion para la carpeta de Minecraft y vuelve a intentarlo.' }
    'err_av_blocked' = @{ en='Your antivirus blocked the downloaded winmm.dll even with the automatic exclusion. Open Windows Security, go to Virus & threat protection, open Protection history, find the blocked winmm.dll and choose Allow or Restore. Then add the exclusions manually for: {0}. If you use another antivirus, add the same exclusions there too. Run the installer again.'; es='Tu antivirus bloqueo la descarga de winmm.dll incluso con la exclusion automatica. Abra Seguridad de Windows, vaya a Proteccion contra virus y amenazas, abra el Historial de proteccion, encuentre el winmm.dll bloqueado y elija Permitir o Restaurar. Despues anada manualmente las exclusiones para: {0}. Si usa otro antivirus, anada las mismas exclusiones alli tambien. Ejecute el instalador de nuevo.' }
    'av_retrying' = @{ en='The antivirus may have removed the downloaded file. Retrying ({0}/{1})...'; es='El antivirus pudo haber eliminado el archivo descargado. Reintentando ({0}/{1})...' }
    'av_exclusion_ok' = @{ en='Windows Defender exclusion added for: {0}'; pt='Exclusao do Windows Defender adicionada para: {0}'; es='Exclusion de Windows Defender anadida para: {0}' }
    'av_exclusion_fail' = @{ en='Could not add the Windows Defender exclusion automatically. Run as administrator or add it manually: {0}'; pt='Nao foi possivel adicionar a exclusao do Windows Defender automaticamente. Rode como administrador ou adicione manualmente: {0}'; es='No se pudo anadir la exclusion de Windows Defender automaticamente. Ejecuta como administrador o anadela manualmente: {0}' }
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

function Find-MinecraftContent {
    # Xbox App (GDK/MSIXVC): instala em C:\XboxGames\Minecraft for Windows\Content.
    $xbox = 'C:\XboxGames\Minecraft for Windows\Content'
    if ((Test-Path $xbox) -and (Test-Path (Join-Path $xbox 'Minecraft.Windows.exe'))) {
        return $xbox
    }
    # Microsoft Store (UWP): instala em C:\Program Files\WindowsApps\Microsoft.MinecraftUWP_*.
    # O InstallLocation do pacote vale para a Store e tambem para outros drives.
    $appx = Get-AppxPackage -Name 'Microsoft.MinecraftUWP*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($appx -and $appx.InstallLocation) {
        # GDK (Xbox App) fora do drive canonico pode resolver o InstallLocation
        # para a RAIZ do jogo, com o exe dentro de \Content (mesmo layout que o
        # uninstall.ps1 ja cobre). Tenta as duas formas antes de desistir.
        foreach ($c in @($appx.InstallLocation, (Join-Path $appx.InstallLocation 'Content'))) {
            if (Test-Path (Join-Path $c 'Minecraft.Windows.exe')) {
                return $c
            }
        }
        throw (T 'err_package_incomplete')
    }
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

function Test-UnlockInstalled {
    try { $content = Find-MinecraftContent } catch { return $false }
    $winmm = Join-Path $content 'winmm.dll'
    if (-not (Test-Path $winmm)) { return $false }
    try {
        $actual = Get-SafeFileHash -Path $winmm
        # Arquitetura do JOGO (nao da sessao PS): decide qual lista de hashes
        # validos consultar. Se a arquitetura nao puder ser lida, aceita
        # qualquer hash valido das duas listas (x64 + arm64) para nao falso
        # "TRIAL" num PC em que o exe esta protegido/ilegivel (GitHub issue #49
        # tambem cobre leitura do DLL; aqui e leitura do exe para o Machine).
        $machine = Get-PeMachineType -Path (Join-Path $content 'Minecraft.Windows.exe')
        # Sem chute de arquitetura da SESSAO: se a leitura do PE falhar, o
        # bloco abaixo aceita hashes das duas listas (x64 e arm64). O fallback
        # antigo via PROCESSOR_ARCHITECTURE escolheu o DLL errado em PC WoA
        # com o jogo rodando como x64 emulado.
        if ($machine) {
            if ($machine -eq 0xAA64) {
                return ($knownUnlockHashesArm64 -contains $actual) -or ($expectedHashArm64 -eq $actual)
            }
            return ($knownUnlockHashes -contains $actual)
        }
        return (($knownUnlockHashes -contains $actual) -or ($knownUnlockHashesArm64 -contains $actual))
    } catch { return $false }
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
        $excluded = Add-DefenderExclusions -Paths @($tmp, $content)
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
                if ($isArm) {
                    Write-Host (T 'arm64_no_release') -ForegroundColor Red
                    Write-Host ((T 'track_releases') -replace '\{0\}', 'https://github.com/CoelhoFZ/Minecraft-Bedrock-Free/releases') -ForegroundColor Yellow
                }
                throw
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

while ($true) {
    Show-Banner
    $greeting = Get-TimeGreeting
    $isInstalled = Test-UnlockInstalled

    Write-Host ''
    if ($isInstalled) {
        Write-Host "  $greeting! $(T 'state_unlocked')" -ForegroundColor Green
        Write-Host "  $(T 'state_unlocked_hint')" -ForegroundColor DarkGray
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
    Write-Host "    [0] $(T 'menu_0')"
    Write-Host ''
    $choice = Read-Host "  $(T 'choose_option')"
    switch ($choice) {
        '1' { try { if ($isInstalled) { Restore-Original } else { Install-Unlocker } } catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Red } }
        '2' { try { if ($isInstalled) { Install-Unlocker } } catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Red } }
        '0' { return }
        default { Write-Host "  $(T 'invalid_option')" -ForegroundColor Yellow }
    }
    if ($choice -eq '0') { break }
    Write-Host ''
    Read-Host "  $(T 'press_enter')"
}
