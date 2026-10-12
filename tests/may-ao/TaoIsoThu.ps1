<#
  Dựng "USB giả" để thử trên máy ảo, không cần Ventoy: chạy TaoUSB vào một thư mục, đặt một bản unattend làm
  autounattend.xml ở gốc (Windows Setup tự đọc từ mọi ổ), rồi đóng thành ISO gắn vào máy ảo cạnh ISO Windows.
  Biến Ventoy trong file unattend: ổ cần xoá lấy theo -DiskId (máy ảo một ổ SATA: 0), tên máy thì như chưa nhập.

  Tham số:
    -BienThe <tên>       bản unattend (mặc định 3_XOA-SACH-o_1-phan-vung; xem \AutoSetup\unattend trên USB)
    -DiskId <số>         số ổ (diskpart) bản xoá ổ được phép xoá (mặc định 0)
    -Ra <file .iso>      mặc định out\may-ao\usb-<BienThe>.iso
    -MatKhauFile, -KhongMatKhau: chuyển cho TaoUSB.ps1 (taiKhoan.cheDo = tu-dong)
  Ví dụ: powershell -ExecutionPolicy Bypass -File tests\may-ao\TaoIsoThu.ps1 -BienThe 1_Chon-o-bang-tay
#>
[CmdletBinding()]
param(
    [string]$BienThe = '3_XOA-SACH-o_1-phan-vung',
    [string]$DiskId = '0',
    [string]$Ra = '',
    [string]$MatKhauFile = '',
    [switch]$KhongMatKhau
)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$work = Join-Path $repo 'out\may-ao'
$usb = Join-Path $work 'usb'
if (-not $Ra) { $Ra = Join-Path $work "usb-$BienThe.iso" }
if (Test-Path -LiteralPath $usb) { Remove-Item -LiteralPath $usb -Recurse -Force }
New-Item -ItemType Directory -Path $usb -Force | Out-Null

$env:AUTOSETUP_OUT = Join-Path $work 'unattend'
$tuArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repo 'scripts\TaoUSB.ps1'), '-O', $usb, '-DiskId', $DiskId, '-KhongDung')
if ($MatKhauFile) { $tuArgs += @('-MatKhauFile', $MatKhauFile) }
if ($KhongMatKhau) { $tuArgs += '-KhongMatKhau' }
& powershell.exe @tuArgs
$code = $LASTEXITCODE
$env:AUTOSETUP_OUT = ''
if ($code -ne 0) { throw "TaoUSB.ps1 lỗi (mã $code)." }
$xml = Join-Path $usb "AutoSetup\unattend\$BienThe.xml"
if (-not (Test-Path -LiteralPath $xml)) { throw "Không có bản unattend $BienThe." }
Copy-Item -LiteralPath $xml -Destination (Join-Path $usb 'autounattend.xml') -Force

# Đóng ISO bằng IMAPI2 có sẵn trong Windows (ISO9660 + Joliet + UDF).
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
public static class AutoSetupIso {
    public static void Save(object stream, string path) {
        IStream s = (IStream)stream;
        byte[] buf = new byte[1 << 20];
        IntPtr pRead = Marshal.AllocHGlobal(sizeof(int));
        try {
            using (FileStream fs = File.Create(path)) {
                while (true) {
                    s.Read(buf, buf.Length, pRead);
                    int n = Marshal.ReadInt32(pRead);
                    if (n <= 0) break;
                    fs.Write(buf, 0, n);
                }
            }
        } finally { Marshal.FreeHGlobal(pRead); }
    }
}
'@
$fs = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
$fs.FileSystemsToCreate = 7
$fs.VolumeName = 'AUTOSETUP'
$fs.FreeMediaBlocks = 0
$fs.Root.AddTree($usb, $false)
New-Item -ItemType Directory -Path (Split-Path -Parent $Ra) -Force | Out-Null
[AutoSetupIso]::Save($fs.CreateResultImage().ImageStream, $Ra)
Write-Host "ISO thử: $Ra ($([Math]::Round((Get-Item -LiteralPath $Ra).Length / 1MB, 1)) MB, bản $BienThe, ổ $DiskId)" -ForegroundColor Green
