<#
  Dành cho người phát triển: chuẩn hoá mã hoá và xuống dòng của file trong repo, chạy trước khi commit.
    .ps1            UTF-8 có BOM (PowerShell 5.1 chỉ đọc đúng tiếng Việt khi có BOM), CRLF
    .bat .cmd       UTF-8 không BOM (cmd.exe hỏng dòng đầu nếu có BOM), CRLF
    .vbs .xml .xaml UTF-8 không BOM, CRLF
    .json .md       UTF-8 không BOM, LF
  -ChiKiemTra: chỉ liệt kê file sai, không sửa (mã thoát 1 nếu có file sai).
#>
param([switch]$ChiKiemTra)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$repo = Split-Path -Parent $PSScriptRoot
$rules = @{
    '.ps1' = @{ Bom = $true; Eol = "`r`n" }
    '.bat' = @{ Bom = $false; Eol = "`r`n" }
    '.cmd' = @{ Bom = $false; Eol = "`r`n" }
    '.vbs' = @{ Bom = $false; Eol = "`r`n" }
    '.xml' = @{ Bom = $false; Eol = "`r`n" }
    '.xaml' = @{ Bom = $false; Eol = "`r`n" }
    '.json' = @{ Bom = $false; Eol = "`n" }
    '.md' = @{ Bom = $false; Eol = "`n" }
}
$bad = 0
# Chỉ file git theo dõi hoặc sẽ theo dõi (bỏ out\, tài liệu bên thứ ba bị .gitignore/.git\info\exclude chặn);
# không có git thì quét cả cây trừ .git, out.
$list = try { @(& git -c core.quotepath=off -C $repo ls-files --cached --others --exclude-standard 2>$null) } catch { $null }
$files = if ($null -eq $list -or $LASTEXITCODE -ne 0) { Get-ChildItem -LiteralPath $repo -Recurse -File | Where-Object { $_.FullName -notmatch '\\(\.git|out)\\' } }
else { $list | ForEach-Object { Get-Item -LiteralPath (Join-Path $repo $_) -ErrorAction SilentlyContinue } }
$files = @($files | Where-Object { $rules.ContainsKey($_.Extension.ToLowerInvariant()) })
foreach ($f in $files) {
    $r = $rules[$f.Extension.ToLowerInvariant()]
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = (New-Object Text.UTF8Encoding $false).GetString($bytes, $(if ($hasBom) { 3 } else { 0 }), $bytes.Length - $(if ($hasBom) { 3 } else { 0 }))
    $norm = ($text -replace "`r`n", "`n" -replace "`r", "`n") -replace "`n", $r.Eol
    if (-not $norm.EndsWith($r.Eol)) { $norm += $r.Eol }
    $enc = New-Object Text.UTF8Encoding $r.Bom
    $want = [byte[]]($enc.GetPreamble() + $enc.GetBytes($norm))
    $same = $want.Length -eq $bytes.Length
    if ($same) { for ($i = 0; $i -lt $want.Length; $i++) { if ($want[$i] -ne $bytes[$i]) { $same = $false; break } } }
    if ($same) { continue }
    $bad++
    $rel = $f.FullName.Substring($repo.Length + 1)
    if ($ChiKiemTra) { Write-Host "  sai: $rel" -ForegroundColor Yellow; continue }
    [IO.File]::WriteAllBytes($f.FullName, $want)
    Write-Host "  đã sửa: $rel"
}
if ($ChiKiemTra -and $bad) { exit 1 }
Write-Host ("  {0} file {1}." -f $bad, $(if ($ChiKiemTra) { 'sai' } else { 'đã chuẩn hoá' }))
exit 0
