# menu.ps1 - Minecraft Bedrock Free - menu interativo (open source, GPLv3).
# Suporte a 8 idiomas (pt/en/es/fr/zh/hi/ar/ru) com deteccao automatica.
$ErrorActionPreference = 'Stop'
$Script:Version = '4.3.0'
$base = 'https://raw.githubusercontent.com/CoelhoFZ/Minecraft-Bedrock-Free/main'
$expectedHash = '86689c9724be7f391ba9bd1f4ef8dddaa73baec0b76b9c73bebef89f37b76e97'

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
    'err_content_not_found' = 'Content do Minecraft nao encontrado. Instale o Minecraft pelo Xbox App.'
    'err_store_not_supported' = 'Versao da Microsoft Store NAO suportada. Instale o Minecraft pelo Xbox App.'
    'closing_mc'         = 'Fechando Minecraft...'
    'downloading_bin'    = 'Baixando o binario (winmm.dll)...'
    'err_hash_invalid'   = 'Hash do winmm.dll invalido: {0}'
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
}

$Script:I18N = @{
    'greet_morning' = @{ en='Good morning'; zh='早上好'; hi='सुप्रभात'; es='Buenos días'; fr='Bonjour'; ar='صباح الخير'; ru='Доброе утро' }
    'greet_afternoon' = @{ en='Good afternoon'; zh='下午好'; hi='शुभ दोपहर'; es='Buenas tardes'; fr='Bon après-midi'; ar='مساء الخير'; ru='Добрый день' }
    'greet_evening' = @{ en='Good evening'; zh='晚上好'; hi='शुभ संध्या'; es='Buenas noches'; fr='Bonsoir'; ar='مساء النور'; ru='Добрый вечер' }
    'err_content_not_found' = @{ en='Minecraft Content folder not found. Install Minecraft from the Xbox App.'; zh='未找到 Minecraft Content 文件夹。请从 Xbox 应用安装 Minecraft。'; hi='Minecraft Content फ़ोल्डर नहीं मिला। Xbox App से Minecraft इंस्टॉल करें।'; es='No se encontró la carpeta Content de Minecraft. Instala Minecraft desde la Xbox App.'; fr='Dossier Content de Minecraft introuvable. Installez Minecraft depuis l''application Xbox.'; ar='لم يتم العثور على مجلد Content الخاص بـ Minecraft. ثبّت Minecraft من تطبيق Xbox.'; ru='Папка Content Minecraft не найдена. Установите Minecraft из приложения Xbox.' }
    'err_store_not_supported' = @{ en='Microsoft Store version is NOT supported. Install Minecraft from the Xbox App.'; zh='不支持 Microsoft Store 版本。请通过 Xbox 应用安装 Minecraft。'; hi='Microsoft Store संस्करण समर्थित नहीं है। Xbox App से Minecraft इंस्टॉल करें।'; es='La versión de Microsoft Store NO es compatible. Instala Minecraft desde la Xbox App.'; fr='La version Microsoft Store n''est PAS prise en charge. Installez Minecraft depuis l''application Xbox.'; ar='إصدار Microsoft Store غير مدعوم. ثبّت Minecraft من تطبيق Xbox.'; ru='Версия из Microsoft Store НЕ поддерживается. Установите Minecraft из приложения Xbox.' }
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
    Write-Host ""
}

function Get-TimeGreeting {
    $hour = (Get-Date).Hour
    if ($hour -ge 6 -and $hour -lt 12) { return T 'greet_morning' }
    elseif ($hour -ge 12 -and $hour -lt 18) { return T 'greet_afternoon' }
    else { return T 'greet_evening' }
}

function Find-MinecraftContent {
    # Xbox App (suportada): instala em C:\XboxGames\Minecraft for Windows\Content.
    $xbox = 'C:\XboxGames\Minecraft for Windows\Content'
    if ((Test-Path $xbox) -and (Test-Path (Join-Path $xbox 'Minecraft.Windows.exe'))) {
        return $xbox
    }
    # Microsoft Store (NAO suportada): instala em C:\Program Files\WindowsApps\...
    $appx = Get-AppxPackage -Name 'Microsoft.MinecraftUWP*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($appx -and $appx.InstallLocation -and ($appx.InstallLocation -like '*WindowsApps*')) {
        throw (T 'err_store_not_supported')
    }
    throw (T 'err_content_not_found')
}

function Test-UnlockInstalled {
    try { $content = Find-MinecraftContent } catch { return $false }
    $winmm = Join-Path $content 'winmm.dll'
    if (-not (Test-Path $winmm)) { return $false }
    try {
        $actual = (Get-FileHash -Path $winmm -Algorithm SHA256).Hash.ToLowerInvariant()
        return ($actual -eq $expectedHash)
    } catch { return $false }
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

    $tmp = Join-Path $env:TEMP ('mbu-{0}' -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $dll = Join-Path $tmp 'winmm.dll'
    try {
        Write-Host (T 'downloading_bin')
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri "$base/release/winmm.dll" -OutFile $dll
        $actual = (Get-FileHash -Path $dll -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $expectedHash) { throw ((T 'err_hash_invalid') -replace '\{0\}', $actual) }

        Close-Minecraft

        $winmm = Join-Path $content 'winmm.dll'
        if ((Test-Path $winmm) -and -not (Test-Path (Join-Path $content 'winmm.dll.orig'))) {
            Copy-Item $winmm (Join-Path $content 'winmm.dll.orig') -Force
            Write-Host (T 'backup_orig')
        }

        foreach ($f in @('dlllist.txt','unlock-CoelhoFZ.dll','unlock-CoelhoFZ.ini','unlocker-CoelhoFZ.dll','unlocker-CoelhoFZ.ini','XGameCore.GDK.dll','XGameCore.GDK.ini')) {
            Remove-Item (Join-Path $content $f) -Force -ErrorAction SilentlyContinue
        }

        # O winmm.dll do jogo pode ter ACL restrita ou read-only (dono SYSTEM).
        # O instalador roda elevado: toma posse e limpa antes de copiar
        # (sem isso o Copy-Item falha com "Access denied" - issue #45).
        if (Test-Path $winmm) {
            try { Set-ItemProperty -Path $winmm -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue } catch { }
            try { Remove-Item $winmm -Force -ErrorAction SilentlyContinue } catch { }
        }
        if (Test-Path $winmm) {
            # ACL restrita (dono SYSTEM/TrustedInstaller): toma posse e libera escrita.
            try { & takeown /f $winmm 2>&1 | Out-Null } catch { }
            try { & icacls $winmm /grant '*S-1-5-32-544:(F)' 2>&1 | Out-Null } catch { }
            try { Remove-Item $winmm -Force -ErrorAction SilentlyContinue } catch { }
        }
        Copy-Item $dll $winmm -Force
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
        $exe = Join-Path $content 'Minecraft.Windows.exe'
        if (Test-Path $exe) {
            Start-Process -FilePath $exe -WorkingDirectory $content -ErrorAction Stop
            $opened = $true
        }
    } catch { }
    if (-not $opened) {
        try {
            Start-Process 'shell:AppsFolder\Microsoft.MinecraftUWP_8wekyb3d8bbwe!App' -ErrorAction Stop
            $opened = $true
        } catch { }
    }
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
