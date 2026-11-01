# 0. Preflight: checks, restore point, tools, files from the Win7 ISO.

Register-Step -Id 'preflight' -Order 0 -Title '사전 점검 + 시스템 복원 지점' -Kind Auto -Run {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [int]$cv.CurrentBuild
    $ubr = [int]$cv.UBR
    Write-Log "Windows 빌드: $build.$ubr ($($cv.DisplayVersion))"

    if ($build -lt 22000) { Write-Log 'Windows 11이 아니에요. 이 스크립트는 Windows 11 기준이에요.' 'WARN' }
    if ($build -gt 26200 -or ($build -eq 26200 -and $ubr -ge 8457)) {
        Write-Log '원글: 빌드 26200.8457 이상은 비추천 (OpenGlass 불안정, github.com/ALTaleX531/OpenGlass/issues/299)' 'WARN'
        if (-not (Test-DryRun) -and -not (Confirm-User '그래도 계속할까요?' $false)) { throw '사용자가 중단함' }
    }
    if ($build -ge 26100) {
        Write-Log '24H2 이상: Explorer7은 2026-02-21부로 개발/지원 종료. 시작 메뉴 게임 항목, 트레이 네트워크 아이콘이 안 보이는 버그가 있어요.' 'WARN'
    }

    $ui = (Get-UICulture).Name
    $lang = Get-UiLanguage
    if ($ui -ne $lang) { Write-Log "config 언어($lang)와 Windows 표시 언어($ui)가 달라요." 'WARN' }

    $iso = Get-Cfg 'win7IsoPath' ''
    if (-not $iso) { $iso = Find-Asset -Pattern @('*.iso') }
    if (-not $iso -or -not (Test-Path $iso)) { Write-Log 'Windows 7 ISO 경로가 없어요 (config.json의 win7IsoPath). ISO가 필요한 단계가 실패할 거예요.' 'WARN' }

    Wait-User @(
        '원글 주의사항:',
        '- Discord, Spotify, Twitch 같은 Electron 앱은 AeroUI 적용 전에 미리 설치해 두세요 (나중에 설치하면 깨질 수 있음).',
        '- Windows Update 후 레지스트리가 깨질 수 있어요.',
        '- 가능하면 VM에서 먼저 해보세요. 모든 건 자기 책임!'
    ) '계속하려면 Enter'

    Invoke-Action '시스템 복원 지점 생성' {
        Enable-ComputerRestore -Drive "$env:SystemDrive\"
        # allow more than one restore point per 24h
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force | Out-Null
        Checkpoint-Computer -Description 'Before Win7Look' -RestorePointType 'MODIFY_SETTINGS'
    }
}

Register-Step -Id 'tools' -Order 5 -Title '필수 도구 설치 (7-Zip)' -Kind Auto -Run {
    if (Get-SevenZip) { Write-Log '7-Zip 이미 설치됨' 'OK'; return }
    Install-Winget '7zip.7zip'
}

