<#
  Driver và cập nhật Windows:
    - nạp driver để sẵn trên USB (\AutoSetup\drivers, các file .inf trong mọi thư mục con) bằng pnputil;
    - tải driver còn thiếu (và bản cập nhật Windows nếu bật) qua Windows Update Agent (COM), không dùng nguồn ngoài.
#>

function Get-ProblemDevices {
    # Thiết bị đang báo lỗi hoặc thiếu driver.
    try {
        return @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object { $_.Status -in 'Error', 'Degraded', 'Unknown' } |
            ForEach-Object { [pscustomobject]@{ ten = [string]$_.FriendlyName; lop = [string]$_.Class; ma = [string]$_.InstanceId; trangThai = [string]$_.Status } })
    } catch { return @() }
}

function Install-UsbDrivers {
    # pnputil /add-driver <thư mục>\*.inf /subdirs /install. Trả @{ TrangThai; GhiChu; KhoiDongLai }.
    param([string]$Folder, [switch]$DryRun)
    $infs = @(Get-ChildItem -LiteralPath $Folder -Filter '*.inf' -File -Recurse -ErrorAction SilentlyContinue)
    if (-not $infs.Count) { return [pscustomobject]@{ TrangThai = 'bo-qua'; GhiChu = "không có file .inf trong $Folder"; KhoiDongLai = $false } }
    Write-Info ("Nạp {0} driver từ {1}" -f $infs.Count, $Folder)
    if ($DryRun) { Write-Plan "pnputil /add-driver `"$Folder\*.inf`" /subdirs /install"; return [pscustomobject]@{ TrangThai = 'chay-thu'; GhiChu = ''; KhoiDongLai = $false } }
    $out = & pnputil.exe /add-driver (Join-Path $Folder '*.inf') /subdirs /install 2>&1
    $code = $LASTEXITCODE
    $added = @($out | Where-Object { $_ -match 'Added driver packages|Đã thêm|added' }) -join ' '
    # 0: xong; 3010: xong, cần khởi động lại; 259: không có driver nào hợp thiết bị (không phải lỗi).
    switch ($code) {
        0 { return [pscustomobject]@{ TrangThai = 'xong'; GhiChu = "pnputil xong. $added".Trim(); KhoiDongLai = $false } }
        3010 { return [pscustomobject]@{ TrangThai = 'xong'; GhiChu = "pnputil xong, cần khởi động lại. $added".Trim(); KhoiDongLai = $true } }
        259 { return [pscustomobject]@{ TrangThai = 'xong'; GhiChu = 'Driver trên USB không hợp thiết bị nào của máy này.'; KhoiDongLai = $false } }
        default { return [pscustomobject]@{ TrangThai = 'loi'; GhiChu = "pnputil mã $code"; KhoiDongLai = $false } }
    }
}

function Invoke-WindowsUpdate {
    # Tìm, tải, cài bản cập nhật qua Windows Update. $Kind: Driver hoặc Software.
    # Trả @{ TrangThai (xong|loi|chay-thu); DaCai (tên); Loi (tên); KhoiDongLai; GhiChu }.
    param([ValidateSet('Driver', 'Software')][string]$Kind, [switch]$DryRun)
    $res = [pscustomobject]@{ TrangThai = 'xong'; DaCai = @(); Loi = @(); KhoiDongLai = $false; GhiChu = '' }
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $session.ClientApplicationID = 'AutoSetup_Win'
        $searcher = $session.CreateUpdateSearcher()
        Write-Info ("Tìm {0} trên Windows Update (có thể mất vài phút)..." -f $(if ($Kind -eq 'Driver') { 'driver' } else { 'bản cập nhật' }))
        $found = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='$Kind'")
        $list = @()
        foreach ($u in $found.Updates) { $list += $u }
        if (-not $list.Count) { $res.GhiChu = 'Không còn gì cần cài.'; Write-Ok $res.GhiChu; return $res }
        foreach ($u in $list) { Write-Plan $u.Title }
        if ($DryRun) { $res.TrangThai = 'chay-thu'; return $res }
        $coll = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $list) { if (-not $u.EulaAccepted) { $u.AcceptEula() }; [void]$coll.Add($u) }
        Write-Info "Tải $($coll.Count) mục..."
        $dl = $session.CreateUpdateDownloader()
        $dl.Updates = $coll
        [void]$dl.Download()
        Write-Info 'Cài...'
        $inst = $session.CreateUpdateInstaller()
        $inst.Updates = $coll
        $r = $inst.Install()
        for ($i = 0; $i -lt $coll.Count; $i++) {
            $code = $r.GetUpdateResult($i).ResultCode   # 2 xong, 3 xong có lỗi phụ, 4 lỗi, 5 huỷ
            if ($code -in 2, 3) { $res.DaCai += $coll.Item($i).Title } else { $res.Loi += $coll.Item($i).Title }
        }
        $res.KhoiDongLai = [bool]$r.RebootRequired
        if ($res.Loi.Count) { $res.TrangThai = 'loi'; $res.GhiChu = "Cài lỗi $($res.Loi.Count) mục." }
        else { $res.GhiChu = "Đã cài $($res.DaCai.Count) mục." }
    } catch {
        $res.TrangThai = 'loi'
        $res.GhiChu = 'Windows Update lỗi: ' + $_.Exception.Message.Trim()
    }
    return $res
}
