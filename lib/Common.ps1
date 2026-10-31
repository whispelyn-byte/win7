# Common helpers: logging, state, backup-aware registry/file operations,
# downloads, user prompts, reboot/sign-out resume.
# Windows PowerShell 5.1 compatible. Save as UTF-8 with BOM.

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Globals (initialised by Initialize-Win7Look)
# ---------------------------------------------------------------------------
$script:W7 = @{
    Root        = $null   # repo root (where Install-Win7Look.ps1 lives)
    Assets      = $null   # assets dir
    Data        = 'C:\ProgramData\Win7Look'
    Work        = $null
    BackupDir   = $null
    LogFile     = $null
    StateFile   = $null
    Manifest    = $null   # backup manifest path
    ConfigPath  = $null
    DryRun      = $false
    NonInteractive = $false
    Config      = $null
    Steps       = New-Object System.Collections.ArrayList
    Win7        = $null   # paths of files extracted from Win7 ISO
}

function Initialize-Win7Look {
    param(
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] $Config,
        [switch] $DryRun,
        [switch] $NonInteractive
    )
    $W7.Root   = $Root
    $W7.Config = $Config
    $W7.DryRun = [bool]$DryRun
    $W7.NonInteractive = [bool]$NonInteractive

    $assets = $Config.assetsDir
    if (-not $assets) { $assets = 'assets' }
    if (-not [System.IO.Path]::IsPathRooted($assets)) { $assets = Join-Path $Root $assets }
    $W7.Assets = $assets

    $W7.Work      = Join-Path $W7.Data 'work'
    $W7.BackupDir = Join-Path $W7.Data 'backup'
    $W7.LogFile   = Join-Path $W7.Data 'install.log'
    $W7.StateFile = Join-Path $W7.Data 'state.json'
    $W7.Manifest  = Join-Path $W7.BackupDir 'manifest.jsonl'
    $W7.Win7      = Join-Path $W7.Work 'win7'

    foreach ($d in @($W7.Data, $W7.Work, $W7.BackupDir, $W7.Win7)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
function Write-Log {
    param([string] $Message, [ValidateSet('INFO','WARN','ERROR','OK','STEP','DRY')] [string] $Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    $color = switch ($Level) {
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
        'OK'    { 'Green' }
        'STEP'  { 'Cyan' }
        'DRY'   { 'DarkGray' }
        default { 'Gray' }
    }
    Write-Host $line -ForegroundColor $color
    if ($W7.LogFile) {
        try { Add-Content -Path $W7.LogFile -Value $line -Encoding UTF8 } catch { }
    }
}

function Test-DryRun { return [bool]$W7.DryRun }

# Run a scriptblock unless in dry-run mode.
function Invoke-Action {
    param([Parameter(Mandatory)] [string] $Description, [Parameter(Mandatory)] [scriptblock] $Action)
    if (Test-DryRun) { Write-Log "(dry-run) $Description" 'DRY'; return }
    Write-Log $Description
    & $Action
}

# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------
function Get-Cfg {
    param([Parameter(Mandatory)] [string] $Name, $Default = $null)
    $obj = $W7.Config
    foreach ($part in $Name.Split('.')) {
        if ($null -eq $obj) { return $Default }
        $prop = $obj.PSObject.Properties[$part]
        if ($null -eq $prop) { return $Default }
        $obj = $prop.Value
    }
    if ($null -eq $obj) { return $Default }
    return $obj
}

function Get-UiLanguage {
    $lang = Get-Cfg 'language' $null
    if (-not $lang) { $lang = (Get-UICulture).Name }
    return $lang
}

# ---------------------------------------------------------------------------
# State (completed steps) for resume after reboot / sign-out
# ---------------------------------------------------------------------------
function Get-State {
    if (Test-Path $W7.StateFile) {
        $s = Get-Content $W7.StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $done = @()
        if ($s.done) { $done = @($s.done) }
        return @{ done = $done }
    }
    return @{ done = @() }
}

function Save-State { param([hashtable] $State)
    if (Test-DryRun) { return }
    ($State | ConvertTo-Json -Depth 5) | Set-Content -Path $W7.StateFile -Encoding UTF8
}

function Set-StepDone { param([string] $Id)
    $s = Get-State
    if ($s.done -notcontains $Id) { $s.done += $Id }
    Save-State $s
}

# ---------------------------------------------------------------------------
# Step registry
# ---------------------------------------------------------------------------
# Kind: Auto | Semi (needs user clicks) | Manual (checklist only)
# After: None | Reboot | SignOut | RestartExplorer
function Register-Step {
    param(
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [int] $Order,
        [Parameter(Mandatory)] [string] $Title,
        [ValidateSet('Auto','Semi','Manual')] [string] $Kind = 'Auto',
        [ValidateSet('None','Reboot','SignOut','RestartExplorer')] [string] $After = 'None',
        [Parameter(Mandatory)] [scriptblock] $Run
    )
    [void]$W7.Steps.Add([pscustomobject]@{
        Id = $Id; Order = $Order; Title = $Title; Kind = $Kind; After = $After; Run = $Run
    })
}

# ---------------------------------------------------------------------------
# User interaction
# ---------------------------------------------------------------------------
function Wait-User {
    param([string[]] $Lines, [string] $Prompt = '완료했으면 Enter를 누르세요')
    Write-Host ''
    Write-Host '------------------------------------------------------------' -ForegroundColor Magenta
    foreach ($l in $Lines) { Write-Host ('  ' + $l) -ForegroundColor White }
    Write-Host '------------------------------------------------------------' -ForegroundColor Magenta
    if ((Test-DryRun) -or $W7.NonInteractive) { Write-Log '(사용자 입력 대기 생략)' 'DRY'; return }
    [void](Read-Host $Prompt)
}

function Confirm-User {
    param([string] $Question, [bool] $Default = $true)
    if ($W7.NonInteractive) { return $Default }
    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    $a = Read-Host "$Question $suffix"
    if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
    return ($a.Trim().ToLower() -in @('y','yes','ㅇ','ㅇㅇ','네','예'))
}

function Set-ClipboardText { param([string] $Text)
    if (Test-DryRun) { return }
    try { Set-Clipboard -Value $Text; Write-Log '클립보드에 복사했어요.' } catch { Write-Log "클립보드 복사 실패: $_" 'WARN' }
}

function Open-Url { param([string] $Url)
    Invoke-Action "열기: $Url" { Start-Process $Url }
}

# ---------------------------------------------------------------------------
# Backup manifest (used by -Rollback)
# ---------------------------------------------------------------------------
function Add-ManifestEntry { param([hashtable] $Entry)
    if (Test-DryRun) { return }
    $Entry.time = (Get-Date).ToString('o')
    Add-Content -Path $W7.Manifest -Value ($Entry | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8
}

function New-BackupPath { param([string] $Hint)
    $safe = ($Hint -replace '[\\/:*?"<>| ]', '_')
    if ($safe.Length -gt 80) { $safe = $safe.Substring($safe.Length - 80) }
    $name = '{0}_{1}' -f (Get-Date -Format 'yyyyMMddHHmmssfff'), $safe
    return Join-Path $W7.BackupDir $name
}

# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------
function ConvertTo-PsRegPath { param([string] $Path)
    $p = $Path -replace '^HKEY_LOCAL_MACHINE', 'HKLM:' -replace '^HKEY_CURRENT_USER', 'HKCU:' -replace '^HKEY_CLASSES_ROOT', 'HKCR:'
    $p = $p -replace '^HKLM\\', 'HKLM:\' -replace '^HKCU\\', 'HKCU:\' -replace '^HKCR\\', 'HKCR:\'
    if ($p -like 'HKCR:*' -and -not (Get-PSDrive -Name HKCR -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -Scope Global | Out-Null
    }
    return $p
}

# Set a registry value and record the previous state for rollback.
function Set-RegValue {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Name,   # '' = (Default)
        [Parameter(Mandatory)] [AllowEmptyString()] $Value,
        [ValidateSet('DWord','QWord','String','ExpandString','MultiString','Binary')] [string] $Type = 'DWord'
    )
    $ps = ConvertTo-PsRegPath $Path
    $label = if ($Name) { $Name } else { '(기본값)' }
    if (Test-DryRun) { Write-Log "(dry-run) reg $Path [$label] = $Value ($Type)" 'DRY'; return }

    $keyExisted = Test-Path $ps
    $prev = $null; $prevKind = $null; $valExisted = $false
    if ($keyExisted) {
        $k = Get-Item $ps
        if ($k.GetValueNames() -contains $Name) {
            $valExisted = $true
            $prev = $k.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
            $prevKind = $k.GetValueKind($Name).ToString()
        }
    } else {
        New-Item -Path $ps -Force | Out-Null
    }
    $psName = if ($Name) { $Name } else { '(default)' }
    New-ItemProperty -Path $ps -Name $psName -Value $Value -PropertyType $Type -Force | Out-Null
    Add-ManifestEntry @{ kind = 'reg'; path = $ps; name = $Name; keyExisted = $keyExisted; existed = $valExisted; prev = $prev; prevKind = $prevKind }
    Write-Log "reg $Path [$label] = $Value"
}

# Import a .reg file, exporting every key it touches first.
function Import-RegFile {
    param([Parameter(Mandatory)] [string] $File)
    if (-not (Test-Path $File)) { throw "레지스트리 파일 없음: $File" }
    $text = Get-Content $File -Raw
    $keys = [regex]::Matches($text, '(?m)^\[-?([^\]]+)\]') | ForEach-Object { $_.Groups[1].Value.Trim() } | Select-Object -Unique
    if (Test-DryRun) { Write-Log "(dry-run) reg import $File ($($keys.Count)개 키)" 'DRY'; return }
    foreach ($key in $keys) {
        $out = New-BackupPath ($key + '.reg')
        & reg.exe export $key $out /y 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Add-ManifestEntry @{ kind = 'regexport'; key = $key; file = $out }
        } else {
            Add-ManifestEntry @{ kind = 'regnewkey'; key = $key }
        }
    }
    & reg.exe import $File 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "reg import 실패: $File" }
    Write-Log "reg import $File" 'OK'
}

# Delete a registry key after exporting it (rollback re-imports the export).
function Remove-RegKeySafe {
    param([Parameter(Mandatory)] [string] $Key)
    & reg.exe query $Key 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { return }
    if (Test-DryRun) { Write-Log "(dry-run) reg 키 삭제 $Key" 'DRY'; return }
    $out = New-BackupPath ($Key + '.reg')
    & reg.exe export $Key $out /y 2>&1 | Out-Null
    Add-ManifestEntry @{ kind = 'regexport'; key = $Key; file = $out }
    & reg.exe delete $Key /f 2>&1 | Out-Null
    Write-Log "reg 키 삭제: $Key"
}

# Block a shell extension CLSID (removes context menu entries cleanly).
function Block-ShellExtension {
    param([Parameter(Mandatory)] [string] $Clsid, [string] $Label = '')
    Set-RegValue -Path 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked' -Name $Clsid -Value $Label -Type String
    Set-RegValue -Path 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked' -Name $Clsid -Value $Label -Type String
}

# ---------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------
# Take ownership of a protected system file/folder so Administrators can write.
function Grant-AdminAccess {
    param([Parameter(Mandatory)] [string] $Path, [switch] $Recurse)
    if (Test-DryRun) { return }
    $r = if ($Recurse) { @('/r', '/d', 'y') } else { @() }
    & takeown.exe /f $Path @r /a 2>&1 | Out-Null
    $ir = if ($Recurse) { @('/t') } else { @() }
    & icacls.exe $Path /grant '*S-1-5-32-544:F' @ir /c /q 2>&1 | Out-Null
}

# Copy one file, backing up the destination if it already exists.
function Copy-FileSafe {
    param([Parameter(Mandatory)] [string] $Source, [Parameter(Mandatory)] [string] $Destination)
    if (Test-DryRun) { Write-Log "(dry-run) copy $Source -> $Destination" 'DRY'; return }
    if (-not (Test-Path $Source)) { throw "원본 파일 없음: $Source" }
    $dir = Split-Path $Destination -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (Test-Path $Destination) {
        $bak = New-BackupPath $Destination
        Copy-Item -LiteralPath $Destination -Destination $bak -Force
        Add-ManifestEntry @{ kind = 'file'; path = $Destination; backup = $bak }
    } else {
        Add-ManifestEntry @{ kind = 'newfile'; path = $Destination }
    }
    try {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    } catch {
        # Only take ownership of the single protected file, never of a whole system folder
        if (-not (Test-Path -LiteralPath $Destination)) { throw }
        Write-Log "권한 부족, 소유권 가져온 뒤 재시도: $Destination" 'WARN'
        Grant-AdminAccess $Destination
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
}

# Copy the contents of a directory (recursive), backing up anything overwritten.
function Copy-DirSafe {
    param([Parameter(Mandatory)] [string] $Source, [Parameter(Mandatory)] [string] $Destination)
    if (-not (Test-Path $Source)) {
        if (Test-DryRun) { Write-Log "(dry-run) 폴더 복사 $Source -> $Destination (원본이 아직 없음)" 'DRY'; return }
        throw "원본 폴더 없음: $Source"
    }
    $src = (Resolve-Path $Source).Path.TrimEnd('\')
    $files = Get-ChildItem -LiteralPath $src -Recurse -File -Force
    Write-Log "폴더 복사: $src -> $Destination ($($files.Count)개 파일)"
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($src.Length).TrimStart('\')
        Copy-FileSafe -Source $f.FullName -Destination (Join-Path $Destination $rel)
    }
}

# Delete a file after backing it up.
function Remove-FileSafe {
    param([Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (Test-DryRun) { Write-Log "(dry-run) 삭제 $Path" 'DRY'; return }
    $bak = New-BackupPath $Path
    Copy-Item -LiteralPath $Path -Destination $bak -Force
    Add-ManifestEntry @{ kind = 'file'; path = $Path; backup = $bak }
    Remove-Item -LiteralPath $Path -Force
    Write-Log "삭제: $Path"
}

function New-Shortcut {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Target,
        [string] $Arguments = '',
        [string] $IconLocation = '',
        [string] $WorkingDirectory = ''
    )
    if (Test-DryRun) { Write-Log "(dry-run) 바로가기 $Path -> $Target $Arguments" 'DRY'; return }
    $sh = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut($Path)
    $lnk.TargetPath = $Target
    if ($Arguments) { $lnk.Arguments = $Arguments }
    if ($IconLocation) { $lnk.IconLocation = $IconLocation }
    if ($WorkingDirectory) { $lnk.WorkingDirectory = $WorkingDirectory }
    $lnk.Save()
    Add-ManifestEntry @{ kind = 'newfile'; path = $Path }
    Write-Log "바로가기 생성: $Path"
}

# ---------------------------------------------------------------------------
# Assets / downloads
# ---------------------------------------------------------------------------
# Find a file or folder under assets/ by wildcard, recursively. Returns $null if missing.
function Find-Asset {
    param([Parameter(Mandatory)] [string[]] $Pattern, [switch] $Directory, [string] $Under = '')
    $base = $W7.Assets
    if ($Under) { $base = Join-Path $base $Under }
    if (-not (Test-Path $base)) { return $null }
    foreach ($p in $Pattern) {
        if ($Directory) {
            $hit = Get-ChildItem -LiteralPath $base -Recurse -Directory -Filter $p -ErrorAction SilentlyContinue | Select-Object -First 1
        } else {
            $hit = Get-ChildItem -LiteralPath $base -Recurse -File -Filter $p -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Require-Asset {
    param([Parameter(Mandatory)] [string[]] $Pattern, [switch] $Directory, [string] $Under = '', [string] $Hint = '')
    $hit = Find-Asset -Pattern $Pattern -Directory:$Directory -Under $Under
    if ($hit) { return $hit }
    $msg = "에셋을 찾을 수 없음: $($Pattern -join ', ')" + $(if ($Under) { " (assets\$Under 아래)" } else { '' })
    if ($Hint) { $msg += " - $Hint" }
    if (Test-DryRun) { Write-Log $msg 'WARN'; return (Join-Path $W7.Assets ($Under + '\' + $Pattern[0])) }
    throw $msg
}

function Invoke-Download {
    param([Parameter(Mandatory)] [string] $Url, [Parameter(Mandatory)] [string] $OutFile)
    if (Test-Path $OutFile) { Write-Log "이미 받아둔 파일 사용: $OutFile"; return $OutFile }
    if (Test-DryRun) { Write-Log "(dry-run) 다운로드 $Url" 'DRY'; return $OutFile }
    $dir = Split-Path $OutFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Log "다운로드: $Url"
    $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
    try { Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -Headers @{ 'User-Agent' = 'Win7Look' } }
    finally { $ProgressPreference = $old }
    return $OutFile
}

# Pick a release asset from GitHub (latest release by default).
function Get-GitHubReleaseAsset {
    param([Parameter(Mandatory)] [string] $Repo, [Parameter(Mandatory)] [string] $NameLike, [string] $Tag = 'latest')
    if (Test-DryRun) { return "https://github.com/$Repo/releases/$Tag/$NameLike" }
    $api = if ($Tag -eq 'latest') { "https://api.github.com/repos/$Repo/releases/latest" } else { "https://api.github.com/repos/$Repo/releases/tags/$Tag" }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $rel = Invoke-RestMethod -Uri $api -UseBasicParsing -Headers @{ 'User-Agent' = 'Win7Look' }
    $a = $rel.assets | Where-Object { $_.name -like $NameLike } | Select-Object -First 1
    if (-not $a) { throw "$Repo 릴리스에서 '$NameLike' 파일을 찾지 못함" }
    return $a.browser_download_url
}

function Install-Winget {
    param([Parameter(Mandatory)] [string] $Id)
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'winget이 없어요. Microsoft Store에서 "앱 설치 관리자"를 업데이트하세요.' }
    Invoke-Action "winget 설치: $Id" {
        & winget.exe install --id $Id -e --accept-source-agreements --accept-package-agreements --silent 2>&1 | ForEach-Object { Write-Log $_ }
        # -1978335189 = already installed / no upgrade available
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { Write-Log "winget 종료 코드 $LASTEXITCODE ($Id)" 'WARN' }
    }
}

# Run an installer/program and wait.
function Start-Program {
    param([Parameter(Mandatory)] [string] $FilePath, [string[]] $ArgumentList = @(), [switch] $NoWait)
    if (Test-DryRun) { Write-Log "(dry-run) 실행: $FilePath $($ArgumentList -join ' ')" 'DRY'; return }
    Write-Log "실행: $FilePath $($ArgumentList -join ' ')"
    $p = @{ FilePath = $FilePath; PassThru = $true }
    if ($ArgumentList.Count -gt 0) { $p.ArgumentList = $ArgumentList }
    $proc = Start-Process @p
    $null = $proc.Handle   # cache the handle so ExitCode is available later
    if (-not $NoWait) { $proc.WaitForExit(); return $proc.ExitCode }
}

function Expand-Zip { param([string] $Zip, [string] $Dest)
    if (Test-DryRun) { Write-Log "(dry-run) 압축 해제 $Zip -> $Dest" 'DRY'; return }
    if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force }
    Expand-Archive -LiteralPath $Zip -DestinationPath $Dest -Force
}

# ---------------------------------------------------------------------------
# Explorer / session
# ---------------------------------------------------------------------------
function Restart-Explorer {
    Invoke-Action '탐색기 재시작' {
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
        Wait-ExplorerOrStart
    }
}

# Winlogon restarts a killed shell by itself (non-elevated). Only start it ourselves if that didn't happen.
function Wait-ExplorerOrStart {
    for ($i = 0; $i -lt 16; $i++) {
        Start-Sleep -Milliseconds 500
        if (Get-Process explorer -ErrorAction SilentlyContinue) { return }
    }
    Start-Process explorer.exe
}

function Clear-IconCache {
    Invoke-Action '아이콘 캐시 삭제' {
        $dir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 1
        # explorer may auto-restart; kill again right before deleting
        for ($i = 0; $i -lt 5; $i++) {
            Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
            Get-ChildItem $dir -Filter 'iconcache_*.db' -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Get-ChildItem $dir -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            $left = @(Get-ChildItem $dir -Filter 'iconcache_*.db' -Force -ErrorAction SilentlyContinue)
            if ($left.Count -eq 0) { break }
            Start-Sleep -Milliseconds 500
        }
        & ie4uinit.exe -show 2>$null
        Wait-ExplorerOrStart
    }
}

# Schedule this script to run again (elevated) at next logon of the current user.
function Register-Resume {
    $task = 'Win7Look-Resume'
    $script = Join-Path $W7.Root 'Install-Win7Look.ps1'
    $argStr = "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$script`" -Resume"
    if ($W7.ConfigPath) { $argStr += " -ConfigPath `"$($W7.ConfigPath)`"" }
    if (Test-DryRun) { Write-Log "(dry-run) 다음 로그온 때 이어서 실행 예약" 'DRY'; return }
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argStr
    $trigger   = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
    Write-Log '다음 로그온 때 자동으로 이어서 실행하도록 예약했어요.' 'OK'
}

function Unregister-Resume {
    if (Test-DryRun) { return }
    Unregister-ScheduledTask -TaskName 'Win7Look-Resume' -Confirm:$false -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Win7 ISO
# ---------------------------------------------------------------------------
function Get-SevenZip {
    $cands = @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe")
    foreach ($c in $cands) { if (Test-Path $c) { return $c } }
    return $null
}

function Mount-Win7Iso {
    $iso = Get-Cfg 'win7IsoPath' ''
    if (-not $iso) { $iso = Find-Asset -Pattern @('*.iso') }
    if (-not $iso -or -not (Test-Path $iso)) {
        if (Test-DryRun) { Write-Log 'Win7 ISO 경로가 없어요 (config.json의 win7IsoPath)' 'WARN'; return 'X:\' }
        throw 'Windows 7 ISO를 찾을 수 없어요. config.json의 win7IsoPath를 설정하세요.'
    }
    if (Test-DryRun) { Write-Log "(dry-run) ISO 마운트 $iso" 'DRY'; return 'X:\' }
    $img = Get-DiskImage -ImagePath $iso
    if (-not $img.Attached) { $img = Mount-DiskImage -ImagePath $iso -PassThru; Start-Sleep -Seconds 2 }
    $vol = Get-DiskImage -ImagePath $iso | Get-Volume
    if (-not $vol.DriveLetter) { throw "ISO는 마운트됐는데 드라이브 문자를 못 찾았어요: $iso" }
    return ($vol.DriveLetter + ':\')
}

function Get-Win7File { param([Parameter(Mandatory)] [string] $RelativePath)
    # Path relative to the extracted image root, e.g. 'Windows\System32\shell32.dll'
    return (Join-Path $W7.Win7 $RelativePath)
}
