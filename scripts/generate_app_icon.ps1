# Regenerate the app's geometric calendar mark for all supported platforms.
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
function RoundRect($x, $y, $width, $height, $radius) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $radius * 2
    $path.AddArc($x, $y, $diameter, $diameter, 180, 90)
    $path.AddArc(($x + $width - $diameter), $y, $diameter, $diameter, 270, 90)
    $path.AddArc(($x + $width - $diameter), ($y + $height - $diameter), $diameter, $diameter, 0, 90)
    $path.AddArc($x, ($y + $height - $diameter), $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return ,$path
}
function FillRound($graphics, $brush, $x, $y, $width, $height, $radius) {
    $path = RoundRect $x $y $width $height $radius
    $graphics.FillPath($brush, $path)
    $path.Dispose()
}
function New-Mark([bool] $foreground) {
    $bitmap = New-Object System.Drawing.Bitmap 1024,1024
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    if (!$foreground) {
        $gradient = New-Object System.Drawing.Drawing2D.LinearGradientBrush ([System.Drawing.Rectangle]::new(0,0,1024,1024)), ([System.Drawing.ColorTranslator]::FromHtml('#3568D4')), ([System.Drawing.ColorTranslator]::FromHtml('#9E8CDE')), 45
        $g.FillRectangle($gradient,0,0,1024,1024)
        $gradient.Dispose()
        $glow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(24,255,255,255))
        $g.FillEllipse($glow,-160,-230,950,950)
        $glow.Dispose()
    }
    $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(35,30,48,106))
    FillRound $g $shadow 249 274 544 556 100
    $shadow.Dispose()
    $glass = New-Object System.Drawing.Drawing2D.LinearGradientBrush ([System.Drawing.Rectangle]::new(240,240,544,556)), ([System.Drawing.Color]::FromArgb(252,255,255,255)), ([System.Drawing.Color]::FromArgb(221,227,237,255)), 65
    FillRound $g $glass 240 240 544 556 100
    $glass.Dispose()
    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    FillRound $g $white 356 196 40 114 20
    FillRound $g $white 628 196 40 114 20
    $white.Dispose()
    $line = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(40,53,104,212)), 8
    $g.DrawLine($line,304,370,720,370)
    $line.Dispose()
    $blue = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#3568D4'))
    $purple = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#A08ADD'))
    $pale = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#CBD8F4'))
    FillRound $g $blue 316 430 170 106 30
    FillRound $g $pale 522 430 186 106 30
    FillRound $g $pale 316 572 94 132 30
    FillRound $g $purple 446 572 262 132 30
    $blue.Dispose(); $purple.Dispose(); $pale.Dispose()
    $g.Dispose()
    return ,$bitmap
}
function Save-Size($source, [string] $relative, [int] $size) {
    $image = New-Object System.Drawing.Bitmap $size,$size
    $g = [System.Drawing.Graphics]::FromImage($image)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($source,0,0,$size,$size)
    $g.Dispose()
    $image.Save((Join-Path $root $relative), [System.Drawing.Imaging.ImageFormat]::Png)
    $image.Dispose()
}
$mark = New-Mark $false
Save-Size $mark 'assets/app_icon.png' 1024
$densities = @{mdpi=48;hdpi=72;xhdpi=96;xxhdpi=144;xxxhdpi=192}
foreach ($density in $densities.Keys) {
    Save-Size $mark "android/app/src/main/res/mipmap-$density/ic_launcher.png" $densities[$density]
}
Save-Size $mark 'android/app/src/main/res/drawable/ic_launcher.png' 192
$foreground = New-Mark $true
Save-Size $foreground 'android/app/src/main/res/drawable/ic_launcher_foreground.png' 432
$foreground.Dispose()
foreach ($platform in @('ios','macos')) {
    $catalog = "$platform/Runner/Assets.xcassets/AppIcon.appiconset"
    $contents = Get-Content -Raw (Join-Path $root "$catalog/Contents.json") | ConvertFrom-Json
    foreach ($entry in $contents.images) {
        if (!$entry.filename) { continue }
        $size = [int]([double]($entry.size.Split('x')[0]) * [double]($entry.scale.TrimEnd('x')))
        Save-Size $mark "$catalog/$($entry.filename)" $size
    }
}
foreach ($size in @(192,512)) {
    Save-Size $mark "web/icons/Icon-$size.png" $size
    Save-Size $mark "web/icons/Icon-maskable-$size.png" $size
}
Save-Size $mark 'web/favicon.png' 32
# PNG-compressed, multi-resolution ICO for Windows.
$stream = [IO.File]::Create((Join-Path $root 'windows/runner/resources/app_icon.ico'))
$writer = New-Object IO.BinaryWriter $stream
$sizes = @(16,32,48,64,128,256)
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Length)
$offset = 6 + 16 * $sizes.Length
$payloads = @()
foreach ($size in $sizes) {
    $image = New-Object System.Drawing.Bitmap $size,$size
    $g = [System.Drawing.Graphics]::FromImage($image)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($mark,0,0,$size,$size); $g.Dispose()
    $memory = New-Object IO.MemoryStream
    $image.Save($memory,[System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $memory.ToArray()
    $payloads += ,$bytes
    $dimension = if ($size -eq 256) { 0 } else { $size }
    $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]32)
    $writer.Write([uint32]$bytes.Length); $writer.Write([uint32]$offset)
    $offset += $bytes.Length
    $memory.Dispose(); $image.Dispose()
}
foreach ($bytes in $payloads) { $writer.Write([byte[]]$bytes) }
$writer.Dispose(); $stream.Dispose(); $mark.Dispose()