<#
  Hàm dùng chung cho bài thử: so sánh, thư mục tạm (ngoài repo, trong %TEMP%\AutoSetup-KiemThu), kết thúc bài.
#>
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:Fails = 0
$script:Passes = 0

function Assert-True {
    param($Condition, [string]$Message)
    if ($Condition) { $script:Passes++; Write-Host "  ok    $Message" -ForegroundColor DarkGray }
    else { $script:Fails++; Write-Host "  HỎNG  $Message" -ForegroundColor Red }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    $ok = ([string]$Expected -ceq [string]$Actual)
    if ($ok) { Assert-True $true $Message } else { Assert-True $false "$Message (cần '$Expected', được '$Actual')" }
}

function New-TestDir {
    param([string]$Name)
    $base = Join-Path ([IO.Path]::GetTempPath()) 'AutoSetup-KiemThu'
    $d = Join-Path $base ('{0}-{1}' -f $Name, [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    return $d
}

function Remove-TestDir {
    param([string]$Path)
    if ($Path -and $Path -like '*AutoSetup-KiemThu*' -and (Test-Path -LiteralPath $Path)) { Remove-Item -LiteralPath $Path -Recurse -Force }
}

function Invoke-Ps {
    # Chạy một script PowerShell trong tiến trình riêng; trả @{ Code; Text }.
    param([string]$File, [string[]]$Arguments = @())
    $all = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $File) + $Arguments
    $out = & powershell.exe @all 2>&1
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ((@($out) | ForEach-Object { [string]$_ }) -join "`n") }
}

function Complete-Test {
    Write-Host ("  {0} đạt, {1} hỏng" -f $script:Passes, $script:Fails)
    if ($script:Fails) { exit 1 }
    exit 0
}
