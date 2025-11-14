Add-Type -AssemblyName System.Drawing

# Load the existing walk sprite
$walkSprite = [System.Drawing.Image]::FromFile("C:\Users\kevin\OneDrive\fantom\mmo\rhythmrpg\assets\test_sprites\walk_longsword.png")

# Paths to individual layers in correct order (bottom to top)
$bodyPath = "C:\Fraps\Universal-LPC-Spritesheet-Character-Generator-master (1)\Universal-LPC-Spritesheet-Character-Generator-master\spritesheets\body\bodies\male\slash\light.png"
$legsPath = "C:\lpc-generator-full\Universal-LPC-Spritesheet-Character-Generator-master\spritesheets\legs\leggings\male\slash\black.png"
$torsoPath = "C:\lpc-generator-full\Universal-LPC-Spritesheet-Character-Generator-master\spritesheets\torso\chainmail\male\slash\iron.png"
$hatPath = "C:\lpc-generator-full\Universal-LPC-Spritesheet-Character-Generator-master\spritesheets\hat\helmet\nasal\adult\slash\iron.png"
$weaponPath = "C:\lpc-generator-full\Universal-LPC-Spritesheet-Character-Generator-master\spritesheets\weapon\sword\longsword\walk\longsword.png"

# Create output - copy existing sprite as base
$output = New-Object System.Drawing.Bitmap(576, 256)
$g = [System.Drawing.Graphics]::FromImage($output)

# Set compositing mode to draw over (not blend)
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver

$g.DrawImage($walkSprite, 0, 0)

Write-Host "Rebuilding row 2 (down direction, Y=128) with weapon on top..."

# Clear row 2 first by drawing transparent rectangle
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$clearBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Transparent)
$g.FillRectangle($clearBrush, 0, 128, 576, 64)
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver

# Layer 1: Body
if (Test-Path $bodyPath) {
    $body = [System.Drawing.Image]::FromFile($bodyPath)
    $g.DrawImage($body, (New-Object System.Drawing.Rectangle(0, 128, 576, 64)), (New-Object System.Drawing.Rectangle(0, 128, 576, 64)), [System.Drawing.GraphicsUnit]::Pixel)
    $body.Dispose()
    Write-Host "  1. Body drawn"
}

# Layer 2: Legs/Pants
if (Test-Path $legsPath) {
    $legs = [System.Drawing.Image]::FromFile($legsPath)
    $g.DrawImage($legs, (New-Object System.Drawing.Rectangle(0, 128, 576, 64)), (New-Object System.Drawing.Rectangle(0, 128, 576, 64)), [System.Drawing.GraphicsUnit]::Pixel)
    $legs.Dispose()
    Write-Host "  2. Legs drawn"
}

# Layer 3: Torso/Armor
if (Test-Path $torsoPath) {
    $torso = [System.Drawing.Image]::FromFile($torsoPath)
    $g.DrawImage($torso, (New-Object System.Drawing.Rectangle(0, 128, 576, 64)), (New-Object System.Drawing.Rectangle(0, 128, 576, 64)), [System.Drawing.GraphicsUnit]::Pixel)
    $torso.Dispose()
    Write-Host "  3. Torso drawn"
}

# Layer 4: Hat/Helmet
if (Test-Path $hatPath) {
    $hat = [System.Drawing.Image]::FromFile($hatPath)
    $g.DrawImage($hat, (New-Object System.Drawing.Rectangle(0, 128, 576, 64)), (New-Object System.Drawing.Rectangle(0, 128, 576, 64)), [System.Drawing.GraphicsUnit]::Pixel)
    $hat.Dispose()
    Write-Host "  4. Hat drawn"
}

# Layer 5: WEAPON ON TOP
if (Test-Path $weaponPath) {
    $weapon = [System.Drawing.Image]::FromFile($weaponPath)
    $g.DrawImage($weapon, (New-Object System.Drawing.Rectangle(0, 128, 576, 64)), (New-Object System.Drawing.Rectangle(0, 128, 576, 64)), [System.Drawing.GraphicsUnit]::Pixel)
    $weapon.Dispose()
    Write-Host "  5. WEAPON drawn ON TOP!"
}

$g.Dispose()
$walkSprite.Dispose()

# Save
$outputPath = "C:\Users\kevin\OneDrive\fantom\mmo\rhythmrpg\assets\test_sprites\walk_longsword_fixed.png"
$output.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$output.Dispose()

Write-Host "`nDONE! Row 2 rebuilt with weapon on top."
Write-Host "Close Godot, then rename walk_longsword_fixed.png to walk_longsword.png"
