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

$menu = Join-Path $tempDir 'mbu-menu.ps1'
$downloaded = $false
$lastDownloadErr = $null
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "$base/menu.ps1" -OutFile $menu -TimeoutSec 30
        $downloaded = $true
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
$menuHash = '8ea7161e675229c9a4207999b99929e3f953b8d5ad6c17a59fc5222e21c2dfda'
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
    Write-Host ''
    Write-Host (L 'err_menu_hash') -ForegroundColor Red
    Write-Host ((L 'err_expected') -replace '\{0\}', $menuHash)
    Write-Host ((L 'err_received') -replace '\{0\}', $menuActual)
    Write-Host (L 'err_stale_1') -ForegroundColor Yellow
    Write-Host (L 'err_stale_2')
    Read-Host (L 'press_enter_close')
    exit 1
}

$launcher = Join-Path $tempDir 'mbu-launch.bat'
[System.IO.File]::WriteAllLines($launcher, @(
    '@echo off',
    'title Minecraft Bedrock Free',
    'color 07',
    'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mbu-menu.ps1"',
    'del "%~f0" >nul 2>&1'
), [System.Text.Encoding]::ASCII)

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

try {
    if ($isAdmin) {
        Start-Process -FilePath $launcher
    } else {
        Write-Host (L 'uac_request')
        Start-Process -FilePath $launcher -Verb RunAs
    }
} finally {
    exit
}
