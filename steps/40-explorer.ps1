# 5. NTMU packs + Explorer chain, in the order the guide gives.
# Guide warning: mistakes here are hard to undo, so each pack is its own resumable step.

Register-Step -Id 'ntmu' -Order 40 -Title 'NTMU (Windows NT Modding Utility) 설치' -Kind Semi -Run {
    if (Get-NtmuExe) { Write-Log 'NTMU 이미 설치됨' 'OK'; return }
    Invoke-AssetInstallers -Under 'NTMU' -FallbackUrl 'https://get-ntmu.github.io/' -What 'NTMU'
}

Register-Step -Id 'explorer-frame' -Order 41 -Title 'NTMU: Windows 7 Explorer Frame' -Kind Semi -Run {
    Invoke-NtmuPack -PackPattern 'explorer-frame-vista*' -Label 'explorer-frame-vista (Windows 7 Explorer Frame)'
}

Register-Step -Id 'cursor-7' -Order 42 -Title 'NTMU: Windows 7 커서' -Kind Semi -Run {
    Invoke-NtmuPack -PackPattern 'cursor-7*' -Label 'cursor-7'
    Update-SystemCursors
    Wait-User @(
        '커서가 아직 Win11 모양이면:',
        '제어판 > 하드웨어 및 소리 > 마우스 > 포인터 > 구성표를 다른 걸로 바꿨다가 다시 원래 걸로 → 적용',
        "'포인터 그림자 사용'은 자동으로 켰어요."
    )
}

Register-Step -Id 'aerexplorer' -Order 43 -Title 'Windhawk: Aerexplorer (탐색기 Win7 스타일)' -Kind Semi -Run {
    $src = Find-Asset -Pattern @('aerexplorer*.cpp', '*.cpp') -Under 'Aerexplorer'
    if (-not $src) {
        $src = Invoke-Download -Url 'https://raytek.cafe/blog/resources/re8pl/aerexplorer11fork.cpp' -OutFile (Join-Path $W7.Work 'aerexplorer11fork.cpp')
    }
    Start-Windhawk
    Wait-User @(
        'Windhawk 설정 > 기타 고급 설정 에서 아래 3개 체크 해제:',
        '  - 중요한 시스템 프로세스 제외',
        '  - 호환되지 않는 알려진 프로그램 제외',
        '  - 유명한 게임 제외',
        '같은 화면의 프로세스 포함 목록에 추가:  svchost.exe',
        '저장하세요.'
    )
    if (-not (Test-DryRun)) { Set-ClipboardText (Get-Content $src -Raw -Encoding UTF8) }
    Wait-User @(
        'Windhawk > 새 Mod 만들기',
        '편집기에서 Ctrl+A → Ctrl+V (Aerexplorer 소스가 클립보드에 있어요)',
        '컴파일 → 활성화',
        "소스 파일: $src",
        '※ 드라이브 이름이 깨지면 빌드 번호가 안 맞는 거예요. 다른 포크(assets\Aerexplorer\)를 쓰세요.'
    )
}

Register-Step -Id 'win7-ribbon' -Order 44 -Title 'NTMU: Win7 리본(명령 모음)' -Kind Semi -Run {
    Invoke-NtmuPack -PackPattern 'win7-ribbon*' -Label 'win7-ribbon'
}

Register-Step -Id 'briefcase' -Order 45 -Title 'NTMU: 서류 가방 (우클릭 메뉴)' -Kind Semi -Run {
    Invoke-NtmuPack -PackPattern 'briefcase*' -Label 'briefcase'
}

Register-Step -Id 'pane7' -Order 46 -Title 'NTMU: pane7 (세부 정보 창)' -Kind Semi -Run {
    $lang = Get-UiLanguage
    if ($lang -ne 'en-US') {
        # pane7 patches the en-US resources, so the guide copies the UI language folder over en-US first
        $from = Join-Path $env:SystemRoot $lang
        $to = Join-Path $env:SystemRoot 'en-US'
        Write-Log "pane7 준비: $from 내용을 $to 에 복사 (원본은 백업)"
        Copy-DirSafe -Source $from -Destination $to
    }
    Invoke-NtmuPack -PackPattern 'pane7*' -Label 'pane7'
    Clear-IconCache
}

Register-Step -Id 'explorerpatcher' -Order 47 -Title 'ExplorerPatcher 설치 + Alt+Tab을 Windows 10 방식으로' -Kind Auto -Run {
    $setup = Find-Asset -Pattern @('ep_setup*.exe')
    if (-not $setup) {
        $url = Get-GitHubReleaseAsset -Repo 'valinet/ExplorerPatcher' -NameLike 'ep_setup.exe'
        $setup = Invoke-Download -Url $url -OutFile (Join-Path $W7.Work 'ep_setup.exe')
    }
    Start-Program $setup | Out-Null
    Start-Sleep -Seconds 5
    # ExplorerPatcher: "Window switcher (Alt+Tab) style"  0 = Windows 11, 1 = Windows 10
    Set-RegValue -Path 'HKCU\Software\ExplorerPatcher' -Name 'AltTabSettings' -Value 1
    Restart-Explorer
    Wait-User @(
        '작업 표시줄 우클릭 > 속성 (ExplorerPatcher 설정) > 창 전환(Window switcher)',
        "'Windows 10'으로 되어 있는지 확인하세요."
    )
}

