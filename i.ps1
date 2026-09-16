$ErrorActionPreference = 'Stop'

$base = if ($env:MBU_BASE_URL) {
    $env:MBU_BASE_URL.TrimEnd('/')
} else {
    'https://raw.githubusercontent.com/CoelhoFZ/Minecraft-Bedrock-Free/main'
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Resolve-MbuLang {
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
        foreach ($language in (Get-WinUserLanguageList -ErrorAction SilentlyContinue)) {
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
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        $value = $candidate.Trim().ToLowerInvariant()
        switch -Wildcard ($value) {
            'pt*' {
                return 'pt'
            } '*portugu*' {
                return 'pt'
            } '*brasil*' {
                return 'pt'
            } '*brazil*' {
                return 'pt'
            }
            'en*' {
                return 'en'
            } '*english*' {
                return 'en'
            }
            'es*' {
                return 'es'
            } '*spanish*' {
                return 'es'
            } '*espanol*' {
                return 'es'
            } '*español*' {
                return 'es'
            }
            'fr*' {
                return 'fr'
            } '*french*' {
                return 'fr'
            } '*francais*' {
                return 'fr'
            } '*français*' {
                return 'fr'
            }
            'zh*' {
                return 'zh'
            } '*chinese*' {
                return 'zh'
            }
            'hi*' {
                return 'hi'
            } '*hindi*' {
                return 'hi'
            }
            'ar*' {
                return 'ar'
            } '*arabic*' {
                return 'ar'
            }
            'ru*' {
                return 'ru'
            } '*russian*' {
                return 'ru'
            }
        }
    }
    return 'en'
}
$Script:MbuLang = Resolve-MbuLang
$Script:Msg = @{
    'err_menu_hash' = @{
        pt='ERRO: o hash do menu.ps1 baixado nao confere com o esperado.'
        en='ERROR: the hash of the downloaded menu.ps1 does not match the expected one.'
        es='ERROR: el hash del menu.ps1 descargado no coincide con el esperado.'
        fr='ERREUR : le hash du menu.ps1 téléchargé ne correspond pas à celui attendu.'
        zh='错误：下载的 menu.ps1 哈希与预期不符。'
        hi='त्रुटि: डाउनलोड किए गए menu.ps1 का हैश अपेक्षित से मेल नहीं खाता।'
        ar='خطأ: تجزئة menu.ps1 التي تم تنزيلها لا تطابق المتوقعة.'
        ru='ОШИБКА: хеш загруженного menu.ps1 не совпадает с ожидаемым.'
    }
    'err_menu_download' = @{
        pt='Nao foi possivel baixar o menu.ps1. Verifique sua conexao com a internet e rode o instalador de novo.'
        en='Could not download menu.ps1. Check your internet connection and run the installer again.'
        es='No se pudo descargar el menu.ps1. Verifica tu conexion a internet y vuelve a ejecutar el instalador.'
        fr='Impossible de telecharger le menu.ps1. Verifiez votre connexion internet et relancez l''installateur.'
        zh='无法下载 menu.ps1。请检查网络连接后重新运行安装程序。'
        hi='menu.ps1 डाउनलोड नहीं हो सका। अपने इंटरनेट कनेक्शन की जाँच करें और इंस्टॉलर फिर से चलाएँ।'
        ar='تعذّر تنزيل menu.ps1. تحقق من اتصالك بالإنترنت وشغّل المثبّت مرة أخرى.'
        ru='Не удалось скачать menu.ps1. Проверьте подключение к интернету и запустите установщик снова.'
    }
    'err_expected' = @{
        pt='  Esperado: {0}'
        en='  Expected: {0}'
        es='  Esperado: {0}'
        fr='  Attendu : {0}'
        zh='  预期值：{0}'
        hi='  अपेक्षित: {0}'
        ar='  المتوقع: {0}'
        ru='  Ожидалось: {0}'
    }
    'err_received' = @{
        pt='  Recebido: {0}'
        en='  Received: {0}'
        es='  Recibido: {0}'
        fr='  Reçu : {0}'
        zh='  实际值：{0}'
        hi='  प्राप्त: {0}'
        ar='  المستلم: {0}'
        ru='  Получено: {0}'
    }
    'err_stale_1' = @{
        pt='Isso geralmente significa que o menu.ps1 no repositorio foi atualizado sem sincronizar o hash neste bootstrap (i.ps1).'
        en='This usually means menu.ps1 in the repository was updated without syncing the hash in this bootstrap (i.ps1).'
        es='Esto generalmente significa que el menu.ps1 del repositorio se actualizo sin sincronizar el hash en este bootstrap (i.ps1).'
        fr='Cela signifie généralement que le menu.ps1 du dépôt a été mis à jour sans synchroniser le hash dans ce bootstrap (i.ps1).'
        zh='这通常意味着仓库中的 menu.ps1 已更新，但未同步此引导脚本 (i.ps1) 中的哈希。'
        hi='इसका आम तौर पर मतलब है कि रिपॉज़िटरी में menu.ps1 को इस बूटस्ट्रैप (i.ps1) में हैश सिंक किए बिना अपडेट किया गया।'
        ar='هذا يعني عادةً أنه تم تحديث menu.ps1 في المستودع دون مزامنة التجزئة في هذا المُشغّل (i.ps1).'
        ru='Обычно это означает, что menu.ps1 в репозитории был обновлён без синхронизации хеша в этом загрузчике (i.ps1).'
    }
    'err_stale_2' = @{
        pt='Se voce nao e o mantenedor, desconfie do link que usou.'
        en='If you are not the maintainer, be suspicious of the link you used.'
        es='Si no eres el mantenedor, desconfia del enlace que usaste.'
        fr='Si vous n''êtes pas le mainteneur, méfiez-vous du lien utilisé.'
        zh='如果您不是维护者，请警惕您使用的链接。'
        hi='यदि आप अनुरक्षक नहीं हैं, तो आपके द्वारा उपयोग किए गए लिंक पर संदेह करें।'
        ar='إذا لم تكن المشرف، فكن متشككًا في الرابط الذي استخدمته.'
        ru='Если вы не сопровождающий, отнеситесь с подозрением к использованной ссылке.'
    }
    'press_enter_close' = @{
        pt='Pressione Enter para fechar esta janela'
        en='Press Enter to close this window'
        es='Pulse Enter para cerrar esta ventana'
        fr='Appuyez sur Entrée pour fermer cette fenêtre'
        zh='按 Enter 键关闭此窗口'
        hi='इस विंडो को बंद करने के लिए Enter दबाएँ'
        ar='اضغط Enter لإغلاق هذه النافذة'
        ru='Нажмите Enter для закрытия этого окна'
    }
    'uac_request' = @{
        pt='Solicitando permissao de administrador (UAC)...'
        en='Requesting administrator permission (UAC)...'
        es='Solicitando permiso de administrador (UAC)...'
        fr='Demande de permission administrateur (UAC)...'
        zh='正在请求管理员权限 (UAC)...'
        hi='व्यवस्थापक अनुमति का अनुरोध किया जा रहा है (UAC)...'
        ar='جارٍ طلب إذن المسؤول (UAC)...'
        ru='Запрос разрешения администратора (UAC)...'
    }
    'err_launch_title' = @{
        pt='ERRO: o instalador nao conseguiu abrir com permissao de administrador.'
        en='ERROR: the installer could not open with administrator permission.'
        es='ERROR: el instalador no pudo abrirse con permiso de administrador.'
        fr='ERREUR : l''installateur n''a pas pu s''ouvrir avec les droits d''administrateur.'
        zh='错误：安装程序无法以管理员权限打开。'
        hi='त्रुटि: इंस्टॉलर व्यवस्थापक अनुमति के साथ नहीं खुल सका।'
        ar='خطأ: تعذّر فتح المثبّت بصلاحيات المسؤول.'
        ru='ОШИБКА: установщик не смог открыться с правами администратора.'
    }
    'err_launch_hint' = @{
        pt='Rode o comando abaixo em um PowerShell aberto como administrador:'
        en='Run the command below in a PowerShell window opened as administrator:'
        es='Ejecuta el comando de abajo en un PowerShell abierto como administrador:'
        fr='Lancez la commande ci-dessous dans un PowerShell ouvert en administrateur :'
        zh='请在以管理员身份打开的 PowerShell 中运行下面的命令：'
        hi='कृपया नीचे दिया गया कमांड व्यवस्थापक के रूप में खोले गए PowerShell में चलाएँ:'
        ar='شغّل الأمر أدناه في PowerShell مفتوح كمسؤول:'
        ru='Запустите команду ниже в PowerShell, открытом от имени администратора:'
    }
    'err_child_fail' = @{
        pt='O instalador foi interrompido por um erro acima. Envie esta imagem para o desenvolvedor.'
        en='The installer stopped because of the error above. Send this picture to the developer.'
        es='El instalador se detuvo por el error de arriba. Envia esta imagen al desarrollador.'
        fr='L''installateur s''est arrete a cause de l''erreur ci-dessus. Envoyez cette image au developpeur.'
        zh='安装程序因上面的错误而停止。请把这张图片发送给开发者。'
        hi='ऊपर दी गई त्रुटि के कारण इंस्टॉलर रुक गया। यह तस्वीर डेवलपर को भेजें।'
        ar='توقف المثبّت بسبب الخطأ أعلاه. أرسل هذه الصورة إلى المطور.'
        ru='Установщик остановился из-за ошибки выше. Отправьте это изображение разработчику.'
    }
    'err_child_never_started' = @{
        pt='A janela do instalador nao abriu depois do UAC. Isso costuma ser antivirus ou politica do Windows bloqueando o instalador.'
        en='The installer window did not open after the UAC prompt. This is usually an antivirus or a Windows policy blocking the installer.'
        es='La ventana del instalador no se abrio despues del UAC. Normalmente es un antivirus o una politica de Windows bloqueando el instalador.'
        fr='La fenetre de l''installateur ne s''est pas ouverte apres l''UAC. C''est souvent un antivirus ou une strategie Windows qui bloque l''installateur.'
        zh='UAC 之后安装程序窗口没有打开。通常是杀毒软件或 Windows 策略阻止了安装程序。'
        hi='UAC के बाद इंस्टॉलर विंडो नहीं खुली। यह आमतौर पर एंटीवायरस या Windows नीति के कारण होता है जो इंस्टॉलर को रोकती है।'
        ar='لم تُفتح نافذة المثبّت بعد UAC. السبب عادةً برنامج مكافحة فيروسات أو سياسة Windows تمنع المثبّت.'
        ru='Окно установщика не открылось после запроса UAC. Обычно это антивирус или политика Windows, блокирующая установщик.'
    }
    'err_elev_denied' = @{
        pt='O Windows recusou a permissao de administrador para esta conta. Se voce nao esta em uma conta de administrador deste PC, entre com uma e rode o instalador de novo. Se a janela do UAC nem chega a aparecer, a elevacao esta bloqueada por politica do Windows.'
        en='Windows refused administrator permission for this account. If you are not using an administrator account on this PC, sign in with one and run the installer again. If the UAC window never appears, elevation is blocked by a Windows policy.'
        es='Windows negó el permiso de administrador para esta cuenta. Si no estás usando una cuenta de administrador en este PC, inicia sesión con una y vuelve a ejecutar el instalador. Si la ventana de UAC no aparece, la elevación está bloqueada por una política de Windows.'
        fr='Windows a refusé la permission d''administrateur pour ce compte. Si vous n''utilisez pas un compte administrateur sur ce PC, connectez-vous avec un et relancez l''installateur. Si la fenêtre UAC n''apparaît pas, l''élévation est bloquée par une stratégie Windows.'
        zh='Windows 拒绝为此帐户授予管理员权限。如果此电脑上使用的不是管理员帐户，请用管理员帐户登录后重新运行安装程序。如果 UAC 窗口始终不出现，说明提升权限被 Windows 策略阻止。'
        hi='Windows ने इस खाते को व्यवस्थापक अनुमति देने से मना किया। यदि आप इस PC पर व्यवस्थापक खाते का उपयोग नहीं कर रहे हैं, तो उससे साइन इन करें और इंस्टॉलर फिर से चलाएँ। यदि UAC विंडो नहीं दिखती, तो Windows नीति ने अनुमति बढ़ाना रोक दिया है।'
        ar='رفض Windows منح صلاحيات المسؤول لهذا الحساب. إذا كنت لا تستخدم حساب مسؤول على هذا الجهاز، فسجّل الدخول بحساب مسؤول وشغّل المثبّت مرة أخرى. إذا لم تظهر نافذة UAC، فإن رفع الصلاحيات محظور بسياسة Windows.'
        ru='Windows отклонил предоставление прав администратора для этой учетной записи. Если вы не используете учетную запись администратора на этом компьютере, войдите под ней и запустите установщик снова. Если окно UAC не появляется, повышение прав блокируется политикой Windows.'
    }
    'err_elev_cancelled' = @{
        pt='Voce cancelou o pedido de administrador. Rode o instalador de novo e aceite a janela do UAC.'
        en='You cancelled the administrator request. Run the installer again and accept the UAC window.'
        es='Cancelaste la solicitud de administrador. Vuelve a ejecutar el instalador y acepta la ventana de UAC.'
        fr='Vous avez annulé la demande d''administrateur. Relancez l''installateur et acceptez la fenêtre UAC.'
        zh='你取消了管理员请求。请重新运行安装程序并接受 UAC 窗口。'
        hi='आपने व्यवस्थापक अनुरोध रद्द किया। इंस्टॉलर फिर से चलाएँ और UAC विंडो स्वीकार करें।'
        ar='لقد ألغيت طلب المسؤول. شغّل المثبّت مرة أخرى واقبل نافذة UAC.'
        ru='Вы отменили запрос прав администратора. Запустите установщик снова и подтвердите окно UAC.'
    }
    'report_ask' = @{
        pt='Deseja enviar o relatorio para o desenvolvedor para ajuda-lo a corrigir o problema? (S para sim, N para nao)'
        en='Do you want to send the report to the developer to help fix the problem? (Y for yes, N for no)'
        es='¿Desea enviar el informe al desarrollador para ayudar a corregir el problema? (S para sí, N para no)'
        fr='Voulez-vous envoyer le rapport au développeur pour aider à corriger le problème ? (O pour oui, N pour non)'
        zh='是否将报告发送给开发者以帮助修复问题？(S=发送，N=不发送)'
        hi='क्या आप समस्या ठीक करने में मदद के लिए रिपोर्ट डेवलपर को भेजना चाहते हैं? (S=हाँ, N=नहीं)'
        ar='هل تريد إرسال التقرير إلى المطور للمساعدة في إصلاح المشكلة؟ (S=نعم، N=لا)'
        ru='Отправить отчёт разработчику, чтобы помочь исправить проблему? (S=да, N=нет)'
    }
    'report_sent' = @{
        pt='Relatorio enviado ao desenvolvedor. Obrigado!'
        en='Report sent to the developer. Thank you!'
        es='Informe enviado al desarrollador. ¡Gracias!'
        fr='Rapport envoyé au développeur. Merci !'
        zh='报告已发送给开发者。谢谢！'
        hi='रिपोर्ट डेवलपर को भेज दी गई। धन्यवाद!'
        ar='تم إرسال التقرير إلى المطور. شكرًا!'
        ru='Отчёт отправлен разработчику. Спасибо!'
    }
    'report_not_sent' = @{
        pt='Ok, relatorio nao enviado.'
        en='OK, the report was not sent.'
        es='De acuerdo, el informe no se envió.'
        fr='D''accord, le rapport n''a pas été envoyé.'
        zh='好的，报告未发送。'
        hi='ठीक है, रिपोर्ट नहीं भेजी गई।'
        ar='حسنًا، لم يتم إرسال التقرير.'
        ru='Хорошо, отчёт не отправлен.'
    }
    'report_send_fail' = @{
        pt='Nao foi possivel enviar o relatorio automaticamente.'
        en='Could not send the report automatically.'
        es='No se pudo enviar el informe automáticamente.'
        fr='Impossible d''envoyer le rapport automatiquement.'
        zh='无法自动发送报告。'
        hi='रिपोर्ट स्वचालित रूप से नहीं भेजी जा सकी।'
        ar='تعذّر إرسال التقرير تلقائيًا.'
        ru='Не удалось отправить отчёт автоматически.'
    }
}
function L {
    param([string]$Key)
    $entry = $Script:Msg[$Key]
    if ($entry) {
        if ($entry[$Script:MbuLang]) {
            return $entry[$Script:MbuLang]
        }
        if ($entry['en']) {
            return $entry['en']
        }
    }
    return $Key
}

function Get-MbuTempDir {
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
            return $c.TrimEnd('\')
        } catch { }
    }
    try {
        return ([IO.Path]::GetTempPath()).TrimEnd('\')
    } catch {
        return $env:TEMP
    }
}
$tempDir = Get-MbuTempDir
$logPath = Join-Path $tempDir 'mbu-bootstrap.log'
$runId = [guid]::NewGuid().ToString('N').Substring(0, 8)
function Add-MbuLog {
    param([string]$Line)
    try {
        $stamp = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
        [IO.File]::AppendAllText($logPath, ($stamp + ' run=' + $runId + ' ' + $Line + [Environment]::NewLine))
    } catch { }
}
Add-MbuLog ("stage=start temp=$tempDir env=$env:TEMP tmp=$env:TMP")

$menu = Join-Path $tempDir 'mbu-menu.ps1'
$downloaded = $false
$lastDownloadErr = $null
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "$base/menu.ps1" -OutFile $menu -TimeoutSec 30
        $downloaded = $true
        try {
            Add-MbuLog ("stage=download ok bytes=" + (New-Object System.IO.FileInfo -ArgumentList $menu).Length)
        } catch { }
        break
    } catch {
        $lastDownloadErr = $_.Exception.Message
        $code = $null
        try {
            $code = [int]$_.Exception.Response.StatusCode
        } catch { }
        $transient = ($code -in @(408, 429, 502, 503, 504)) -or
                     ($lastDownloadErr -match '50[234]|429|408|timed out|Unable to connect|The connection was closed|The remote name could not be resolved')
        if (-not $transient -or $attempt -ge 3) {
            break
        }
        Start-Sleep -Seconds (3 * $attempt)
    }
}
if (-not $downloaded) {
    Write-Host ''
    if ($lastDownloadErr) {
        Write-Host ("$($lastDownloadErr)") -ForegroundColor Red
    }
    Write-Host ("[temp] used=$tempDir env=$env:TEMP tmp=$env:TMP") -ForegroundColor DarkGray
    Write-Host (L 'err_menu_download') -ForegroundColor Red
    Read-Host (L 'press_enter_close')
    exit 1
}
$menuHash = '461f1f75f6b924d61d5844d027992f26c4415c6f1d4e6bb5c354de6afdaebe85'
$menuBytes = [IO.File]::ReadAllBytes($menu)
$clean = New-Object System.Collections.Generic.List[byte]
foreach ($b in $menuBytes) {
    if ($b -ne 13) {
        $clean.Add([byte]$b)
    }
}
$menuBytes = $clean.ToArray()
$tmpHash = [System.Security.Cryptography.SHA256]::Create()
$menuActual = [BitConverter]::ToString($tmpHash.ComputeHash($menuBytes)).Replace('-','').ToLowerInvariant()
if ($menuActual -ne $menuHash) {
    Add-MbuLog ("stage=hash-fail expected=$menuHash actual=$menuActual")
    Write-Host ''
    Write-Host (L 'err_menu_hash') -ForegroundColor Red
    Write-Host ((L 'err_expected') -replace '\{0\}', $menuHash)
    Write-Host ((L 'err_received') -replace '\{0\}', $menuActual)
    Write-Host (L 'err_stale_1') -ForegroundColor Yellow
    Write-Host (L 'err_stale_2')
    Read-Host (L 'press_enter_close')
    exit 1
}

