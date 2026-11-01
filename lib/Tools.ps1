# Helpers for specific third-party tools (Windhawk, NTMU, Win7 image extraction, Win32 calls).

# ---------------------------------------------------------------------------
# Generic: find an installed program exe
# ---------------------------------------------------------------------------
function Find-InstalledExe {
    param([Parameter(Mandatory)] [string[]] $Candidates, [string[]] $SearchNames = @(), [string[]] $SearchRoots = @())
    foreach ($c in $Candidates) { $e = [Environment]::ExpandEnvironmentVariables($c); if (Test-Path $e) { return $e } }
    if ($SearchNames.Count -gt 0) {
        if ($SearchRoots.Count -eq 0) { $SearchRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs')) }
        foreach ($root in $SearchRoots) {
            if (-not $root -or -not (Test-Path $root)) { continue }
            foreach ($n in $SearchNames) {
                $hit = Get-ChildItem -Path $root -Filter $n -Recurse -Depth 3 -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($hit) { return $hit.FullName }
            }
        }
    }
    return $null
}

# Run every installer (.msi/.exe) in an assets subfolder, one by one.
function Invoke-AssetInstallers {
    param([Parameter(Mandatory)] [string] $Under, [string] $FallbackUrl = '', [string] $What = '')
    $dir = Find-Asset -Pattern @($Under, "$Under*") -Directory
    $files = @()
    if ($dir) { $files = @(Get-ChildItem $dir -Recurse -File -Include '*.exe', '*.msi' -ErrorAction SilentlyContinue | Sort-Object Name) }
    if ($files.Count -eq 0) {
        Write-Log "assets\$Under 에 설치 파일이 없어요." 'WARN'
        if ($FallbackUrl) { Open-Url $FallbackUrl }
        Wait-User @("$What 을(를) 직접 받아서 설치하세요.", $FallbackUrl)
        return
    }
    foreach ($f in $files) {
        if ($f.Extension -eq '.msi') { Start-Program 'msiexec.exe' @('/i', "`"$($f.FullName)`"", '/passive', '/norestart') | Out-Null }
        else { Start-Program $f.FullName | Out-Null }
    }
}

# ---------------------------------------------------------------------------
# Windhawk
# ---------------------------------------------------------------------------
function Get-WindhawkExe {
    return Find-InstalledExe -Candidates @('%ProgramFiles%\Windhawk\windhawk.exe') -SearchNames @('windhawk.exe')
}

function Start-Windhawk {
    $exe = Get-WindhawkExe
    if ($exe) { Start-Program $exe -NoWait } else { Write-Log 'Windhawk 실행 파일을 못 찾았어요. 직접 여세요.' 'WARN' }
}

# Windhawk has no supported CLI for installing mods, so walk the user through it.
function Install-WindhawkMods {
    param([Parameter(Mandatory)] [string[]] $Names, [string[]] $Notes = @())
    Start-Windhawk
    $i = 0
    foreach ($n in $Names) {
        $i++
        Set-ClipboardText $n
        $lines = @(
            "Windhawk 모드 설치 ($i/$($Names.Count)): $n",
            "1) Windhawk > '탐색(Explore)' 탭 > 검색창에 붙여넣기(Ctrl+V)  ← 이름이 클립보드에 있어요",
            "2) '$n' 열기 > 설치(Install) > 설치 수락"
        )
        if ($Notes.Count -ge $i -and $Notes[$i - 1]) { $lines += ('3) ' + $Notes[$i - 1]) }
        Wait-User $lines
    }
}

# ---------------------------------------------------------------------------
# NTMU (Windows NT Modding Utility)
# ---------------------------------------------------------------------------
function Get-NtmuExe {
    $cfg = Get-Cfg 'ntmuPath' ''
    if ($cfg -and (Test-Path $cfg)) { return $cfg }
    return Find-InstalledExe -Candidates @() -SearchNames @('ntmu*.exe', 'NTModdingUtility*.exe', 'Windows NT Modding Utility*.exe')
}

function Invoke-NtmuPack {
    param(
        [Parameter(Mandatory)] [string] $PackPattern,
        [Parameter(Mandatory)] [string] $Label,
        [string[]] $ExtraLines = @(),
        [string[]] $Options = @()
    )
    $dir = Require-Asset -Pattern @($PackPattern) -Directory -Hint "NTMU Packs 폴더 안의 $Label 팩"
    $ini = $null
    if (Test-Path $dir) { $ini = Get-ChildItem $dir -Recurse -Filter 'pack.ini' -File -ErrorAction SilentlyContinue | Select-Object -First 1 }
    $iniPath = if ($ini) { $ini.FullName } else { Join-Path $dir 'pack.ini' }

    $exe = Get-NtmuExe
    if ($exe) { Start-Program $exe -NoWait } else { Write-Log 'NTMU 실행 파일을 못 찾았어요. 직접 여세요.' 'WARN' }
    Set-ClipboardText $iniPath

    $lines = @(
        "NTMU 팩 적용: $Label",
        "1) NTMU에서 팩 열기 → 이 파일 선택 (경로가 클립보드에 있어요):",
        "   $iniPath"
    )
    if ($Options.Count -gt 0) { $lines += '2) 옵션 체크:'; $lines += ($Options | ForEach-Object { "   - $_" }) }
    $lines += "적용(Apply) 클릭 → 끝나면 NTMU 안내대로 탐색기 재시작"
    $lines += $ExtraLines
    $lines += '※ 원글 경고: 여기서 실수하면 되돌리기 어려워요. 순서대로 하세요.'
    Wait-User $lines
}

# ---------------------------------------------------------------------------
# Win7 image extraction (7-Zip)
# ---------------------------------------------------------------------------
function Expand-Win7Files {
    param([Parameter(Mandatory)] [string[]] $Paths)
    $drive = Mount-Win7Iso
    $wim = $null
    foreach ($n in @('sources\install.wim', 'sources\install.esd')) {
        $p = Join-Path $drive $n
        if ((Test-DryRun) -or (Test-Path $p)) { $wim = $p; break }
    }
    if (-not $wim) { throw "ISO에서 install.wim/esd를 찾지 못했어요 ($drive)" }
    $7z = Get-SevenZip
    if (-not $7z -and -not (Test-DryRun)) { throw '7-Zip이 없어요 (tools 단계를 먼저 실행하세요).' }

    $idx = [string](Get-Cfg 'win7WimIndex' 1)
    $raw = Join-Path $W7.Work 'win7raw'
    if (Test-DryRun) { Write-Log "(dry-run) 7z x $wim (index $idx): $($Paths -join '; ')" 'DRY'; return }

    if (Test-Path $raw) { Remove-Item $raw -Recurse -Force }
    # multi-image WIMs list files as "<index>\Windows\...", single-image ones without a prefix
    $withIdx = $Paths | ForEach-Object { "$idx\$_" }
    & $7z x $wim "-o$raw" -y @withIdx 2>&1 | Out-Null
    $src = Join-Path $raw $idx
    if (-not (Test-Path $src)) {
        & $7z x $wim "-o$raw" -y @Paths 2>&1 | Out-Null
        $src = $raw
    }
    if (-not (Test-Path $src)) { throw "install.wim에서 파일을 꺼내지 못했어요. win7WimIndex 설정을 확인하세요." }
    # replace the extracted tree as a whole (Copy-Item -Recurse into existing folders nests them)
    if (Test-Path $W7.Win7) { Remove-Item $W7.Win7 -Recurse -Force }
    Move-Item -LiteralPath $src -Destination $W7.Win7
    Remove-Item $raw -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($p in $Paths) {
        if (Test-Path (Join-Path $W7.Win7 $p)) { Write-Log "추출됨: $p" 'OK' } else { Write-Log "ISO에 없음: $p" 'WARN' }
    }
}

# ---------------------------------------------------------------------------
# Win32
# ---------------------------------------------------------------------------
function Update-SystemCursors {
    if (Test-DryRun) { Write-Log '(dry-run) 커서 다시 불러오기 + 포인터 그림자 켜기' 'DRY'; return }
    if (-not ('W7Native' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class W7Native {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);
}
'@
    }
    $SPIF = 0x01 -bor 0x02  # UPDATEINIFILE | SENDCHANGE
    # SPI_SETCURSORSHADOW (0x101B): pvParam = TRUE
    [void][W7Native]::SystemParametersInfo(0x101B, 0, [IntPtr]1, $SPIF)
    # SPI_SETCURSORS (0x57): reload the cursor scheme from the registry
    [void][W7Native]::SystemParametersInfo(0x57, 0, [IntPtr]::Zero, $SPIF)
    Write-Log '커서를 다시 불러오고 포인터 그림자를 켰어요.' 'OK'
}
