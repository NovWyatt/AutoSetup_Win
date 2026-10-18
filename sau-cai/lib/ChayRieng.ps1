<#
  Chạy một hàm của lib\*.ps1 trong tiến trình powershell.exe riêng (Invoke-StorageFunction trong HeThong.ps1 gọi), ghi
  giá trị hàm trả về (hoặc lỗi) ra file CLIXML -Ra. Tiến trình gọi dừng được tiến trình này khi hàm đứng quá giờ.
    -Ham <tên hàm>   hàm cần chạy
    -Ra <file>       file kết quả
    -ChayThu         gọi hàm với -DryRun
#>
param([Parameter(Mandatory)][string]$Ham, [Parameter(Mandatory)][string]$Ra, [switch]$ChayThu)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
foreach ($f in 'Json.ps1', 'Chung.ps1', 'HeThong.ps1') { . (Join-Path $PSScriptRoot $f) }

if ($env:AUTOSETUP_TEST_TREO_ODIA) { Start-Sleep -Seconds 600 }   # bài thử giả lệnh Storage đứng
$a = @{}
if ($ChayThu) { $a.DryRun = $true }
try { $r = [pscustomobject]@{ KetQua = (& $Ham @a); Loi = '' } }
catch { $r = [pscustomobject]@{ KetQua = $null; Loi = $_.Exception.Message.Trim() } }
Export-Clixml -LiteralPath $Ra -InputObject $r -Depth 4
