<#
  Cài ứng dụng bằng winget (nguồn winget của Microsoft; winget kiểm mã băm bộ cài theo manifest).
  Cách làm theo công cụ bo-ung-dung của Trạm Tool: đọc lại danh sách đã cài thay vì tin mã thoát của bộ cài.
#>

$script:WingetCommon = @('--source', 'winget', '--accept-source-agreements', '--disable-interactivity')
$script:WgNotFound = -1978335212       # 0x8A150014: không thấy ứng dụng (winget list)
$script:WgReboot = -1978334967         # 0x8A150109: cài xong, cần khởi động lại
$script:WgAlready = -1978335135        # 0x8A150061: đã cài
$script:WgFamily = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe'

function Get-WingetPath {
    # Đường dẫn winget.exe; $null khi máy chưa có. Bài thử đặt AUTOSETUP_WINGET (file giả).
    if ($env:AUTOSETUP_WINGET) { return $env:AUTOSETUP_WINGET }
    $c = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path -LiteralPath $alias) { return $alias }
    # Cửa sổ Admin có khi không thấy alias của tài khoản: dùng thẳng bản trong WindowsApps (bản mới nhất).
    $pkg = Get-ChildItem -Path "$env:ProgramFiles\WindowsApps" -Filter 'Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe' -Directory -ErrorAction SilentlyContinue |
        Sort-Object { try { [version]($_.Name.Split('_')[1]) } catch { [version]'0.0' } } -Descending | Select-Object -First 1
    if ($pkg -and (Test-Path -LiteralPath (Join-Path $pkg.FullName 'winget.exe'))) { return (Join-Path $pkg.FullName 'winget.exe') }
    return $null
}

function Invoke-Winget {
    # Chạy winget trong cùng cửa sổ (thấy tiến trình tải, cài), trả mã thoát.
    param([string[]]$Arguments)
    $text = ($Arguments | ForEach-Object { if ($_ -match '\s') { '"{0}"' -f $_ } else { $_ } }) -join ' '
    $p = Start-Process -FilePath (Get-WingetPath) -ArgumentList $text -NoNewWindow -Wait -PassThru
    try { return [int]$p.ExitCode } catch { return 1 }
}

function Invoke-WingetQuiet {
    # Chạy winget không in ra, trả @{ Code; Text }.
    param([string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    $out = & (Get-WingetPath) @Arguments 2>&1
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ((@($out) | ForEach-Object { [string]$_ }) -join "`n") }
}

function Initialize-Winget {
    # Bảo đảm winget chạy được: đăng ký App Installer cho tài khoản (máy mới cài hay thiếu), cập nhật nguồn.
    # Trả @{ Ok; GhiChu }.
    param([int]$WaitSeconds = 300)
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $registered = $false
    while ($true) {
        $wg = Get-WingetPath
        if ($wg) {
            $v = Invoke-WingetQuiet @('--version')
            if ($v.Code -eq 0) {
                Write-Ok "winget $($v.Text.Trim())"
                $s = Invoke-WingetQuiet @('source', 'update', '--name', 'winget')
                if ($s.Code -ne 0) { Write-Warn "winget source update mã $(Format-ExitCode $s.Code) (vẫn thử cài)." }
                return [pscustomobject]@{ Ok = $true; GhiChu = "winget $($v.Text.Trim())" }
            }
        }
        if (-not $registered) {
            Write-Info 'Đăng ký App Installer (winget) cho tài khoản này...'
            try { Add-AppxPackage -RegisterByFamilyName -MainPackage $script:WgFamily -ErrorAction Stop } catch { Write-Warn "Đăng ký App Installer lỗi: $($_.Exception.Message.Trim())" }
            $registered = $true
            continue
        }
        if ((Get-Date) -gt $deadline) { break }
        Write-Info 'Chờ winget sẵn sàng (Windows đang cập nhật App Installer)...'
        Start-Sleep -Seconds 15
    }
    # Hết cách nhẹ: Repair-WinGetPackageManager (module Microsoft.WinGet.Client, cần mạng).
    try {
        Write-Info 'Thử sửa winget bằng Repair-WinGetPackageManager (tải từ PowerShell Gallery)...'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge [version]'2.8.5.201' })) {
            [void](Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop)
        }
        Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
        Import-Module Microsoft.WinGet.Client -Force -ErrorAction Stop
        Repair-WinGetPackageManager -Latest -Force -ErrorAction Stop | Out-Null
        if (Get-WingetPath) {
            $v = Invoke-WingetQuiet @('--version')
            if ($v.Code -eq 0) { return [pscustomobject]@{ Ok = $true; GhiChu = "winget $($v.Text.Trim()) (đã sửa)" } }
        }
    } catch { Write-Warn "Không sửa được winget: $($_.Exception.Message.Trim())" }
    return [pscustomobject]@{ Ok = $false; GhiChu = 'winget không chạy được (thiếu App Installer hoặc chưa có mạng).' }
}