Register-Step -Id 'win7-tray-items' -Order 48 -Title 'NTMU: Win7 트레이 항목' -Kind Semi -After Reboot -Run {
    $opts = @()
    if (Get-Cfg 'isLaptop' $false) { $opts = @('Battery Meter (For Laptops)', 'Mobility Center (For Laptops)') }
    else { $opts = @('(데스크톱: 기본값 그대로)') }
    Invoke-NtmuPack -PackPattern 'win7-tray-items*' -Label 'win7-tray-items' -Options $opts
}

Register-Step -Id 'alttab' -Order 49 -Title 'Win7 Alt+Tab (AltTab.dll 복사 + Windhawk 로더)' -Kind Semi -Run {
    $lang = Get-UiLanguage
    $sys = Join-Path $env:SystemRoot 'System32'
    $dll = Get-Win7File 'Windows\System32\AltTab.dll'
    $dllA = Find-Asset -Pattern @('AltTab.dll')
    if ($dllA) { $dll = $dllA }
    Copy-FileSafe -Source $dll -Destination (Join-Path $sys 'AltTab.dll')

    # .mui: prefer one in the UI language; otherwise put the en-US one in both folders
    $mui = Get-Win7File "Windows\System32\$lang\AltTab.dll.mui"
    $muiA = Find-Asset -Pattern @('AltTab.dll.mui')
    if ($muiA) { $mui = $muiA }
    if ((Test-DryRun) -or (Test-Path $mui)) {
        Copy-FileSafe -Source $mui -Destination (Join-Path $sys "$lang\AltTab.dll.mui")
    } else {
        $en = Get-Win7File 'Windows\System32\en-US\AltTab.dll.mui'
        Write-Log "ISO에 $lang 용 AltTab.dll.mui가 없어서 en-US 것을 써요." 'WARN'
        Copy-FileSafe -Source $en -Destination (Join-Path $sys 'en-US\AltTab.dll.mui')
        Copy-FileSafe -Source $en -Destination (Join-Path $sys "$lang\AltTab.dll.mui")
    }
    Install-WindhawkMods -Names @('Alt+Tab') -Notes @("검색 결과에서 Win7 AltTab.dll을 불러오는 'Alt+Tab loader' 모드를 설치하세요.")
}

Register-Step -Id 'explorer7' -Order 50 -Title 'Explorer7 (Win7 작업 표시줄/시작 메뉴)' -Kind Semi -After SignOut -Run {
    $ex7 = Require-Asset -Pattern @('ex7forw8.exe') -Hint 'ex7-m2_winmain_r4 폴더'
    $dir = Split-Path $ex7 -Parent
    if (Test-Path $dir) {
        foreach ($r in (Get-ChildItem $dir -Filter '*.reg' -File)) { Import-RegFile $r.FullName }
    }
    $drive = Mount-Win7Iso
    Set-ClipboardText $drive
    # ex7forw8 signs out by itself, so mark this step done and arm resume first
    Set-StepDone 'explorer7'
    Register-Resume
    Wait-User @(
        "Windows 7 ISO가 $drive 에 마운트돼 있어요 (클립보드에 복사함).",
        'ex7forw8 창에서 Windows 7 을 선택하고 진행하세요.',
        '끝나면 자동으로 로그아웃돼요. 다시 로그인하면 스크립트가 이어서 실행돼요.'
    ) 'ex7forw8 실행하려면 Enter'
    Start-Program $ex7 | Out-Null
}

Register-Step -Id 'explorer7-post' -Order 51 -Title 'Explorer7 후속 설정 (레지스트리/폴더 옵션)' -Kind Auto -After RestartExplorer -Run {
    $adv = 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-RegValue -Path $adv -Name 'EnableImmersive' -Value 1
    Set-RegValue -Path $adv -Name 'ColorizationOptions' -Value 0
    # Taskbar properties: "Use Aero Peek to preview the desktop"
    Set-RegValue -Path $adv -Name 'DisablePreviewDesktop' -Value 0
    # Folder options (as in the guide): no frequent folders, no Office.com files, status bar off
    $exp = 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer'
    Set-RegValue -Path $exp -Name 'ShowFrequent' -Value 0
    Set-RegValue -Path $exp -Name 'ShowCloudFilesInQuickAccess' -Value 0
    Set-RegValue -Path $adv -Name 'ShowStatusBar' -Value 0
}

Register-Step -Id 'gameux' -Order 52 -Title 'NTMU: gameux (게임 탐색기)' -Kind Semi -After RestartExplorer -Run {
    Invoke-NtmuPack -PackPattern 'gameux*' -Label 'gameux'
}
