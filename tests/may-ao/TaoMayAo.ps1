<#
  Tạo máy ảo VirtualBox để thử AutoSetup_Win: UEFI + TPM 2.0 + Secure Boot, ổ SATA, gắn ISO Windows và ISO thử
  (TaoIsoThu.ps1). -Chay thì khởi động luôn và bấm phím ở màn "Press any key to boot from CD or DVD".

  Tham số:
    -Ten <tên>             tên máy ảo (mặc định AutoSetup-Thu)
    -IsoWin <file .iso>    ISO Windows 10/11
    -IsoThu <file .iso>    ISO thử (mặc định out\may-ao\usb-3_XOA-SACH-o_1-phan-vung.iso)
    -OGB 64[,500]          dung lượng từng ổ (GB); hai ổ trở lên để thử bản xoá ổ bị chặn
    -RamMB, -Cpu           mặc định 4096 MB, 4 nhân
    -Chay                  khởi động máy ảo (cửa sổ VirtualBox) và qua màn bấm phím của đĩa cài
  Ví dụ: powershell -ExecutionPolicy Bypass -File tests\may-ao\TaoMayAo.ps1 -IsoWin D:\ISO\Win11.iso -Chay
#>
[CmdletBinding()]
param(
    [string]$Ten = 'AutoSetup-Thu',
    [Parameter(Mandatory)] [string]$IsoWin,
    [string]$IsoThu = '',
    [string[]]$OGB = @('64'),   # chuỗi: qua powershell -File, "64,80" thành số 6480 nếu khai báo [int[]]
    [int]$RamMB = 4096,
    [int]$Cpu = 4,
    [switch]$Chay
)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $IsoThu) { $IsoThu = Join-Path $repo 'out\may-ao\usb-3_XOA-SACH-o_1-phan-vung.iso' }
foreach ($f in $IsoWin, $IsoThu) { if (-not (Test-Path -LiteralPath $f)) { throw "Không có $f" } }
$sizes = @($OGB | ForEach-Object { $_ -split ',' } | Where-Object { $_.Trim() } | ForEach-Object { [int]$_.Trim() })
if (-not $sizes.Count -or @($sizes | Where-Object { $_ -lt 30 }).Count) { throw 'Mỗi ổ ít nhất 30 GB (-OGB 64 hoặc -OGB 64,80).' }

$dir = @($env:VBOX_MSI_INSTALL_PATH, (Get-ItemProperty 'HKLM:\SOFTWARE\Oracle\VirtualBox' -ErrorAction SilentlyContinue).InstallDir,
    "$env:ProgramFiles\Oracle\VirtualBox") | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'VBoxManage.exe')) } | Select-Object -First 1
if (-not $dir) { throw 'Chưa cài VirtualBox (không thấy VBoxManage.exe).' }
$vb = Join-Path $dir 'VBoxManage.exe'
function V {
    # VBoxManage ghi tiến độ ra stderr; chỉ coi mã thoát.
    $ErrorActionPreference = 'Continue'
    $out = & $vb @args 2>$null
    if ($LASTEXITCODE -ne 0) { throw "VBoxManage $($args -join ' ') -> mã $LASTEXITCODE" }
    return $out
}

V createvm --name $Ten --ostype Windows11_64 --register | Out-Null
$cfg = ((V showvminfo $Ten --machinereadable | Where-Object { $_ -like 'CfgFile=*' }) -replace '^CfgFile="(.*)"$', '$1') -replace '\\\\', '\'
$vmDir = Split-Path -Parent $cfg
# Ổ trước, đĩa cài sau: ổ trống thì khởi động đĩa cài; cài xong khởi động thẳng vào Windows.
# natdnshostresolver: DNS của NAT hay hỏng khi máy thật dùng VPN, Hyper-V; OOBE, winget cần DNS.
# paravirt none: trên máy thật dùng Hyper-V, paravirt mặc định (Hyper-V) làm Windows trong máy ảo màn hình xanh 0xA.
V modifyvm $Ten --memory $RamMB --cpus $Cpu --ioapic on --firmware efi --tpm-type 2.0 --graphicscontroller vboxsvga --vram 128 `
    --paravirt-provider none `
    --nic1 nat --natdnshostresolver1 on --audio-enabled off --usb-ohci off --usb-ehci off --usb-xhci off `
    --boot1 disk --boot2 dvd --boot3 none --boot4 none --clipboard-mode disabled --drag-and-drop disabled | Out-Null
V modifynvram $Ten inituefivarstore | Out-Null
V modifynvram $Ten enrollmssignatures | Out-Null
V modifynvram $Ten enrollorclpk | Out-Null
V modifynvram $Ten secureboot --enable | Out-Null
V storagectl $Ten --name SATA --add sata --controller IntelAhci --portcount ($sizes.Count + 2) --hostiocache on | Out-Null
$port = 0
foreach ($gb in $sizes) {
    $vdi = Join-Path $vmDir "$Ten-o$port.vdi"
    V createmedium disk --filename $vdi --size ($gb * 1024) --format VDI | Out-Null
    V storageattach $Ten --storagectl SATA --port $port --device 0 --type hdd --medium $vdi | Out-Null
    $port++
}
V storageattach $Ten --storagectl SATA --port $port --device 0 --type dvddrive --medium $IsoWin | Out-Null
V storageattach $Ten --storagectl SATA --port ($port + 1) --device 0 --type dvddrive --medium $IsoThu | Out-Null
Write-Host "Đã tạo máy ảo $Ten ($(($sizes | ForEach-Object { "$_ GB" }) -join ' + '), $RamMB MB, $Cpu nhân) tại $vmDir" -ForegroundColor Green
if (-not $Chay) { return }

# Khởi động, chờ VBox.log báo nạp cdboot.efi (màn "Press any key...") rồi bấm Enter vài lần.
$log = Join-Path $vmDir 'Logs\VBox.log'
V startvm $Ten --type gui | Out-Null
$deadline = (Get-Date).AddMinutes(5)
while ((Get-Date) -lt $deadline) {
    if ((Get-Content -LiteralPath $log -ErrorAction SilentlyContinue) -match "loadimage64 'cdboot\.efi'") {
        for ($i = 0; $i -lt 8; $i++) { & $vb controlvm $Ten keyboardputscancode 1c 9c 2>$null; Start-Sleep -Milliseconds 300 }
        Write-Host 'Đã bấm phím khởi động đĩa cài. Theo dõi trong cửa sổ VirtualBox.' -ForegroundColor Green
        return
    }
    Start-Sleep -Milliseconds 250
}
Write-Warning 'Không thấy màn bấm phím của đĩa cài sau 5 phút: bấm một phím trong cửa sổ máy ảo nếu nó đang chờ.'