Register-Step -Id 'assets-unpack' -Order 6 -Title 'assets 안의 zip 풀기 + 에셋 점검' -Kind Auto -Run {
    if (-not (Test-Path $W7.Assets)) { Write-Log "assets 폴더가 없어요: $($W7.Assets)" 'WARN'; return }
    $out = Join-Path $W7.Assets '_unpacked'
    $7z = Get-SevenZip
    # Google Drive downloads are zip-in-zip, so repeat a few rounds
    for ($round = 1; $round -le 4; $round++) {
        $zips = @(Get-ChildItem -LiteralPath $W7.Assets -Recurse -File -Filter '*.zip' -ErrorAction SilentlyContinue |
                  Where-Object { -not (Test-Path -LiteralPath ($_.FullName + '.unpacked')) })
        if ($zips.Count -eq 0) { break }
        foreach ($z in $zips) {
            # top-level zips go to assets\_unpacked\<name>, nested ones next to themselves
            $dest = if ($z.FullName.StartsWith($out, [StringComparison]::OrdinalIgnoreCase)) {
                Join-Path $z.DirectoryName $z.BaseName
            } else { Join-Path $out $z.BaseName }
            Invoke-Action "압축 풀기: $($z.Name) -> $dest" {
                if ($7z) {
                    & $7z x $z.FullName "-o$dest" -y 2>&1 | Out-Null
                    if ($LASTEXITCODE -gt 1) { throw "7-Zip 압축 풀기 실패 ($LASTEXITCODE): $($z.FullName)" }
                } else {
                    Expand-Archive -LiteralPath $z.FullName -DestinationPath $dest -Force
                }
                Set-Content -LiteralPath ($z.FullName + '.unpacked') -Value $dest -Encoding UTF8
            }
        }
        if (Test-DryRun) { break }
    }

    # log the layout (3 levels) so pattern mismatches are easy to spot
    if (Test-Path $out) {
        $base = (Resolve-Path $out).Path
        Get-ChildItem -LiteralPath $base -Recurse -Depth 2 -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Log ('  assets\_unpacked' + $_.FullName.Substring($base.Length))
        }
    }

    # quick asset inventory (warn only)
    $checks = @(
        @{ n = 'SecureUxTheme msi';        p = @('SecureUxTheme*.msi') },
        @{ n = 'Aero11 테마 폴더';          p = @('Aero11*', '*Aero*'); d = $true; c = '*.theme' },
        @{ n = 'OpenGlass 설치 파일';       p = @('OpenGlassSetup*.exe') },
        @{ n = 'oglbasic.reg';             p = @('oglbasic.reg') },
        @{ n = 'oglfull.reg';              p = @('oglfull.reg') },
        @{ n = 'NTMU 팩: explorer-frame';  p = @('explorer-frame-vista*'); d = $true },
        @{ n = 'NTMU 팩: cursor-7';        p = @('cursor-7*'); d = $true },
        @{ n = 'NTMU 팩: win7-ribbon';     p = @('win7-ribbon*'); d = $true },
        @{ n = 'NTMU 팩: briefcase';       p = @('briefcase*'); d = $true },
        @{ n = 'NTMU 팩: pane7';           p = @('pane7*'); d = $true },
        @{ n = 'NTMU 팩: win7-tray-items'; p = @('win7-tray-items*'); d = $true },
        @{ n = 'NTMU 팩: gameux';          p = @('gameux*'); d = $true },
        @{ n = 'Explorer7 (ex7forw8.exe)'; p = @('ex7forw8.exe') },
        @{ n = 'OldNewExplorer';           p = @('OldNewExplorerCfg.exe') },
        @{ n = 'OpenWithEx';               p = @('OpenWithEx*'); d = $true },
        @{ n = 'AuthUx';                   p = @('AuthUx*'); d = $true },
        @{ n = 'Network Activity Indicator'; p = @('NetworkIndicator.exe') },
        @{ n = 'Win7 사운드 (Media)';       p = @('Media*'); d = $true; c = '*.wav' }
    )
    $missing = 0
    foreach ($c in $checks) {
        $hit = Find-Asset -Pattern $c.p -Directory:([bool]$c.d) -Containing ([string]$c.c)
        if ($hit) { Write-Log "에셋 OK: $($c.n)" } else { Write-Log "에셋 없음: $($c.n)" 'WARN'; $missing++ }
    }
    if ($missing -gt 0) { Write-Log "없는 에셋 $missing 개. 해당 단계에서 멈추거나 수동 안내로 바뀌어요. (assets\README.md 참고)" 'WARN' }

}

Register-Step -Id 'win7-extract' -Order 8 -Title 'Windows 7 ISO에서 필요한 파일 추출' -Kind Auto -Run {
    $lang = Get-UiLanguage
    $paths = @(
        'Windows\System32\imageres.dll',
        'Windows\System32\shell32.dll',
        'Windows\System32\AltTab.dll',
        "Windows\System32\$lang\AltTab.dll.mui",
        'Windows\System32\en-US\AltTab.dll.mui',
        'Windows\Media',
        'ProgramData\Microsoft\User Account Pictures',
        'Program Files\Internet Explorer\iexplore.exe'
    ) | Select-Object -Unique
    Expand-Win7Files -Paths $paths
}
