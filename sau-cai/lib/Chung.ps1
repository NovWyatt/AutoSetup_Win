<#
  Hàm dùng chung: in ra màn hình, hỏi, quyền Admin, tìm USB AutoSetup.
#>

function Write-Head { param([string]$Text) Write-Host ''; Write-Host ("== $Text " + ('=' * [Math]::Max(3, 68 - $Text.Length))) -ForegroundColor Cyan }
function Write-Line { param([string]$Text) Write-Host "  $Text" }
function Write-Sub { param([string]$Text) Write-Host "       $Text" -ForegroundColor Gray }
function Write-Ok { param([string]$Text) Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "  [!]  $Text" -ForegroundColor Yellow }
function Write-Bad { param([string]$Text) Write-Host "  [X]  $Text" -ForegroundColor Red }
function Write-Info { param([string]$Text) Write-Host "  [i]  $Text" -ForegroundColor Gray }
function Write-Plan { param([string]$Text) Write-Host "   ->  $Text" -ForegroundColor White }

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Read-YesNo {
    # Không có bàn phím (chạy tự động) thì trả mặc định thay vì treo.
    param([string]$Question, [bool]$Default = $false)
    if ([Console]::IsInputRedirected) { return $Default }
    $hint = if ($Default) { '[C/k]' } else { '[c/K]' }
    while ($true) {
        $a = ([string](Read-Host "  $Question $hint")).Trim().ToLowerInvariant()
        if (-not $a) { return $Default }
        if ($a -in 'c', 'co', 'có', 'y', 'yes') { return $true }
        if ($a -in 'k', 'khong', 'không', 'n', 'no') { return $false }
        Write-Host '  Gõ C (có) hoặc K (không).' -ForegroundColor Yellow
    }
}

function Find-UsbRoot {
    # Gốc ổ có \AutoSetup\sau-cai\SauCai.ps1, bỏ qua ổ Windows. Bài thử đặt AUTOSETUP_USB để chỉ định. Không có thì $null.
    if ($env:AUTOSETUP_USB) {
        if (Test-Path -LiteralPath (Join-Path $env:AUTOSETUP_USB 'AutoSetup\sau-cai\SauCai.ps1')) { return $env:AUTOSETUP_USB.TrimEnd('\') }
        return $null
    }
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $r = $d.Root
        if (-not $r -or $r -like "$env:SystemDrive*") { continue }
        if (Test-Path -LiteralPath (Join-Path $r 'AutoSetup\sau-cai\SauCai.ps1')) { return $r.TrimEnd('\') }
    }
    return $null
}

function Format-ExitCode {
    # Mã thoát kèm dạng hex (mã của winget, Windows Update là số âm 0x8A15...).
    param([int]$Code)
    if ($Code -lt 0 -or $Code -gt 0xFFFF) { return ('{0} (0x{1:X8})' -f $Code, $Code) }
    return [string]$Code
}
