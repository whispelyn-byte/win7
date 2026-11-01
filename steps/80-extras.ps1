# 12-23. Extras: OpenWithEx, AuthUx, This PC commands, gadgets, account pictures, font,
# Recent Folders, network activity indicator, explorer icon redirect, extra Windhawk mods,
# sounds, removal of default Windows 11 apps.

Register-Step -Id 'openwithex' -Order 80 -Title "OpenWithEx (Win7 스타일 '연결 프로그램')" -Kind Semi -Run {
    Invoke-AssetInstallers -Under 'OpenWithEx' -What 'OpenWithEx'
}

Register-Step -Id 'authux' -Order 81 -Title 'AuthUx (Win7 로그온 화면)' -Kind Semi -Run {
    Invoke-AssetInstallers -Under 'AuthUx' -What 'AuthUx'
}

Register-Step -Id 'this-pc-commands' -Order 82 -Title 'Windhawk: Old This PC Commands (내 PC에 제어판 등)' -Kind Semi -Run {
    Install-WindhawkMods -Names @('Old This PC Commands')
}

Register-Step -Id 'gadgets' -Order 83 -Title 'Windows 7 가젯' -Kind Semi -Run {
    Invoke-AssetInstallers -Under 'Gadgets' -FallbackUrl 'https://gadgetsrevived.com/' -What 'Windows 7 Gadgets (8GadgetPack 등)'
}

Register-Step -Id 'account-pictures' -Order 84 -Title 'Win7 사용자 계정 사진' -Kind Auto -Run {
    $src = Find-Asset -Pattern @('User Account Pictures') -Directory -Containing '*.*'
    if (-not $src) { $src = Get-Win7File 'ProgramData\Microsoft\User Account Pictures' }
    Copy-DirSafe -Source $src -Destination (Join-Path $env:ProgramData 'Microsoft\User Account Pictures')
}

Register-Step -Id 'system-font' -Order 85 -Title '시스템 글꼴 변경' -Kind Semi -Run {
    $tool = Find-Asset -Pattern @('*.exe') -Under 'FontChanger'
    if ($tool) { Start-Program $tool -NoWait }
    else { Open-Url 'https://forest.watch.impress.co.jp/library/software/win10fontchg/' }
    Wait-User @('글꼴 변경 도구로 시스템 글꼴을 원하는 걸로 바꾸세요 (원글에도 세부 설명은 없어요).')
}

Register-Step -Id 'recent-folders' -Order 86 -Title "'최근 폴더' 바로가기" -Kind Semi -Run {
    $name = if ((Get-UiLanguage) -like 'ko-*') { '최근 폴더.lnk' } else { 'Recent Folders.lnk' }
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) $name
    New-Shortcut -Path $lnk -Target "$env:SystemRoot\explorer.exe" -Arguments 'shell:::{22877a6d-37a1-461a-91b0-dbda5aaebc99}' -IconLocation '%SystemRoot%\System32\imageres.dll,-117'
    Wait-User @("바탕 화면의 '$($name -replace '\.lnk$','')' 바로가기를 더블클릭 → 작업 표시줄 아이콘 우클릭 → 작업 표시줄에 고정")
}

Register-Step -Id 'network-indicator' -Order 87 -Title '네트워크 활동 표시기 (로그온 시 자동 실행)' -Kind Auto -Run {
    $defaultDir = 'C:\Windows (Vista-7)\Network Activity Indicator'
    $exe = Join-Path $defaultDir 'NetworkIndicator.exe'
    if (-not (Test-Path $exe)) {
        # assets has two versions: "Network Activity Indicator" and "Network Activity Indicator (Wifi)"
        $wifi = [bool](Get-Cfg 'networkIndicatorWifi' $false)
        $all = @()
        if (Test-Path $W7.Assets) { $all = @(Get-ChildItem -LiteralPath $W7.Assets -Recurse -File -Filter 'NetworkIndicator.exe' -ErrorAction SilentlyContinue) }
        $pick = @($all | Where-Object { ($_.FullName -like '*Wifi*') -eq $wifi }) + $all | Select-Object -First 1
        if ($pick) {
            Write-Log "네트워크 표시기 원본: $($pick.DirectoryName)"
            Copy-DirSafe -Source $pick.DirectoryName -Destination $defaultDir
        } else {
            Invoke-AssetInstallers -Under 'Network Activity Indicator' -What 'Network Activity Indicator'
        }
    }
    if (-not (Test-Path $exe) -and -not (Test-DryRun)) {
        $hit = Find-InstalledExe -Candidates @() -SearchNames @('NetworkIndicator.exe') -SearchRoots @('C:\Windows (Vista-7)', $env:ProgramFiles, ${env:ProgramFiles(x86)})
        if ($hit) { $exe = $hit } else { throw "NetworkIndicator.exe를 못 찾았어요 (예상 위치: $exe)" }
    }
    Invoke-Action "작업 스케줄러 등록: Network -> $exe" {
        $action = New-ScheduledTaskAction -Execute $exe
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName 'Network' -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
        Add-ManifestEntry @{ kind = 'task'; name = 'Network' }
        Start-Process $exe
    }
}