function Read-AppList {
    param([Parameter(Mandatory)][string]$Path)
    $j = Read-JsonFile $Path
    $list = @($j.ungDung | Where-Object { $_.khoa -and $_.id })
    if (-not $list.Count) { throw "Danh sách ứng dụng $Path không có ứng dụng nào." }
    return , $list
}

function Select-Apps {
    # Ứng dụng sẽ cài: macDinh = true; trong một nhóm chỉ lấy cái đứng trước. Trả @{ Chon; BoQua }.
    param([object[]]$Apps)
    $chosen = @(); $skipped = @(); $groups = @{}
    foreach ($a in $Apps) {
        if ($a.macDinh -ne $true) { continue }
        $g = [string]$a.nhom
        if ($g) {
            if ($groups.ContainsKey($g)) { $skipped += [pscustomobject]@{ App = $a; LyDo = "cùng nhóm với $($groups[$g])" }; continue }
            $groups[$g] = $a.ten
        }
        $chosen += $a
    }
    return [pscustomobject]@{ Chon = $chosen; BoQua = $skipped }
}

function Test-AppInstalled {
    param([string]$Id)
    $r = Invoke-WingetQuiet (@('list', '--id', $Id, '-e') + $script:WingetCommon)
    return ($r.Code -eq 0)
}

function Install-Apps {
    # Cài từng ứng dụng; đã có thì bỏ qua; lỗi thì thử lại một lần. Trả danh sách kết quả từng ứng dụng.
    param([object[]]$Apps, [string]$InstallRoot = '', [switch]$DryRun)
    $results = @()
    foreach ($a in $Apps) {
        $r = [ordered]@{ khoa = $a.khoa; ten = $a.ten; id = $a.id; ketQua = ''; ma = 0; ghiChu = '' }
        if (Test-AppInstalled $a.id) { Write-Ok "Đã có: $($a.ten)"; $r.ketQua = 'da-co'; $results += [pscustomobject]$r; continue }
        $wgArgs = @('install', '--id', $a.id, '-e', '--silent', '--accept-package-agreements') + $script:WingetCommon
        if ($InstallRoot -and $a.doiThuMuc -eq $true) { $wgArgs += @('--location', (Join-Path $InstallRoot $a.khoa)) }
        if ($DryRun) { Write-Plan ("{0}   winget {1}" -f $a.ten, ($wgArgs -join ' ')); $r.ketQua = 'chay-thu'; $results += [pscustomobject]$r; continue }
        $code = 0
        for ($try = 1; $try -le 2; $try++) {
            Write-Line ''
            Write-Line ("Đang cài {0}{1}..." -f $a.ten, $(if ($try -gt 1) { ' (lần 2)' }))
            $code = Invoke-Winget $wgArgs
            if ($code -in 0, $script:WgReboot, $script:WgAlready) { break }
            if (Test-AppInstalled $a.id) { break }
            Start-Sleep -Seconds 5
        }
        $r.ma = $code
        if (Test-AppInstalled $a.id) {
            $r.ketQua = 'da-cai'
            if ($code -eq $script:WgReboot) { $r.ghiChu = 'cần khởi động lại để cài xong' }
            elseif ($code -ne 0) { $r.ghiChu = "winget báo mã $(Format-ExitCode $code) nhưng ứng dụng đã có trong danh sách đã cài" }
            Write-Ok "Đã cài $($a.ten)"
        } else {
            $r.ketQua = 'loi'
            $r.ghiChu = "winget install mã $(Format-ExitCode $code)"
            Write-Bad "Chưa cài được $($a.ten): $($r.ghiChu)"
        }
        $results += [pscustomobject]$r
    }
    return , $results
}
