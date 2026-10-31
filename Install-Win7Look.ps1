<#
.SYNOPSIS
    Windows 11 -> Windows 7 look automation (based on note.com/rg0 guide).

.DESCRIPTION
    Runs the steps in steps\*.ps1 in order. Progress is saved in
    C:\ProgramData\Win7Look\state.json, so after a reboot or sign-out the
    script resumes automatically (a one-shot scheduled task re-launches it).

.EXAMPLE
    .\Install-Win7Look.ps1                 # run everything not yet done
    .\Install-Win7Look.ps1 -List           # list steps and status
    .\Install-Win7Look.ps1 -DryRun         # show what would happen
    .\Install-Win7Look.ps1 -Only firefox-ie,sounds
    .\Install-Win7Look.ps1 -Skip openglass
    .\Install-Win7Look.ps1 -Redo aero11-theme
    .\Install-Win7Look.ps1 -Rollback       # undo registry / file changes
#>
[CmdletBinding()]
param(
    [string]   $ConfigPath,
    [string[]] $Only,
    [string[]] $Skip,
    [string[]] $Redo,
    [switch]   $DryRun,
    [switch]   $Resume,
    [switch]   $List,
    [switch]   $Rollback,
    [switch]   $NonInteractive,
    [switch]   $Reset
)

$ErrorActionPreference = 'Stop'
# With -File, "a,b" arrives as one string: split it.
$Only = @($Only | Where-Object { $_ } | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() })
$Skip = @($Skip | Where-Object { $_ } | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() })
$Redo = @($Redo | Where-Object { $_ } | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() })
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- self-elevate -----------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $List -and -not $DryRun) {
    Write-Host '관리자 권한으로 다시 실행합니다...' -ForegroundColor Yellow
    $argList = @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($MyInvocation.MyCommand.Path)`"")
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) { if ($kv.Value.IsPresent) { $argList += "-$($kv.Key)" } }
        elseif ($kv.Value -is [array]) { $argList += "-$($kv.Key)"; $argList += ($kv.Value -join ',') }
        else { $argList += "-$($kv.Key)"; $argList += "`"$($kv.Value)`"" }
    }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    return
}

. (Join-Path $Root 'lib\Common.ps1')
. (Join-Path $Root 'lib\Tools.ps1')
. (Join-Path $Root 'lib\Rollback.ps1')

# --- config -----------------------------------------------------------------
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $Root 'config.json'
    if (-not (Test-Path $ConfigPath)) {
        Copy-Item (Join-Path $Root 'config.example.json') $ConfigPath
        Write-Host "config.json이 없어서 예제를 복사했어요: $ConfigPath" -ForegroundColor Yellow
        Write-Host 'win7IsoPath 등을 확인한 뒤 다시 실행하세요.' -ForegroundColor Yellow
        if (-not $List -and -not $DryRun) { return }
    }
}
$Config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

Initialize-Win7Look -Root $Root -Config $Config -DryRun:$DryRun -NonInteractive:$NonInteractive
$W7.ConfigPath = $ConfigPath

if ($Rollback) { Invoke-Rollback; return }

if ($Reset) {
    if (Test-Path $W7.StateFile) { Remove-Item $W7.StateFile -Force }
    Write-Log '진행 상태를 초기화했어요.' 'OK'
}

# --- load steps -------------------------------------------------------------
foreach ($stepFile in (Get-ChildItem (Join-Path $Root 'steps') -Filter '*.ps1' | Sort-Object Name)) { . $stepFile.FullName }
$steps = @($W7.Steps | Sort-Object Order)

$state = Get-State
foreach ($r in @($Redo)) { if ($r) { $state.done = @($state.done | Where-Object { $_ -ne $r }) } }
if ($Redo.Count -gt 0) { Save-State $state }

function Test-StepEnabled { param($Step)
    if ($Only.Count -gt 0 -and ($Only -notcontains $Step.Id)) { return $false }
    if ($Skip.Count -gt 0 -and ($Skip -contains $Step.Id)) { return $false }
    $flag = Get-Cfg ("steps." + $Step.Id) $true
    return [bool]$flag
}

if ($List) {
    Write-Host ''
    Write-Host ('{0,-4} {1,-26} {2,-7} {3,-16} {4,-6} {5}' -f '#', 'ID', '종류', '이후', '상태', '설명')
    foreach ($s in $steps) {
        $st = if ($state.done -contains $s.Id) { '완료' } elseif (-not (Test-StepEnabled $s)) { '끔' } else { '대기' }
        Write-Host ('{0,-4} {1,-26} {2,-7} {3,-16} {4,-6} {5}' -f $s.Order, $s.Id, $s.Kind, $s.After, $st, $s.Title)
    }
    return
}

if ($Resume) { Unregister-Resume; Write-Log '재부팅/로그아웃 후 이어서 진행합니다.' 'STEP' }

Write-Log "Win7Look 시작 (DryRun=$([bool]$DryRun), 언어=$(Get-UiLanguage))" 'STEP'

foreach ($s in $steps) {
    if (-not (Test-StepEnabled $s)) { continue }
    if ($state.done -contains $s.Id) { continue }

    Write-Host ''
    Write-Log ("[{0}] {1}  ({2})" -f $s.Id, $s.Title, $s.Kind) 'STEP'
    try {
        & $s.Run
    } catch {
        Write-Log "단계 실패: $($s.Id) - $($_.Exception.Message)" 'ERROR'
        Write-Log $_.ScriptStackTrace 'ERROR'
        if (-not $NonInteractive -and -not $DryRun -and (Confirm-User '이 단계를 건너뛰고 계속할까요?' $false)) {
            Write-Log "건너뜀: $($s.Id)" 'WARN'
            continue
        }
        Write-Log "문제를 해결한 뒤 다시 실행하면 이 단계부터 이어서 합니다. 로그: $($W7.LogFile)" 'ERROR'
        return
    }
    Set-StepDone $s.Id
    Write-Log "완료: $($s.Id)" 'OK'

    switch ($s.After) {
        'RestartExplorer' { Restart-Explorer }
        'Reboot' {
            $remaining = @($steps | Where-Object { (Test-StepEnabled $_) -and ((Get-State).done -notcontains $_.Id) })
            if ($remaining.Count -eq 0 -and -not $DryRun) { break }
            Register-Resume
            if ($DryRun) { Write-Log '(dry-run) 여기서 재부팅' 'DRY'; continue }
            if ((Get-Cfg 'autoReboot' $false) -or (Confirm-User '재부팅이 필요해요. 지금 재부팅할까요?' $true)) {
                Restart-Computer -Force
            } else {
                Write-Log '직접 재부팅하면 로그온 후 자동으로 이어서 진행돼요.' 'WARN'
            }
            return
        }
        'SignOut' {
            Register-Resume
            if ($DryRun) { Write-Log '(dry-run) 여기서 로그아웃' 'DRY'; continue }
            if ((Get-Cfg 'autoReboot' $false) -or (Confirm-User '로그아웃이 필요해요. 지금 로그아웃할까요?' $true)) {
                & shutdown.exe /l
            } else {
                Write-Log '직접 로그아웃하면 다시 로그인한 뒤 자동으로 이어서 진행돼요.' 'WARN'
            }
            return
        }
    }
}

Write-Host ''
Write-Log '모든 단계가 끝났어요! 한 번 재부팅하는 걸 추천해요.' 'OK'
Write-Log "백업/로그 위치: $($W7.Data)" 'OK'
