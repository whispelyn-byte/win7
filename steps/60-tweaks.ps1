# 8. Winaero Tweaker options (applied directly as registry values), 9. OldNewExplorer,
# 10. 7+ Taskbar Tweaker.

Register-Step -Id 'winaero-tweaks' -Order 60 -Title 'Winaero Tweaker 항목들 (레지스트리로 직접 적용)' -Kind Auto -After SignOut -Run {
    $adv = 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

    # --- Windows 11 -----------------------------------------------------------
    # Classic full context menus
    Set-RegValue -Path 'HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' -Name '' -Value '' -Type String
    # Disable background apps
    Set-RegValue -Path 'HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'GlobalUserDisabled' -Value 1
    Set-RegValue -Path 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' -Name 'LetAppsRunInBackground' -Value 2
    # Disable Copilot
    Set-RegValue -Path 'HKCU\Software\Policies\Microsoft\Windows\WindowsCopilot' -Name 'TurnOffWindowsCopilot' -Value 1
    Set-RegValue -Path 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' -Name 'TurnOffWindowsCopilot' -Value 1
    Set-RegValue -Path $adv -Name 'ShowCopilotButton' -Value 0
    # Remove "Learn about this picture" (Spotlight) desktop icon
    Set-RegValue -Path 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel' -Name '{2cc5ca98-6485-489a-920e-b3e88a6ccce3}' -Value 1

    # --- Behavior -------------------------------------------------------------
    # Disable ads / suggestions
    $cdm = 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($n in @('SilentInstalledAppsEnabled', 'SystemPaneSuggestionsEnabled', 'SoftLandingEnabled', 'RotatingLockScreenOverlayEnabled',
                     'SubscribedContent-310093Enabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
                     'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled')) {
        Set-RegValue -Path $cdm -Name $n -Value 0
    }
    Set-RegValue -Path $adv -Name 'ShowSyncProviderNotifications' -Value 0
    Set-RegValue -Path 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsConsumerFeatures' -Value 1
    # Disable "Look for an app in the Store"
    Set-RegValue -Path 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer' -Name 'NoUseStoreOpenWith' -Value 1

    # --- Context menu: remove default entries ---------------------------------
    if (Get-Cfg 'removeDefenderContextMenu' $true) {
        Block-ShellExtension '{09A47860-11B0-4DA5-AFA5-26D86198A780}' 'Scan with Microsoft Defender'
    }
    Block-ShellExtension '{BFE0E2A4-C70C-4AD7-AC3D-10D1ECEBB5B4}' 'Edit with Photos'
    Block-ShellExtension '{e2bf9676-5f8f-435c-97eb-11607a5bedf7}' 'Share (Modern Sharing)'
    Block-ShellExtension '{9F156763-7844-4DC4-B2B1-901F640F5155}' 'Open in Windows Terminal'
    Block-ShellExtension '{CA6CC9F1-867A-481E-951E-A28C5E4F01EA}' 'Edit in Notepad'
    Block-ShellExtension '{8AB635F8-9A67-4698-AB99-784AD929F3B4}' 'Edit in Clipchamp'
    Block-ShellExtension '{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}' 'Ask Copilot'
    # Edit with Paint 3D (only exists if Paint 3D is installed)
    foreach ($ext in @('.3mf', '.bmp', '.fbx', '.gif', '.glb', '.jfif', '.jpe', '.jpeg', '.jpg', '.obj', '.ply', '.png', '.stl', '.tif', '.tiff')) {
        Remove-RegKeySafe "HKLM\SOFTWARE\Classes\SystemFileAssociations\$ext\Shell\3D Edit"
    }

    # --- Microsoft Edge -------------------------------------------------------
    $edge = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'
    foreach ($kv in @(
        @('HideFirstRunExperience', 1), @('ShowRecommendationsEnabled', 0), @('HubsSidebarEnabled', 0),
        @('EdgeShoppingAssistantEnabled', 0), @('PersonalizationReportingEnabled', 0), @('StartupBoostEnabled', 0),
        @('BackgroundModeEnabled', 0), @('SpotlightExperiencesAndRecommendationsEnabled', 0), @('ShowMicrosoftRewards', 0),
        @('DiagnosticData', 0), @('NewTabPageContentEnabled', 0), @('NewTabPageHideDefaultTopSites', 1))) {
        Set-RegValue -Path $edge -Name $kv[0] -Value $kv[1]
    }
    $eu = 'HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate'
    Set-RegValue -Path $eu -Name 'CreateDesktopShortcutDefault' -Value 0
    Set-RegValue -Path $eu -Name 'UpdateDefault' -Value 0
    Set-RegValue -Path $eu -Name 'AutoUpdateCheckPeriodMinutes' -Value 0
    Set-RegValue -Path $eu -Name 'Update{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}' -Value 0
    Set-RegValue -Path $eu -Name 'RemoveDesktopShortcutDefault' -Value 1

    # --- Windows Terminal: remove "Open in Terminal" (also covered above) ------

    # --- Control Panel: add Windows Update ------------------------------------
    $guid = '{A5C8E7AE-BCFD-4DC5-A98C-6FE521881500}'
    $cls = "HKLM\SOFTWARE\Classes\CLSID\$guid"
    Set-RegValue -Path $cls -Name '' -Value 'Windows Update' -Type String
    Set-RegValue -Path $cls -Name 'InfoTip' -Value 'Windows Update' -Type String
    Set-RegValue -Path $cls -Name 'System.ControlPanel.Category' -Value '5' -Type String
    Set-RegValue -Path "$cls\DefaultIcon" -Name '' -Value '%SystemRoot%\System32\shell32.dll,-47' -Type ExpandString
    Set-RegValue -Path "$cls\Shell\Open\Command" -Name '' -Value 'explorer.exe ms-settings:windowsupdate' -Type String
    Set-RegValue -Path "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel\NameSpace\$guid" -Name '' -Value 'Windows Update' -Type String

    # --- Get Classic Apps: Windows Photo Viewer -------------------------------
    $pv = 'HKLM\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations'
    foreach ($ext in @('.bmp', '.dib', '.gif', '.ico', '.jfif', '.jpe', '.jpeg', '.jpg', '.jxr', '.png', '.tif', '.tiff', '.wdp')) {
        Set-RegValue -Path $pv -Name $ext -Value 'PhotoViewer.FileAssoc.Tiff' -Type String
    }

    # --- Navigation pane: remove Gallery --------------------------------------
    Set-RegValue -Path 'HKCU\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}' -Name 'System.IsPinnedToNameSpaceTree' -Value 0
}

