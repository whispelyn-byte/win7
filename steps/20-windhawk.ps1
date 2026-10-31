# 3. Windhawk + basic mods, 4/6. classic Windows 7 apps.

Register-Step -Id 'windhawk' -Order 20 -Title 'Windhawk 설치' -Kind Auto -Run {
    if (Get-WindhawkExe) { Write-Log 'Windhawk 이미 설치됨' 'OK'; return }
    Install-Winget 'RamenSoftware.Windhawk'
}

Register-Step -Id 'windhawk-basic-mods' -Order 21 -Title 'Windhawk 기본 모드 (테두리/두꺼운 프레임/UAC 어둡게)' -Kind Semi -Run {
    Install-WindhawkMods -Names @(
        'Bring Back the Borders!',
        'Force thick frames',
        'Windows 7 Style UAC Dim'
    )
}

Register-Step -Id 'classic-apps' -Order 30 -Title 'Win7 기본 앱 (계산기/메모장/그림판/워드패드/게임)' -Kind Semi -Run {
    Invoke-Action '앱 실행 별칭 설정 열기' { Start-Process 'ms-settings:advanced-apps' }
    Wait-User @(
        '설정 > 앱 > 고급 앱 설정 > 앱 실행 별칭 에서',
        '  - 메모장(notepad.exe)  끄기',
        '  - 그림판(mspaint.exe)  끄기',
        '(클래식 앱이 새 앱에 가로채이지 않게 하는 단계예요)'
    )
    Invoke-AssetInstallers -Under 'ClassicApps' -FallbackUrl 'https://win7games.com/' -What 'Classic Calculator / Notepad / Paint / WordPad / Windows 7 Games'
}