Add-MbuLog 'stage=hash ok'

$menuText = [IO.File]::ReadAllText($menu)
$versionLabel = 'unknown'
try {
    if ($menuText -match "Script:Version = '([^']+)'") {
        $versionLabel = $Matches[1]
    }
} catch { }
$reportEndpoint = if ($env:MBU_REPORT_URL) {
    $env:MBU_REPORT_URL.TrimEnd('/')
} else {
    'https://mbu-error-worker.xgobg2020.workers.dev/report'
}
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $psExe)) {
    $psExe = 'powershell.exe'
}
function Get-MbuWin32Text {
    param([int]$Code)
    try {
        return [string](New-Object System.ComponentModel.Win32Exception($Code)).Message
    } catch {
        return ''
    }
}

function Get-MbuElevationFailureKind {
    param([string]$Message)
    if (-not $Message) {
        return 'unknown'
    }
    $cancelled = Get-MbuWin32Text 1223
    if ($cancelled -and $Message.Contains($cancelled)) {
        return 'cancelled'
    }
    $denied = Get-MbuWin32Text 5
    if ($denied -and $Message.Contains($denied)) {
        return 'denied'
    }
    return 'unknown'
}

function Get-MbuInAdministrators {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $target = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
        foreach ($group in $identity.Groups) {
            try {
                if ($group.Value -eq $target.Value) {
                    return $true
                }
            } catch { }
        }
    } catch { }
    return $false
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$inAdminGroup = Get-MbuInAdministrators
Add-MbuLog ("stage=admin isAdmin=$isAdmin inAdminGroup=$inAdminGroup version=$versionLabel menu=$menu")

