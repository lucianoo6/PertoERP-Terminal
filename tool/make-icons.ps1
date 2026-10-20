param([string]$Source, [string]$Project)

Add-Type -AssemblyName System.Drawing

$base = [System.Drawing.Image]::FromFile($Source)

function Render([int]$size, [string]$dot) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($base, 0, 0, $size, $size)

    if ($dot) {
        # Bolinha de status no canto inferior direito, com anel branco para destacar sobre o verde.
        $d = [math]::Max(6, [math]::Round($size * 0.46))
        $x = $size - $d
        $y = $size - $d
        $ring = [math]::Max(1, [math]::Round($size * 0.07))
        $g.FillEllipse([System.Drawing.Brushes]::White, $x, $y, $d, $d)
        $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($dot))
        $g.FillEllipse($brush, $x + $ring, $y + $ring, $d - 2 * $ring, $d - 2 * $ring)
        $brush.Dispose()
    }

    $g.Dispose()
    $stream = New-Object System.IO.MemoryStream
    $bmp.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()

    return , $stream.ToArray()
}

function WriteIco([string]$path, [int[]]$sizes, [string]$dot) {
    $images = @()
    foreach ($size in $sizes) { $images += , (Render $size $dot) }

    $out = New-Object System.IO.MemoryStream
    $w = New-Object System.IO.BinaryWriter $out
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $s = $sizes[$i]
        $w.Write([byte]($(if ($s -ge 256) { 0 } else { $s })))
        $w.Write([byte]($(if ($s -ge 256) { 0 } else { $s })))
        $w.Write([byte]0); $w.Write([byte]0)
        $w.Write([uint16]1); $w.Write([uint16]32)
        $w.Write([uint32]$images[$i].Length); $w.Write([uint32]$offset)
        $offset += $images[$i].Length
    }
    foreach ($img in $images) { $w.Write($img) }
    $w.Flush()
    [System.IO.File]::WriteAllBytes($path, $out.ToArray())
}

New-Item -ItemType Directory -Force "$Project\assets\tray", "$Project\assets\brand" | Out-Null

WriteIco "$Project\windows\runner\resources\app_icon.ico" @(16, 20, 24, 32, 40, 48, 64, 128, 256) $null

$states = @{ ok = '#4f8a16'; degraded = '#d97706'; error = '#dc2626'; setup = '#9ca3af' }
foreach ($state in $states.Keys) {
    WriteIco "$Project\assets\tray\$state.ico" @(16, 20, 24, 32, 40, 48) $states[$state]
    [System.IO.File]::WriteAllBytes("$Project\assets\tray\$state.png", (Render 64 $states[$state]))
}

[System.IO.File]::WriteAllBytes("$Project\assets\brand\icon.png", (Render 128 $null))
$base.Dispose()
Get-ChildItem "$Project\assets" -Recurse -File | Select-Object FullName, Length

