
$ErrorActionPreference = 'Stop'

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
    'content_not_found' = @{
        pt='Content do Minecraft nao encontrado.'
        en='Minecraft Content folder not found.'
        es='No se encontro la carpeta Content de Minecraft.'
        fr='Dossier Content de Minecraft introuvable.'
        zh='未找到 Minecraft Content 文件夹。'
        hi='Minecraft Content फ़ोल्डर नहीं मिला।'
        ar='لم يتم العثور على مجلد Content الخاص بـ Minecraft.'
        ru='Папка Content Minecraft не найдена.'
    }
    'closing_mc' = @{
        pt='Fechando Minecraft...'
        en='Closing Minecraft...'
        es='Cerrando Minecraft...'
        fr='Fermeture de Minecraft...'
        zh='正在关闭 Minecraft...'
        hi='Minecraft बंद किया जा रहा है...'
        ar='جارٍ إغلاق Minecraft...'
        ru='Закрытие Minecraft...'
    }
    'restored_ok' = @{
        pt='winmm original restaurado.'
        en='Original winmm restored.'
        es='winmm original restaurado.'
        fr='winmm original restauré.'
        zh='已还原原始 winmm。'
        hi='मूल winmm पुनर्स्थापित हो गया।'
        ar='تمت استعادة winmm الأصلي.'
        ru='Оригинальный winmm восстановлен.'
    }
    'removed_ok' = @{
        pt='winmm.dll removido (o jogo usara o do sistema).'
        en='winmm.dll removed (the game will use the system one).'
        es='winmm.dll eliminado (el juego usara el del sistema).'
        fr='winmm.dll supprimé (le jeu utilisera celui du système).'
        zh='已移除 winmm.dll (游戏将使用系统自带的)。'
        hi='winmm.dll हटा दिया गया (गेम सिस्टम वाला उपयोग करेगा)।'
        ar='تمت إزالة winmm.dll (ستستخدم اللعبة ملف النظام).'
        ru='winmm.dll удалён (игра будет использовать системный).'
    }
    'unlock_removed' = @{
        pt='Unlock removido.'
        en='Unlock removed.'
        es='Desbloqueo eliminado.'
        fr='Déverrouillage supprimé.'
        zh='解锁已移除。'
        hi='अनलॉक हटा दिया गया।'
        ar='تمت إزالة فتح اللعبة.'
        ru='Разблокировка удалена.'
    }
    'defender_excl_removed' = @{
        pt='Exclusao do Defender removida: {0}'
        en='Defender exclusion removed: {0}'
        es='Exclusion de Defender eliminada: {0}'
        fr='Exclusion Defender supprimée : {0}'
        zh='已移除 Defender 排除项：{0}'
        hi='Defender बहिष्करण हटा दिया गया: {0}'
        ar='تمت إزالة استثناء Defender: {0}'
        ru='Исключение Защитника Windows удалено: {0}'
    }
    'defender_proc_removed' = @{
        pt='Exclusao de processo removida: {0}'
        en='Process exclusion removed: {0}'
        es='Exclusion de proceso eliminada: {0}'
        fr='Exclusion de processus supprimée : {0}'
        zh='已移除进程排除项：{0}'
        hi='प्रक्रिया बहिष्करण हटा दिया गया: {0}'
        ar='تمت إزالة استثناء العملية: {0}'
        ru='Исключение процесса удалено: {0}'
    }
    'defender_none' = @{
        pt='Nenhuma exclusao do Defender do unlocker encontrada (nada a limpar).'
        en='No Defender exclusions from the unlocker were found (nothing to clean up).'
        es='No se encontro ninguna exclusion de Defender del unlocker (nada que limpiar).'
        fr='Aucune exclusion Defender du déverrouilleur trouvée (rien à nettoyer).'
        zh='未找到解锁器的 Defender 排除项（无需清理）。'
        hi='अनलॉकर से कोई Defender बहिष्करण नहीं मिला (साफ करने के लिए कुछ नहीं)।'
        ar='لم يتم العثور على استثناءات Defender من الفاتح (لا شيء لتنظيفه).'
        ru='Исключения Защитника от анлокера не найдены (нечего очищать).'
    }
    'defender_fail' = @{
        pt='Nao foi possivel listar/remover exclusoes do Defender (rode como administrador).'
        en='Could not list/remove Defender exclusions (run as administrator).'
        es='No se pudo listar/eliminar las exclusiones de Defender (ejecuta como administrador).'
        fr='Impossible de lister/supprimer les exclusions Defender (exécutez en tant qu''administrateur).'
        zh='无法列出/移除 Defender 排除项（请以管理员身份运行）。'
        hi='Defender बहिष्करण सूचीबद्ध/हटाए नहीं जा सके (व्यवस्थापक के रूप में चलाएँ)।'
        ar='تعذّر سرد/إزالة استثناءات Defender (شغّل كمسؤول).'
        ru='Не удалось вывести/удалить исключения Защитника (запустите от имени администратора).'
    }
    'err_remove_failed' = @{
        pt='Nao foi possivel remover o winmm.dll (arquivo em uso ou acesso negado). Feche o Minecraft e rode como administrador.'
        en='Could not remove winmm.dll (file in use or access denied). Close Minecraft and run as administrator.'
        es='No se pudo eliminar winmm.dll (archivo en uso o acceso denegado). Cierra Minecraft y ejecuta como administrador.'
        fr='Impossible de supprimer winmm.dll (fichier utilise ou acces refuse). Fermez Minecraft et executez en tant qu''administrateur.'
        zh='无法移除 winmm.dll（文件被占用或访问被拒绝）。请关闭 Minecraft 并以管理员身份运行。'
        hi='winmm.dll हटाया नहीं जा सका (फ़ाइल उपयोग में है या पहुँच अस्वीकृत)। Minecraft बंद करें और व्यवस्थापक के रूप में चलाएँ।'
        ar='تعذّرت إزالة winmm.dll (الملف قيد الاستخدام أو تم رفض الوصول). أغلق Minecraft وشغّل كمسؤول.'
        ru='Не удалось удалить winmm.dll (файл используется или отказано в доступе). Закройте Minecraft и запустите от имени администратора.'
    }
    'cache_removed' = @{
        pt='Copia local do unlocker apagada.'
        en='Local unlocker copy deleted.'
        es='Copia local del desbloqueo eliminada.'
        fr='Copie locale du deverrouilleur supprimee.'
        zh='已删除解锁器的本地副本。'
        hi='अनलॉकर की स्थानीय प्रति हटा दी गई।'
        ar='تم حذف النسخة المحلية للفاتح.'
        ru='Локальная копия анлокера удалена.'
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

function Find-MinecraftContent {
    $candidates = @()
    try {
        $proc = Get-Process Minecraft.Windows -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($proc -and $proc.Path) {
            $candidates += (Split-Path $proc.Path -Parent)
        }
    } catch { }
    try {
        $appx = Get-AppxPackage -Name 'Microsoft.MinecraftUWP*' -AllUsers -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $appx) {
            $appx = Get-AppxPackage -Name 'Microsoft.MinecraftUWP*' -ErrorAction SilentlyContinue |
                Select-Object -First 1
        }
        if ($appx -and $appx.InstallLocation) {
            $candidates += $appx.InstallLocation
            $candidates += (Join-Path $appx.InstallLocation 'Content')
        }
    } catch { }
    $candidates += 'C:\XboxGames\Minecraft for Windows\Content'
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c) -and (Test-Path (Join-Path $c 'Minecraft.Windows.exe'))) {
            return $c
        }
    }
    throw (L 'content_not_found')
}