Register-Step -Id 'icon-redirect' -Order 88 -Title 'explorer.exe/시스템 아이콘을 Win7 것으로 (Resource Redirect)' -Kind Semi -Run {
    $dir = Get-Cfg 'iconRedirectDir' 'C:\icons'
    Invoke-Action "폴더 생성: $dir" { if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null } }

    $ex7 = Find-Asset -Pattern @('ex7forw8.exe')
    $explorer = if ($ex7) { Join-Path (Split-Path $ex7 -Parent) 'explorer.exe' } else { $null }
    if (-not $explorer -or -not (Test-Path $explorer)) { $explorer = Require-Asset -Pattern @('explorer.exe') -Hint 'Explorer7 폴더의 explorer.exe' }
    Copy-FileSafe -Source $explorer -Destination (Join-Path $dir 'explorer.exe')
    Copy-FileSafe -Source (Get-Win7File 'Windows\System32\imageres.dll') -Destination (Join-Path $dir 'imageres.dll')
    Copy-FileSafe -Source (Get-Win7File 'Windows\System32\shell32.dll') -Destination (Join-Path $dir 'shell32.dll')

    # The guide's copy-paste text lost its backslashes; this is the intended content.
    $ini = Join-Path $dir 'theme.ini'
    Invoke-Action "theme.ini 작성: $ini" {
        $tmp = Join-Path $W7.Work 'theme.ini'
        @(
            '[redirections]',
            '%SystemRoot%\explorer.exe=explorer.exe',
            '%SystemRoot%\System32\imageres.dll=imageres.dll',
            '%SystemRoot%\System32\shell32.dll=shell32.dll'
        ) | Set-Content -Path $tmp -Encoding Unicode
        Copy-FileSafe -Source $tmp -Destination $ini
    }

    Install-WindhawkMods -Names @('Resource Redirect') -Notes @(
        "모드 설정: 'Redirect all loaded resources (experimental)' 켜기, Theme paths 에 $ini 입력 → 저장"
    )
    Clear-IconCache
    Wait-User @(
        '아이콘이 안 바뀌면 재부팅 후 다시 확인하세요.',
        '그래도 안 되면 대안: 아이콘/대상을 바꾼 바로가기를 작업 표시줄에 고정 (원글 방법).'
    )
}

Register-Step -Id 'windhawk-extras' -Order 89 -Title 'Windhawk 추가 모드' -Kind Semi -Run {
    Install-WindhawkMods -Names @(
        'Aero Flyout Fix',
        'Legacy File Copy',
        'Logon, Logoff & Shutdown Sounds Restored',
        'Restore Button Pulse Animation'
    )
}

Register-Step -Id 'sounds' -Order 90 -Title 'Windows 7 사운드' -Kind Auto -Run {
    $src = Find-Asset -Pattern @('Media*') -Directory -Containing '*.wav'
    if (-not $src) { $src = Get-Win7File 'Windows\Media' }
    if (-not (Test-DryRun) -and -not (Test-Path $src)) { throw "Win7 사운드 폴더가 없어요: $src" }
    Write-Log '원글: 사운드 교체는 VM에서 하는 걸 추천. 원본은 백업해 둬요.' 'WARN'
    Copy-DirSafe -Source $src -Destination (Join-Path $env:SystemRoot 'Media')
    # play the startup sound again
    Set-RegValue -Path 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation' -Name 'DisableStartupSound' -Value 0
}

Register-Step -Id 'remove-default-apps' -Order 91 -Title 'Windows 11 기본 앱 제거' -Kind Auto -Run {
    $default = @(
        'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch', 'Microsoft.GetHelp', 'Microsoft.Getstarted',
        'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.People', 'Microsoft.PowerAutomateDesktop',
        'Microsoft.Todos', 'Microsoft.WindowsFeedbackHub', 'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'Microsoft.YourPhone',
        'Microsoft.WindowsMaps', 'Microsoft.WindowsAlarms', 'Microsoft.549981C3F5F10', 'Microsoft.Copilot', 'Microsoft.Windows.DevHome',
        'Microsoft.OutlookForWindows', 'MicrosoftCorporationII.QuickAssist', 'Clipchamp.Clipchamp', 'MSTeams', 'MicrosoftTeams'
    )
    $list = @(Get-Cfg 'removeApps' $default)
    Write-Log "제거 대상 $($list.Count)개 (config.json의 removeApps로 바꿀 수 있어요). ※ 이 단계는 -Rollback으로 안 돌아와요. Store에서 다시 설치하세요." 'WARN'
    foreach ($n in $list) {
        $pkgs = @(Get-AppxPackage -Name $n -ErrorAction SilentlyContinue)
        $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $n })
        if ($pkgs.Count -eq 0 -and $prov.Count -eq 0) { continue }
        Invoke-Action "앱 제거: $n" {
            foreach ($p in $pkgs) { try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop } catch { Write-Log "제거 실패 $($p.Name): $_" 'WARN' } }
            foreach ($p in $prov) { try { Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null } catch { Write-Log "프로비전 제거 실패 $($p.DisplayName): $_" 'WARN' } }
        }
    }
}
