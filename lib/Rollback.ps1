# Undo registry and file changes recorded in backup\manifest.jsonl (newest first).
# Installed programs (Windhawk, ExplorerPatcher, Firefox, ...) are NOT uninstalled.

function Invoke-Rollback {
    if (-not (Test-Path $W7.Manifest)) { Write-Log '되돌릴 기록이 없어요.' 'WARN'; return }
    $entries = @(Get-Content $W7.Manifest -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
    [array]::Reverse($entries)
    Write-Log "되돌리기: $($entries.Count)개 항목" 'STEP'
    if (Test-DryRun) {
        foreach ($e in $entries) { Write-Log ("(dry-run) 되돌릴 항목: {0} {1}{2}{3}" -f $e.kind, $e.path, $e.key, $(if ($e.name) { " [$($e.name)]" } else { '' })) 'DRY' }
        return
    }
    if (-not (Confirm-User '레지스트리/파일 변경을 모두 되돌릴까요? (설치한 프로그램은 그대로 둬요)' $false)) { return }

    foreach ($e in $entries) {
        try {
            switch ($e.kind) {
                'reg' {
                    $ps = $e.path
                    if ($ps -like 'HKCR:*' -and -not (Get-PSDrive -Name HKCR -ErrorAction SilentlyContinue)) {
                        New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT | Out-Null
                    }
                    $name = if ($e.name) { $e.name } else { '(default)' }
                    if (-not $e.keyExisted) {
                        if (Test-Path $ps) { Remove-Item $ps -Recurse -Force }
                    } elseif ($e.existed) {
                        Invoke-Action "reg 복원 $ps [$name]" { New-ItemProperty -Path $ps -Name $name -Value $e.prev -PropertyType $e.prevKind -Force | Out-Null }
                    } else {
                        if (Test-Path $ps) { Remove-ItemProperty -Path $ps -Name $name -ErrorAction SilentlyContinue }
                    }
                }
                'regexport' {
                    Invoke-Action "reg 복원 $($e.key)" {
                        & reg.exe delete $e.key /f 2>&1 | Out-Null
                        & reg.exe import $e.file 2>&1 | Out-Null
                    }
                }
                'regnewkey' {
                    Invoke-Action "reg 키 삭제 $($e.key)" { & reg.exe delete $e.key /f 2>&1 | Out-Null }
                }
                'file' {
                    Invoke-Action "파일 복원 $($e.path)" {
                        try { Copy-Item -LiteralPath $e.backup -Destination $e.path -Force }
                        catch { Grant-AdminAccess $e.path; Copy-Item -LiteralPath $e.backup -Destination $e.path -Force }
                    }
                }
                'newfile' {
                    Invoke-Action "추가된 파일 삭제 $($e.path)" {
                        if (Test-Path -LiteralPath $e.path) {
                            try { Remove-Item -LiteralPath $e.path -Force }
                            catch { Grant-AdminAccess $e.path; Remove-Item -LiteralPath $e.path -Force }
                        }
                    }
                }
                'task' {
                    Invoke-Action "예약 작업 삭제 $($e.name)" { Unregister-ScheduledTask -TaskName $e.name -Confirm:$false -ErrorAction SilentlyContinue }
                }
            }
        } catch {
            Write-Log "되돌리기 실패 ($($e.kind)): $_" 'WARN'
        }
    }
    if (-not (Test-DryRun)) {
        Move-Item $W7.Manifest ($W7.Manifest + '.rolledback-' + (Get-Date -Format 'yyyyMMddHHmmss')) -Force
        if (Test-Path $W7.StateFile) { Remove-Item $W7.StateFile -Force }
    }
    Write-Log '되돌리기 끝. 재부팅하세요. 설치한 프로그램은 "설정 > 앱"에서 직접 제거하세요.' 'OK'
}
