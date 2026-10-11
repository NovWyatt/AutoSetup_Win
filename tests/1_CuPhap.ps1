<#
  Cú pháp và mã hoá: mọi .ps1 phân tích được bằng PowerShell 5.1 và có BOM; .bat không BOM, CRLF, chỉ ASCII;
  mọi .json đọc được; KiemTraO.vbs không có ký tự cmd đặc biệt; ChuanHoaFile -ChiKiemTra không báo file sai.
#>
. (Join-Path $PSScriptRoot 'lib\KiemThu.ps1')

$files = Get-ChildItem -LiteralPath $script:Repo -Recurse -File | Where-Object { $_.FullName -notmatch '\\(\.git|out)\\' }

foreach ($f in $files | Where-Object { $_.Extension -eq '.ps1' }) {
    $rel = $f.FullName.Substring($script:Repo.Length + 1)
    $tokens = $null; $errs = $null
    [void][Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errs)
    Assert-True (-not $errs.Count) ("cú pháp $rel" + $(if ($errs.Count) { ": $($errs[0].Message) (dòng $($errs[0].Extent.StartLineNumber))" }))
    $b = [IO.File]::ReadAllBytes($f.FullName)
    Assert-True ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) "BOM $rel"
}

foreach ($f in $files | Where-Object { $_.Extension -eq '.bat' }) {
    $rel = $f.FullName.Substring($script:Repo.Length + 1)
    $b = [IO.File]::ReadAllBytes($f.FullName)
    Assert-True (-not ($b.Length -ge 3 -and $b[0] -eq 0xEF)) "không BOM $rel"
    Assert-True (-not @($b | Where-Object { $_ -gt 127 }).Count) "chỉ ASCII $rel"
    $text = [Text.Encoding]::ASCII.GetString($b)
    Assert-True (($text -replace "`r`n", '') -notmatch "`n") "CRLF $rel"
}

foreach ($f in $files | Where-Object { $_.Extension -eq '.json' }) {
    $rel = $f.FullName.Substring($script:Repo.Length + 1)
    $ok = $true
    try { [void]([IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json) } catch { $ok = $false }
    Assert-True $ok "JSON đọc được $rel"
}

foreach ($f in $files | Where-Object { $_.Extension -eq '.xml' }) {
    $rel = $f.FullName.Substring($script:Repo.Length + 1)
    $ok = $true
    try { $x = New-Object Xml.XmlDocument; $x.Load($f.FullName) } catch { $ok = $false }
    Assert-True $ok "XML đọc được $rel"
}

$vbs = @(Get-Content -LiteralPath (Join-Path $script:Repo 'unattend\KiemTraO.vbs') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("'") })
Assert-True (-not @($vbs | Where-Object { $_ -match '[&|<>^%]' }).Count) 'KiemTraO.vbs không có & | < > ^ % (ngoài chú thích)'
Assert-True (-not @($vbs | Where-Object { $_.Length -gt 215 }).Count) 'KiemTraO.vbs mỗi dòng tối đa 215 ký tự (lệnh echo trong WinPE tối đa 255)'

$r = Invoke-Ps (Join-Path $script:Repo 'scripts\ChuanHoaFile.ps1') @('-ChiKiemTra')
Assert-Equal 0 $r.Code "ChuanHoaFile -ChiKiemTra: $($r.Text.Trim())"

Complete-Test