Register-Step -Id 'oldnewexplorer' -Order 61 -Title 'OldNewExplorer (탐색 창/상태 표시줄)' -Kind Semi -Run {
    # Show Libraries in the navigation pane (guide does this first)
    Set-RegValue -Path 'HKCU\Software\Classes\CLSID\{031E4825-7B94-4dc3-B131-E946B44C8DD5}' -Name 'System.IsPinnedToNameSpaceTree' -Value 1
    $cfg = Find-Asset -Pattern @('OldNewExplorerCfg.exe')
    if (-not $cfg) {
        Open-Url 'https://www.majorgeeks.com/files/details/oldnewexplorer.html'
        Wait-User @('OldNewExplorer를 받아서 압축을 풀고 OldNewExplorerCfg.exe를 실행하세요.')
        return
    }
    Start-Program $cfg -NoWait
    Wait-User @(
        'OldNewExplorer 설정 창에서:',
        '  - Install 클릭',
        '  - 탐색 창(내비게이션) 위치 / 상태 표시줄 관련 옵션을 원하는 대로 체크',
        '  - 창 닫기'
    )
    Restart-Explorer
}

Register-Step -Id 'taskbar-tweaker' -Order 62 -Title '7+ Taskbar Tweaker (바탕 화면 보기 버튼 크기 15)' -Kind Auto -Run {
    $exe = Find-InstalledExe -Candidates @('%ProgramFiles%\7+ Taskbar Tweaker\7+ Taskbar Tweaker.exe', '%APPDATA%\7+ Taskbar Tweaker\7+ Taskbar Tweaker.exe') -SearchNames @('7+ Taskbar Tweaker.exe')
    if (-not $exe) {
        Install-Winget 'RamenSoftware.7+TaskbarTweaker'
        $exe = Find-InstalledExe -Candidates @('%ProgramFiles%\7+ Taskbar Tweaker\7+ Taskbar Tweaker.exe', '%APPDATA%\7+ Taskbar Tweaker\7+ Taskbar Tweaker.exe') -SearchNames @('7+ Taskbar Tweaker.exe')
    }
    Invoke-Action '7+ Taskbar Tweaker 종료' { Get-Process '7+ Taskbar Tweaker' -ErrorAction SilentlyContinue | Stop-Process -Force }
    # Advanced options > show_desktop_button_size = 15
    Set-RegValue -Path 'HKCU\Software\7 Taskbar Tweaker\OptionsEx' -Name 'show_desktop_button_size' -Value 15
    if ($exe) { Start-Program $exe -NoWait }
    Wait-User @('7+ Taskbar Tweaker가 뜨면 안내를 수락하세요.', "트레이 아이콘 우클릭 > 고급 옵션에서 show_desktop_button_size 가 15인지 확인하세요.")
}
