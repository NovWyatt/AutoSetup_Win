<#
  Chạy mọi bài thử (tests\<số>_*.ps1), mỗi bài một tiến trình PowerShell riêng. Bài thử không đổi máy: chỉ ghi vào
  %TEMP%\AutoSetup-KiemThu (xoá khi xong); bài có thẻ "doc-may" đọc máy thật (ổ đĩa, thiết bị) nhưng không đổi gì.
    -Chi 3,5        chỉ chạy bài có số hoặc tên khớp
    -ChiTiet        in toàn bộ đầu ra của từng bài (mặc định chỉ in dòng hỏng)
  Mã thoát: 0 đạt hết, 1 có bài hỏng.
#>
param([string[]]$Chi = @(), [switch]$ChiTiet)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$tests = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File | Where-Object { $_.Name -match '^\d+_' } | Sort-Object Name)
if ($Chi.Count) {
    $want = @($Chi | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
    $tests = @($tests | Where-Object { $n = $_.BaseName; @($want | Where-Object { $n -like "$_*" -or $n -like "*$_*" }).Count })
}
$failed = @()
$start = Get-Date
foreach ($t in $tests) {
    $t0 = Get-Date
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $t.FullName 2>&1
    $code = $LASTEXITCODE
    $lines = @($out | ForEach-Object { [string]$_ })
    $sec = [int]((Get-Date) - $t0).TotalSeconds
    if ($code -eq 0) {
        Write-Host ('[ĐẠT]  {0,-22} {1,4}s  {2}' -f $t.BaseName, $sec, ($lines | Select-Object -Last 1)) -ForegroundColor Green
        if ($ChiTiet) { $lines | ForEach-Object { Write-Host "       $_" } }
    } else {
        $failed += $t.BaseName
        Write-Host ('[HỎNG] {0,-22} {1,4}s  mã {2}' -f $t.BaseName, $sec, $code) -ForegroundColor Red
        $show = if ($ChiTiet) { $lines } else { @($lines | Where-Object { $_ -match 'HỎNG|Exception|Error|lỗi|At line|đạt, ' }) }
        $show | ForEach-Object { Write-Host "       $_" }
    }
}
Write-Host ''
Write-Host ('{0} bài, {1} hỏng, {2:N0} giây.' -f $tests.Count, $failed.Count, ((Get-Date) - $start).TotalSeconds)
if ($failed.Count) { exit 1 }
exit 0
