# 1. Aero11 theme (SecureUxTheme) and 2. OpenGlass.

Register-Step -Id 'secureuxtheme' -Order 10 -Title 'SecureUxTheme 설치 (비공식 테마 허용)' -Kind Auto -After Reboot -Run {
    $msi = Require-Asset -Pattern @('SecureUxTheme*x64*.msi', 'SecureUxTheme*.msi') -Hint '구글 드라이브의 SecureUxTheme'
    $code = Start-Program 'msiexec.exe' @('/i', "`"$msi`"", '/passive', '/norestart')
    if ($code -and $code -ne 0 -and $code -ne 3010) { throw "SecureUxTheme 설치 실패 (msiexec $code)" }
}

Register-Step -Id 'aero11-theme' -Order 11 -Title 'Aero11 테마 복사 + 적용' -Kind Auto -Run {
    $src = Require-Asset -Pattern @('Aero11') -Directory -Hint '구글 드라이브의 Aero11 폴더'
    $dest = Join-Path $env:SystemRoot 'Resources\Themes'
    Copy-DirSafe -Source $src -Destination $dest

    $theme = $null
    if (Test-Path $src) { $theme = Get-ChildItem $src -Filter '*.theme' -File | Select-Object -First 1 }
    if ($theme) {
        $target = Join-Path $dest $theme.Name
        Invoke-Action "테마 적용: $($theme.Name)" { Start-Process $target }
        Start-Sleep -Seconds 3
        Wait-User @('개인 설정 창에서 Aero 테마가 적용됐는지 확인하세요.', '안 됐으면 개인 설정 > 테마에서 직접 선택하세요.')
    } else {
        Invoke-Action '개인 설정 열기' { Start-Process 'ms-settings:themes' }
        Wait-User @('개인 설정 > 테마에서 Aero11 테마를 선택하세요.')
    }
}

Register-Step -Id 'openglass' -Order 12 -Title 'OpenGlass (Aero 유리 효과)' -Kind Auto -After SignOut -Run {
    $setup = Require-Asset -Pattern @('OpenGlassSetup*.exe') -Hint '구글 드라이브의 OpenGlass 폴더'
    Wait-User @('OpenGlass 설치 창이 뜨면 기본값으로 설치하세요.', '※ 원글: DWM을 후킹해서 불안정할 수 있어요.') '설치 창을 띄우려면 Enter'
    Start-Program $setup | Out-Null
    foreach ($r in @('oglbasic.reg', 'oglfull.reg')) {
        $f = Require-Asset -Pattern @($r)
        Import-RegFile $f
    }
}
