<#
  Nhúng trong file unattend (thẻ ExtractScript). Bước specialize chạy nó với nội dung C:\Windows\Panther\unattend.xml:
  ghi từng thẻ <File path="..."> trong phần Extensions ra đĩa. Cách làm theo schneegans/unattend-generator (MIT).
#>
param([xml]$Document)

foreach ($file in $Document.unattend.Extensions.File) {
    $path = [Environment]::ExpandEnvironmentVariables($file.GetAttribute('path'))
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    # .ps1 cần BOM để PowerShell 5.1 đọc đúng tiếng Việt; .vbs đọc được Unicode có BOM; còn lại UTF-8 không BOM.
    $encoding = switch ([IO.Path]::GetExtension($path).ToLowerInvariant()) {
        '.ps1' { New-Object Text.UTF8Encoding $true }
        '.vbs' { New-Object Text.UnicodeEncoding $false, $true }
        default { New-Object Text.UTF8Encoding $false }
    }
    $text = $file.InnerText.Trim() + "`r`n"
    [IO.File]::WriteAllBytes($path, [byte[]]($encoding.GetPreamble() + $encoding.GetBytes($text)))
}
