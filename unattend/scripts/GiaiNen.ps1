<#
  Nhúng trong file unattend (thẻ ExtractScript). Bước specialize chạy nó với nội dung C:\Windows\Panther\unattend.xml:
  ghi từng thẻ <File path="..."> trong phần Extensions ra đĩa. Cách làm theo schneegans/unattend-generator (MIT).
  Thẻ có ma="base64" chứa nội dung UTF-8 dạng base64: Setup đổi chữ ngoài ASCII trong bản Panther thành '?', base64 thì
  giữ nguyên tiếng Việt trong script. TaoUnattend bỏ chú thích khi nhúng; phần mã phải là ASCII.
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
    if ($file.GetAttribute('ma') -eq 'base64') {
        $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($file.InnerText))
    } else {
        $text = $file.InnerText
    }
    $text = $text.Trim() + "`r`n"
    [IO.File]::WriteAllBytes($path, [byte[]]($encoding.GetPreamble() + $encoding.GetBytes($text)))
}
