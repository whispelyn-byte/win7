# 11. "Internet Explorer" = Firefox ESR 115.9.1 + BeautyFox + native controls + IE icon/name.

function Get-FirefoxLangCode {
    $lang = Get-UiLanguage
    if ($lang -like 'en-*') { return 'en-US' }
    if ($lang -in @('zh-CN', 'zh-TW', 'pt-BR', 'pt-PT', 'es-ES', 'es-MX', 'es-AR', 'es-CL', 'sv-SE', 'nb-NO', 'nn-NO', 'ga-IE', 'hy-AM', 'ne-NP', 'pa-IN', 'gu-IN', 'hi-IN', 'bn-IN', 'en-GB', 'en-CA')) { return $lang }
    return $lang.Split('-')[0]
}

function Get-FirefoxProfileDir {
    $cfg = Get-Cfg 'firefoxProfileDir' ''
    if ($cfg) { return $cfg }
    $ini = Join-Path $env:APPDATA 'Mozilla\Firefox\profiles.ini'
    if (-not (Test-Path $ini)) { return $null }
    $text = Get-Content $ini -Raw
    # Prefer the default profile of an [Install...] section that points to an ESR profile
    $defaults = [regex]::Matches($text, '(?ms)^\[Install[^\]]+\]\s*\r?\nDefault=([^\r\n]+)') | ForEach-Object { $_.Groups[1].Value }
    $cands = @($defaults | Where-Object { $_ -like '*default-esr*' })
    if ($cands.Count -eq 0) { $cands = @($defaults) }
    $dirs = foreach ($rel in $cands) {
        $p = if ([System.IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path (Join-Path $env:APPDATA 'Mozilla\Firefox') ($rel -replace '/', '\') }
        if (Test-Path $p) { Get-Item $p }
    }
    $best = $dirs | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($best) { return $best.FullName }
    return $null
}

function Get-ResourceHacker {
    $exe = Find-Asset -Pattern @('ResourceHacker.exe')
    if ($exe) { return $exe }
    $dir = Join-Path $W7.Work 'resourcehacker'
    $exe = Join-Path $dir 'ResourceHacker.exe'
    if (Test-Path $exe) { return $exe }
    $zip = Invoke-Download -Url 'https://www.angusj.com/resourcehacker/resource_hacker.zip' -OutFile (Join-Path $W7.Work 'resource_hacker.zip')
    Expand-Zip $zip $dir
    return $exe
}

function Invoke-ResourceHacker {
    param([Parameter(Mandatory)] [string] $Exe, [Parameter(Mandatory)] [string[]] $Arguments)
    $log = Join-Path $W7.Work 'rh.log'
    $all = $Arguments + @('-log', "`"$log`"")
    $p = Start-Process -FilePath $Exe -ArgumentList $all -Wait -PassThru -WindowStyle Hidden
    if ($p.ExitCode -ne 0) {
        $msg = if (Test-Path $log) { Get-Content $log -Raw } else { '' }
        throw "Resource Hacker 실패 ($($p.ExitCode)): $msg"
    }
}

Register-Step -Id 'firefox-ie' -Order 70 -Title 'Firefox ESR → Internet Explorer 꾸미기' -Kind Auto -Run {
    $ver = Get-Cfg 'firefoxVersion' '115.9.1esr'
    $installDir = Get-Cfg 'firefoxInstallDir' 'C:\Program Files\Internet Explorer (x32)'
    $ffExe = Join-Path $installDir 'firefox.exe'

    # 1) Install Firefox ESR (silent, custom dir, no maintenance service, desktop shortcut only)
    if (-not (Test-Path $ffExe)) {
        $lc = Get-FirefoxLangCode
        $setup = Find-Asset -Pattern @("Firefox Setup $ver*.exe")
        if (-not $setup) {
            $url = "https://ftp.mozilla.org/pub/firefox/releases/$ver/win64/$lc/Firefox%20Setup%20$ver.exe"
            $setup = Invoke-Download -Url $url -OutFile (Join-Path $W7.Work "Firefox Setup $ver.exe")
        }
        $ini = Join-Path $W7.Work 'firefox-install.ini'
        if (-not (Test-DryRun)) {
            @(
                '[Install]',
                "InstallDirectoryPath=$installDir",
                'TaskbarShortcut=false',
                'DesktopShortcut=true',
                'StartMenuShortcuts=false',
                'MaintenanceService=false',
                'PrivateBrowsingShortcut=false'
            ) | Set-Content -Path $ini -Encoding ASCII
        }
        Start-Program $setup @("/INI=`"$ini`"") | Out-Null
    } else { Write-Log "Firefox 이미 설치됨: $ffExe" 'OK' }

    # 2) Disable automatic updates (guide: important!) via enterprise policy
    $policyDir = Join-Path $installDir 'distribution'
    Invoke-Action 'Firefox 자동 업데이트 끄기 (policies.json)' {
        if (-not (Test-Path $policyDir)) { New-Item -ItemType Directory -Path $policyDir -Force | Out-Null }
        $tmp = Join-Path $W7.Work 'policies.json'
        '{ "policies": { "DisableAppUpdate": true, "AppAutoUpdate": false, "BackgroundAppUpdate": false } }' | Set-Content -Path $tmp -Encoding UTF8
        Copy-FileSafe -Source $tmp -Destination (Join-Path $policyDir 'policies.json')
    }

    # 3) Make sure a profile exists (run once headless)
    $ffProfile = Get-FirefoxProfileDir
    if (-not $ffProfile -and -not (Test-DryRun)) {
        Write-Log 'Firefox 프로필 생성을 위해 한 번 실행합니다...'
        $p = Start-Process $ffExe -ArgumentList '-headless' -PassThru
        Start-Sleep -Seconds 15
        Get-Process firefox -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $ffExe } | Stop-Process -Force
        Start-Sleep -Seconds 2
        $ffProfile = Get-FirefoxProfileDir
    }
    if (-not $ffProfile) {
        if (-not (Test-DryRun)) { throw 'Firefox 프로필 폴더를 못 찾았어요. config.json의 firefoxProfileDir을 지정하세요 (about:support > 프로필 폴더).' }
        $ffProfile = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles\xxxx.default-esr'
    }
    Write-Log "Firefox 프로필: $ffProfile"
    Invoke-Action 'Firefox 종료' { Get-Process firefox -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep -Seconds 2 }

    # 4) BeautyFox: config.js + defaults -> install dir, chrome -> profile
    $bf = Find-Asset -Pattern @('BeautyFox*') -Directory
    if (-not $bf) {
        $zip = Join-Path $W7.Work 'BeautyFox.zip'
        try { Invoke-Download -Url 'https://github.com/dominichayesferen/BeautyFox/archive/refs/heads/main.zip' -OutFile $zip | Out-Null }
        catch { Invoke-Download -Url 'https://github.com/dominichayesferen/BeautyFox/archive/refs/heads/master.zip' -OutFile $zip | Out-Null }
        $bf = Join-Path $W7.Work 'BeautyFox'
        Expand-Zip $zip $bf
    }
    if (-not (Test-DryRun)) {
        $cfgJs = Get-ChildItem $bf -Recurse -Filter 'config.js' -File | Select-Object -First 1
        $defaults = Get-ChildItem $bf -Recurse -Directory -Filter 'defaults' | Select-Object -First 1
        $chrome = Get-ChildItem $bf -Recurse -Directory -Filter 'chrome' | Select-Object -First 1
        if (-not $cfgJs -or -not $defaults -or -not $chrome) { throw "BeautyFox 파일 구조를 못 찾았어요: $bf" }
        Copy-FileSafe -Source $cfgJs.FullName -Destination (Join-Path $installDir 'config.js')
        Copy-DirSafe -Source $defaults.FullName -Destination (Join-Path $installDir 'defaults')
        Copy-DirSafe -Source $chrome.FullName -Destination (Join-Path $ffProfile 'chrome')
    } else { Write-Log "(dry-run) BeautyFox 복사 ($bf)" 'DRY' }

    # 5) Title bar on (required by native controls) + clear startup cache
    Invoke-Action 'user.js: 제목 표시줄 켜기' {
        $uj = Join-Path $ffProfile 'user.js'
        $line = 'user_pref("browser.tabs.inTitlebar", 0);'
        if (-not (Test-Path $uj) -or -not (Select-String -Path $uj -SimpleMatch 'browser.tabs.inTitlebar' -Quiet)) {
            if (Test-Path $uj) {
                $bak = New-BackupPath $uj
                Copy-Item -LiteralPath $uj -Destination $bak -Force
                Add-ManifestEntry @{ kind = 'file'; path = $uj; backup = $bak }
            } else { Add-ManifestEntry @{ kind = 'newfile'; path = $uj } }
            Add-Content -Path $uj -Value $line -Encoding UTF8
        }
    }
    Invoke-Action '시작 캐시 삭제' {
        $local = $ffProfile -replace [regex]::Escape((Join-Path $env:APPDATA 'Mozilla')), (Join-Path $env:LOCALAPPDATA 'Mozilla')
        foreach ($p in @((Join-Path $ffProfile 'startupCache'), (Join-Path $local 'startupCache'))) {
            if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    # 6) firefox-native-controls xul.dll
    $xul = Find-Asset -Pattern @('xul.dll') -Under 'firefox-native-controls'
    if (-not $xul) {
        try {
            $url = Get-GitHubReleaseAsset -Repo 'ephemeralViolette/firefox-native-controls' -NameLike '*xul*'
        } catch {
            $url = Get-GitHubReleaseAsset -Repo 'ephemeralViolette/firefox-native-controls' -NameLike '*.zip'
        }
        $name = Split-Path $url -Leaf
        $dl = Invoke-Download -Url $url -OutFile (Join-Path $W7.Work "fnc\$name")
        if ($name -like '*.zip') {
            $x = Join-Path $W7.Work 'fnc\x'
            Expand-Zip $dl $x
            if (-not (Test-DryRun)) { $xul = (Get-ChildItem $x -Recurse -Filter 'xul.dll' | Select-Object -First 1).FullName }
        } else { $xul = $dl }
    }
    if ($xul) { Copy-FileSafe -Source $xul -Destination (Join-Path $installDir 'xul.dll') }
    else { Write-Log 'xul.dll을 못 찾았어요. assets\firefox-native-controls\xul.dll 에 넣고 -Redo firefox-ie 하세요.' 'WARN' }

    # 7) IE icon + "Internet Explorer" name with Resource Hacker
    $ieExe = Get-Win7File 'Program Files\Internet Explorer\iexplore.exe'
    $ieA = Find-Asset -Pattern @('iexplore.exe', 'iexplorer.exe')
    if ($ieA) { $ieExe = $ieA }
    try {
        $rh = Get-ResourceHacker
        $rw = Join-Path $W7.Work 'rh'
        if (-not (Test-DryRun)) {
            if (Test-Path $rw) { Remove-Item $rw -Recurse -Force }
            New-Item -ItemType Directory -Path $rw -Force | Out-Null
            $orig = Join-Path $rw 'firefox.orig.exe'
            Copy-Item $ffExe $orig -Force

            # extract IE icon groups -> .rc + .ico files, take the first ICON entry
            $rc = Join-Path $rw 'ie.rc'
            Invoke-ResourceHacker $rh @('-open', "`"$ieExe`"", '-save', "`"$rc`"", '-action', 'extract', '-mask', 'ICONGROUP,,')
            $m = [regex]::Match((Get-Content $rc -Raw), '(?m)^\s*\S+\s+ICON\s+"([^"]+)"')
            if (-not $m.Success) { throw 'iexplore.exe에서 아이콘을 못 꺼냈어요.' }
            $ico = $m.Groups[1].Value -replace '\\\\', '\'
            if (-not [System.IO.Path]::IsPathRooted($ico)) { $ico = Join-Path $rw $ico }

            $step1 = Join-Path $rw 'firefox.icon.exe'
            Invoke-ResourceHacker $rh @('-open', "`"$orig`"", '-save', "`"$step1`"", '-action', 'addoverwrite', '-res', "`"$ico`"", '-mask', 'ICONGROUP,32512,1033')

            # String table 7 / entry 103: "Firefox" -> "Internet Explorer"
            $src = Join-Path $rw 'str.rc'
            Invoke-ResourceHacker $rh @('-open', "`"$step1`"", '-save', "`"$src`"", '-action', 'extract', '-mask', 'STRINGTABLE,7,1033')
            $txt = Get-Content $src -Raw
            $txt2 = [regex]::Replace($txt, '(\b103\s*,\s*)"[^"]*"', '$1"Internet Explorer"')
            Set-Content -Path $src -Value $txt2 -Encoding Unicode
            $res = Join-Path $rw 'str.res'
            Invoke-ResourceHacker $rh @('-open', "`"$src`"", '-save', "`"$res`"", '-action', 'compile')
            $final = Join-Path $rw 'firefox.exe'
            Invoke-ResourceHacker $rh @('-open', "`"$step1`"", '-save', "`"$final`"", '-action', 'addoverwrite', '-res', "`"$res`"", '-mask', 'STRINGTABLE,7,1033')

            Copy-FileSafe -Source $final -Destination $ffExe
            Write-Log 'firefox.exe 아이콘/이름을 IE로 바꿨어요.' 'OK'
        } else { Write-Log "(dry-run) Resource Hacker로 $ffExe 아이콘/이름 변경" 'DRY' }
    } catch {
        Write-Log "아이콘/이름 자동 변경 실패: $($_.Exception.Message)" 'WARN'
        Wait-User @(
            'Resource Hacker로 직접 바꾸세요:',
            "1) $ffExe 열기 → Ctrl+R 로 $ieExe 선택, Icon Group 32512:1033 을 Replace",
            '2) String Table 7:1033 의 103 "Firefox" → "Internet Explorer", F5, 저장',
            "3) 저장한 firefox.exe 를 $installDir 에 덮어쓰기"
        )
    }

    # 8) Shortcuts: Internet Explorer on desktop + start menu, remove the Firefox one
    foreach ($d in @([Environment]::GetFolderPath('CommonDesktopDirectory'), [Environment]::GetFolderPath('Desktop'))) {
        Remove-FileSafe (Join-Path $d 'Firefox.lnk')
    }
    New-Shortcut -Path (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Internet Explorer.lnk') -Target $ffExe -WorkingDirectory $installDir
    New-Shortcut -Path (Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'Internet Explorer.lnk') -Target $ffExe -WorkingDirectory $installDir

    Wait-User @(
        'Internet Explorer(=Firefox)를 처음 실행하면 BeautyFox 초기 설정 화면이 나와요. 원하는 대로 설정하세요.',
        '모양이 안 바뀌면 about:support > "시작 캐시 지우기" 후 재시작하세요.'
    )
}
