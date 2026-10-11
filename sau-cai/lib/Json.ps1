<#
  Đọc, ghi JSON dùng chung (bước sau cài và các script dựng USB).
  ConvertTo-Json của PowerShell 5.1 đổi ' < > & thành '..., thụt lề lộn xộn và cắt mảng một phần tử; Ventoy đọc
  ventoy.json bằng bộ đọc riêng nên ghi bằng hàm dưới đây: giữ nguyên chữ (kể cả tiếng Việt), thụt 4 dấu cách.
#>

function Read-JsonFile {
    # Đọc file JSON (UTF-8, có hay không có BOM). Lỗi thì báo rõ file nào hỏng.
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Không thấy file $Path" }
    try { return ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json) }
    catch { throw "File $Path không phải JSON hợp lệ: $($_.Exception.Message)" }
}

function ConvertTo-JsonText {
    # Chuyển đối tượng (PSCustomObject, hashtable, mảng, chuỗi, số, bool, $null) thành chữ JSON thụt lề.
    param($Value, [int]$Depth = 0)
    $pad = '    ' * ($Depth + 1)
    $end = '    ' * $Depth
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [string] -or $Value -is [char] -or $Value -is [guid] -or $Value -is [enum]) {
        $sb = New-Object Text.StringBuilder
        [void]$sb.Append('"')
        foreach ($ch in ([string]$Value).ToCharArray()) {
            switch ($ch) {
                '"' { [void]$sb.Append('\"') }
                '\' { [void]$sb.Append('\\') }
                "`n" { [void]$sb.Append('\n') }
                "`r" { [void]$sb.Append('\r') }
                "`t" { [void]$sb.Append('\t') }
                default {
                    if ([int]$ch -lt 0x20) { [void]$sb.AppendFormat('\u{0:x4}', [int]$ch) } else { [void]$sb.Append($ch) }
                }
            }
        }
        [void]$sb.Append('"')
        return $sb.ToString()
    }
    if ($Value -is [datetime]) { return '"' + $Value.ToString('s') + '"' }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or $Value -is [byte] -or $Value -is [uint32] -or $Value -is [uint64]) {
        return ([string]$Value)
    }
    if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
        return $Value.ToString([Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [Collections.IDictionary]) {
        $keys = @($Value.Keys)
        if (-not $keys.Count) { return '{}' }
        $parts = foreach ($k in $keys) { $pad + (ConvertTo-JsonText ([string]$k)) + ': ' + (ConvertTo-JsonText $Value[$k] ($Depth + 1)) }
        return "{`n" + ($parts -join ",`n") + "`n$end}"
    }
    if ($Value -is [Management.Automation.PSCustomObject]) {
        $props = @($Value.PSObject.Properties)
        if (-not $props.Count) { return '{}' }
        $parts = foreach ($p in $props) { $pad + (ConvertTo-JsonText $p.Name) + ': ' + (ConvertTo-JsonText $p.Value ($Depth + 1)) }
        return "{`n" + ($parts -join ",`n") + "`n$end}"
    }
    if ($Value -is [Collections.IEnumerable]) {
        $items = @($Value)
        if (-not $items.Count) { return '[]' }
        $parts = foreach ($i in $items) { $pad + (ConvertTo-JsonText $i ($Depth + 1)) }
        return "[`n" + ($parts -join ",`n") + "`n$end]"
    }
    return (ConvertTo-JsonText ([string]$Value) $Depth)
}

function Write-JsonFile {
    # Ghi JSON (UTF-8 không BOM) qua file tạm rồi đổi tên, để không để lại file ghi dở khi mất điện.
    param([Parameter(Mandatory)][string]$Path, $Value)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = "$Path.tmp"
    [IO.File]::WriteAllText($tmp, (ConvertTo-JsonText $Value) + "`n", (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}