function Remove-MbuDefenderExclusions {
    $paths = @()
    foreach ($p in @($args)) {
        if ($p) {
            $paths += $p
        }
    }
    try {
        $pref = Get-MpPreference -ErrorAction Stop
        $targets = @()
        foreach ($p in @($pref.ExclusionPath)) {
            if (-not $p) {
                continue
            }
            $match = ($paths -contains $p) -or ($p -match '\\mbu(-cache)?$') -or
                     ($p -like '*XboxGames\Minecraft*') -or ($p -like '*MinecraftUWP*')
            if ($match) {
                $targets += $p
            }
        }
        foreach ($t in $targets) {
            try {
                Remove-MpPreference -ExclusionPath $t -ErrorAction Stop
                Write-Output ((L 'defender_excl_removed') -replace '\{0\}', $t)
            } catch { }
        }
        $procTargets = @()
        foreach ($p in @($pref.ExclusionProcess)) {
            if ($p -and ($p -match 'Minecraft\.Windows\.exe')) {
                $procTargets += $p
            }
        }
        foreach ($t in $procTargets) {
            try {
                Remove-MpPreference -ExclusionProcess $t -ErrorAction Stop
                Write-Output ((L 'defender_proc_removed') -replace '\{0\}', $t)
            } catch { }
        }
        if (($targets.Count -eq 0) -and ($procTargets.Count -eq 0)) {
            Write-Output (L 'defender_none')
        }
    } catch {
        Write-Output (L 'defender_fail')
    }
}