function Get-MbuLogTail {
    try {
        $lines = [IO.File]::ReadAllLines($logPath)
        if ($lines.Count -gt 20) {
            $lines = $lines[($lines.Count - 20)..($lines.Count - 1)]
        }
        return ($lines -join [Environment]::NewLine)
    } catch {
        return ''
    }
}

function Send-MbuBootstrapReport {
    param([string]$Message)
    try {
        $answer = Read-Host ("  " + (L 'report_ask'))
        if (([string]$answer) -notmatch '^[syo]') {
            Write-Host ("  " + (L 'report_not_sent')) -ForegroundColor DarkGray
            return
        }
        $os = 'Windows (unknown)'
        try {
            $c = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $os = "$($c.Caption) build $($c.BuildNumber)"
        } catch { }
        $diag = @(
            'stage=bootstrap'
            ("version=$versionLabel")
            ("admin=$isAdmin")
            ("temp=$tempDir")
            ("error=" + $Message)
            (Get-MbuLogTail)
        ) -join [Environment]::NewLine
        $body = @{
            v       = $versionLabel
            os      = $os
            lang    = $Script:MbuLang
            trigger = 'launch_error'
            reason  = $Message
            report  = $diag
        } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri $reportEndpoint -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 10 | Out-Null
        Write-Host ("  " + (L 'report_sent')) -ForegroundColor Green
    } catch {
        Write-Host ("  " + (L 'report_send_fail')) -ForegroundColor Yellow
    }
}

