<#
  Bước kiểm tra ổ trong WinPE: chạy đúng các lệnh echo lấy từ file unattend đã sinh để dựng lại KiemTraO.vbs (bắt lỗi
  ký tự cmd), so với file gốc, rồi chạy nó bằng cscript với danh sách ổ giả (AUTOSETUP_TEST_DISKS).
#>
. (Join-Path $PSScriptRoot 'lib\KiemThu.ps1')

$d = New-TestDir 'kiemtrao'
try {
    $out = Join-Path $d 'unattend'
    $r = Invoke-Ps (Join-Path $script:Repo 'scripts\TaoUnattend.ps1') @('-Ra', $out, '-KhongDung')
    Assert-Equal 0 $r.Code 'sinh file unattend'
    $x = New-Object Xml.XmlDocument
    $x.Load((Join-Path $out '5_XOA-SACH-o_chia-C-D.xml'))
    $ns = New-Object Xml.XmlNamespaceManager $x.NameTable
    $ns.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
    $paths = @($x.SelectNodes("//u:settings[@pass='windowsPE']//u:RunSynchronousCommand/u:Path", $ns) | ForEach-Object { $_.InnerText })
    $vbs = Join-Path $d 'kt.vbs'
    $echo = @($paths | Where-Object { $_ -like '*X:\as-kt.vbs echo *' })
    Assert-True ($echo[0] -like 'cmd.exe /c ">X:\as-kt.vbs echo *') 'lệnh đầu ghi mới file (>)'
    Assert-True (-not @($echo | Select-Object -Skip 1 | Where-Object { $_ -notlike 'cmd.exe /c ">>X:\as-kt.vbs echo *' }).Count) 'các lệnh sau ghi nối (>>)'
    foreach ($p in $echo) {
        $psi = New-Object Diagnostics.ProcessStartInfo 'cmd.exe', ($p.Substring('cmd.exe '.Length).Replace('X:\as-kt.vbs', $vbs))
        $psi.UseShellExecute = $false
        $pr = [Diagnostics.Process]::Start($psi)
        $pr.WaitForExit()
    }
    $src = @(Get-Content -LiteralPath (Join-Path $script:Repo 'unattend\KiemTraO.vbs') -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("'") })
    $got = @(Get-Content -LiteralPath $vbs)
    Assert-Equal $src.Count $got.Count 'dựng lại đủ số dòng'
    $diff = @(Compare-Object $src $got -SyncWindow 0 -CaseSensitive)
    Assert-True (-not $diff.Count) ('dựng lại giống hệt file gốc' + $(if ($diff.Count) { ": $($diff[0].InputObject)" }))

    function Test-Guard {
        param([string]$Disks, [string]$Firmware, [string]$Target, [string]$MinGB, [int]$Expect, [string]$Name)
        $env:AUTOSETUP_TEST_DISKS = $Disks
        $env:AUTOSETUP_TEST_FIRMWARE = $Firmware
        $o = & cscript.exe //nologo //E:vbscript $vbs $Target $MinGB
        $code = $LASTEXITCODE
        Assert-Equal $Expect $code "$Name -> $(($o -join ' ').Trim())"
    }
    $nvme = '0/SCSI/Fixed hard disk media/256'
    Test-Guard $nvme '2' '0' '60' 0 'một ổ NVMe, UEFI: cho xoá'
    Test-Guard "$nvme;1/USB/Removable Media/32" '2' '0' '60' 0 'một ổ trong + USB Ventoy: cho xoá ổ trong'
    Test-Guard "1/USB/Removable Media/32;$nvme" '2' '0' '60' 0 'USB đứng trước vẫn chọn đúng ổ trong'
    Test-Guard "$nvme;2/SCSI/Removable Media/64" '2' '0' '170' 0 'thẻ nhớ không tính là ổ trong'
    Test-Guard '0/SCSI/Fixed hard disk media/238;1/SCSI/Fixed hard disk media/238' '2' '0' '60' 1 'hai ổ trong (như máy 2 SSD): chặn'
    Test-Guard "$nvme;1/IDE/Fixed hard disk media/1000" '2' '0' '60' 1 'SSD + HDD: chặn'
    Test-Guard "$nvme;1/USB/Removable Media/32" '2' '1' '60' 1 'ổ được chọn là USB: chặn'
    Test-Guard $nvme '1' '0' '60' 1 'Legacy BIOS: chặn'
    Test-Guard $nvme '' '0' '60' 1 'không đọc được kiểu firmware: chặn'
    Test-Guard '0/SCSI/Fixed hard disk media/50' '2' '0' '60' 1 'ổ 50 GB, cần 60: chặn'
    Test-Guard '0/SCSI/Fixed hard disk media/160' '2' '0' '170' 1 'chia C-D cần 170 GB, ổ 160: chặn'
    Test-Guard $nvme '2' '$$VT_WINDOWS_DISK_1ST_NONUSB$$' '60' 1 'biến Ventoy chưa được điền: chặn'
    Test-Guard '1/USB/Removable Media/32' '2' '0' '60' 1 'không có ổ trong: chặn'
} finally {
    $env:AUTOSETUP_TEST_DISKS = ''
    $env:AUTOSETUP_TEST_FIRMWARE = ''
    Remove-TestDir $d
}

Complete-Test