$content = Find-MinecraftContent
$p = Get-Process Minecraft.Windows -ErrorAction SilentlyContinue
if ($p) {
    Write-Output (L 'closing_mc')
    $p | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Initialize-AclForWrite {
    param([string]$Path)
    $adm = '*S-1-5-32-544'
    $sys = '*S-1-5-18'
    $user = $null
    try {
        $user = '*' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    } catch { }
    try {
        & takeown.exe /f $Path 2>&1 | Out-Null
    } catch { }
    try {
        & icacls.exe $Path /grant ($adm + ':(OI)(CI)F') 2>&1 | Out-Null
    } catch { }
    if ($user) {
        try {
            & icacls.exe $Path /grant ($user + ':(OI)(CI)F') 2>&1 | Out-Null
        } catch { }
        try {
            & icacls.exe $Path /grant ($sys + ':(OI)(CI)F') 2>&1 | Out-Null
        } catch { }
    }
    try {
        $acl = Get-Acl -LiteralPath $Path
        $changed = $false
        foreach ($ace in @($acl.Access)) {
            if ($ace.AccessControlType -eq [Security.AccessControl.AccessControlType]::Deny -and -not $ace.IsInherited) {
                $acl.RemoveAccessRuleSpecific($ace) | Out-Null
                $changed = $true
            }
        }
        if ($changed) {
            Set-Acl -LiteralPath $Path -AclObject $acl
        }
    } catch { }
    try {
        & icacls.exe $Path /grant ($adm + ':(OI)(CI)F') 2>&1 | Out-Null
    } catch { }
}

$winmm = Join-Path $content 'winmm.dll'
$orig = Join-Path $content 'winmm.dll.orig'

$removed = $false
for ($attempt = 1; $attempt -le 3; $attempt++) {
    Initialize-AclForWrite $content
    if (Test-Path $winmm) {
        Initialize-AclForWrite $winmm
        try {
            Set-ItemProperty -LiteralPath $winmm -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        } catch { }
    }
    Remove-Item $winmm -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $winmm)) {
        $removed = $true
        break
    }
    Start-Sleep -Seconds 2
}
if (-not $removed) {
    Write-Output (L 'err_remove_failed')
    exit 1
}

if (Test-Path $orig) {
    try {
        Move-Item $orig $winmm -Force -ErrorAction Stop
        if (-not (Test-Path $winmm)) {
            throw 'orig nao voltou'
        }
        Write-Output (L 'restored_ok')
    } catch {
        Write-Output (L 'err_remove_failed')
        exit 1
    }
} else {
    Write-Output (L 'removed_ok')
}
Write-Output (L 'unlock_removed')

try {
    foreach ($s in @(Get-ChildItem -LiteralPath $content -Filter 'winmm.dll.mbu-prev-*' -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $s.FullName -Force -ErrorAction SilentlyContinue
    }
} catch { }

Remove-MbuDefenderExclusions $content (Join-Path $env:TEMP 'mbu') (Join-Path $env:LOCALAPPDATA 'mbu-cache')

$traces = 0
foreach ($t in @((Join-Path $env:LOCALAPPDATA 'mbu-cache'), (Join-Path $env:TEMP 'mbu'))) {
    if (Test-Path $t) {
        try {
            Remove-Item -Recurse -Force $t -ErrorAction SilentlyContinue
        } catch { }
        if (-not (Test-Path $t)) {
            $traces++
        }
    }
}
if ($traces -gt 0) {
    Write-Output (L 'cache_removed')
}