function Show-MbuLaunchFailure {
    param([string]$Message, [string]$Kind)
    if (-not $Kind) {
        $Kind = 'unknown'
    }
    Add-MbuLog ("stage=launch-fail kind=" + $Kind + " inAdminGroup=" + $inAdminGroup + " reason=" + $Message)
    Write-Host ''
    Write-Host (L 'err_launch_title') -ForegroundColor Red
    if ($Kind -eq 'denied') {
        Write-Host (L 'err_elev_denied') -ForegroundColor Yellow
    } elseif ($Kind -eq 'cancelled') {
        Write-Host (L 'err_elev_cancelled') -ForegroundColor Yellow
    } elseif ($Message) {
        Write-Host ("  " + $Message) -ForegroundColor Yellow
    }
    Write-Host (L 'err_launch_hint') -ForegroundColor Yellow
    Write-Host ("  irm $base/menu.ps1 | iex") -ForegroundColor Cyan
    Write-Host ("  " + $logPath) -ForegroundColor DarkGray
    Send-MbuBootstrapReport -Message ($Kind + ': ' + $Message)
    Read-Host (L 'press_enter_close')
    exit 1
}

function Set-MbuConsoleWidth {
    $target = 132
    try {
        $rawUi = $Host.UI.RawUI
        if ($rawUi) {
            $buf = $rawUi.BufferSize
            if ($buf.Width -lt $target) {
                $rawUi.BufferSize = New-Object System.Management.Automation.Host.Size($target, $buf.Height)
            }
            $win = $rawUi.WindowSize
            if ($win.Width -ne $target) {
                $rawUi.WindowSize = New-Object System.Management.Automation.Host.Size($target, $win.Height)
            }
        }
    } catch { }
}

function Set-MbuConsoleLook {
    $before = 'unknown'
    try {
        $before = [string]$Host.UI.RawUI.BackgroundColor
    } catch { }
    $painted = $false
    try {
        $rawUi = $Host.UI.RawUI
        if ($rawUi) {
            $rawUi.WindowTitle = 'Minecraft Bedrock Free'
        }
    } catch { }
    try {
        $rawUi = $Host.UI.RawUI
        if ($rawUi) {
            $rawUi.BackgroundColor = 'Black'
            $painted = $true
        }
    } catch { }
    Set-MbuConsoleWidth
    try {
        Clear-Host
    } catch { }
    if ($painted) {
        Add-MbuLog ('stage=console-black from=' + $before)
    } else {
        Add-MbuLog ('stage=console-kept from=' + $before)
    }
}

if ($isAdmin) {
    Add-MbuLog 'stage=launch-in-place'
    Set-MbuConsoleLook
    try {
        iex $menuText
    } catch {
        Show-MbuLaunchFailure -Message $_.Exception.Message
    }
} else {
    Write-Host (L 'uac_request')
    $menuLit = "'" + $menu.Replace("'", "''") + "'"
    $logLit = "'" + $logPath.Replace("'", "''") + "'"
    $hintLit = "'" + (L 'err_child_fail').Replace("'", "''") + "'"
    $enterLit = "'" + (L 'press_enter_close').Replace("'", "''") + "'"
    $childLines = @(
        ('$host.UI.RawUI.WindowTitle = ''Minecraft Bedrock Free''')
        ('try { [IO.File]::AppendAllText(' + $logLit + ', ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " run=' + $runId + ' stage=child-console from=" + [string]$host.UI.RawUI.BackgroundColor + [Environment]::NewLine)) } catch { }')
        ('try { $host.UI.RawUI.BackgroundColor = ''Black'' } catch { }')
        ('try {')
        ('  $target = 132')
        ('  $b = $host.UI.RawUI.BufferSize')
        ('  if ($b.Width -lt $target) { $host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size($target, $b.Height) }')
        ('  $w = $host.UI.RawUI.WindowSize')
        ('  if ($w.Width -ne $target) { $host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size($target, $w.Height) }')
        ('} catch { }')
        ('try { Clear-Host } catch { }')
        ('$p = ' + $menuLit)
        ('[IO.File]::AppendAllText(' + $logLit + ', ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " run=' + $runId + ' stage=child-started pid=" + $PID + [Environment]::NewLine))')
        ('try {')
        ('    iex ([IO.File]::ReadAllText($p))')
        ('} catch {')
        ('    [IO.File]::AppendAllText(' + $logLit + ', ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " run=' + $runId + ' stage=child-fail reason=" + $_.Exception.Message + [Environment]::NewLine))')
        ('    Write-Host ""')
        ('    Write-Host ("  " + $_.Exception.Message) -ForegroundColor Red')
        ('    Write-Host ("  " + ' + $hintLit + ') -ForegroundColor Yellow')
        ('    Read-Host ("  " + ' + $enterLit + ')')
        ('}')
    )
    $childText = $childLines -join [Environment]::NewLine
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childText))
    $cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
    if (-not (Test-Path -LiteralPath $cmdExe)) {
        $cmdExe = 'cmd.exe'
    }
    $psHost = $psExe
    if ($psHost -match '\s') {
        $psHost = 'powershell.exe'
    }
    Add-MbuLog 'stage=launch-elevate host=cmd'
    try {
        Start-Process -FilePath $cmdExe -Verb RunAs -ArgumentList ('/d /c ' + $psHost + ' -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + $encoded)
        $started = $null
        $attempt = 0
        while ($attempt -lt 12) {
            $attempt = $attempt + 1
            Start-Sleep -Milliseconds 500
            $logText = ''
            try {
                $logText = [IO.File]::ReadAllText($logPath)
            } catch { }
            if (-not $logText) {
                break
            }
            if ($logText -match ('run=' + $runId + ' stage=child-started')) {
                $started = $true
                break
            }
            $started = $false
        }
        if ($started -eq $true) {
            Add-MbuLog 'stage=launch-ok'
            exit 0
        }
        if ($started -eq $null) {
            exit 0
        }
        Show-MbuLaunchFailure -Message (L 'err_child_never_started') -Kind 'child-never-started'
    } catch {
        $elevationError = [string]$_.Exception.Message
        Show-MbuLaunchFailure -Message $elevationError -Kind (Get-MbuElevationFailureKind $elevationError)
    }
}
