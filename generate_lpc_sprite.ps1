param(
    [string]$AnimationType = "walk",  # walk, slash, hurt, etc.
    [string]$OutputName = "character_walk",
    [string]$BodyColor = "light",
    [string]$TorsoColor = "iron",
    [string]$LegsColor = "black",
    [string]$HatColor = "iron",
    [string]$WeaponName = "longsword"
)

Add-Type -AssemblyName System.Drawing

$BaseDir = "C:\lpc-generator-full\Universal-LPC-Spritesheet-Character-Generator-master\spritesheets"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "LPC Sprite Generator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Animation: $AnimationType"
Write-Host "Output: $OutputName.png"
Write-Host ""

# Define layer order (bottom to top)
$layers = @()

# Determine dimensions based on animation type
$width = 0
$height = 256

switch ($AnimationType) {
    "walk" { $width = 576; $frames = 9; $rows = 4 }
    "slash" { $width = 384; $frames = 6; $rows = 4 }
    "hurt" { $width = 384; $frames = 6; $rows = 4 }
    default {
        Write-Host "ERROR: Unknown animation type: $AnimationType" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Sprite dimensions: $width x $height ($frames frames x $rows rows)" -ForegroundColor Yellow
Write-Host ""

# Build layer paths in correct order
Write-Host "Building layer stack..." -ForegroundColor Green

# Layer 1: Body
$bodyPath = "$BaseDir\body\bodies\male\$AnimationType\$BodyColor.png"
if (Test-Path $bodyPath) {
    $layers += @{ Name = "Body"; Path = $bodyPath }
    Write-Host "  [1] Body: $BodyColor" -ForegroundColor White
} else {
    Write-Host "  [X] Body not found: $bodyPath" -ForegroundColor Red
}

# Layer 2: Legs
$legsPath = "$BaseDir\legs\leggings\male\$AnimationType\$LegsColor.png"
if (Test-Path $legsPath) {
    $layers += @{ Name = "Legs"; Path = $legsPath }
    Write-Host "  [2] Legs: $LegsColor" -ForegroundColor White
}

# Layer 3: Torso
$torsoPath = "$BaseDir\torso\chainmail\male\$AnimationType\$TorsoColor.png"
if (Test-Path $torsoPath) {
    $layers += @{ Name = "Torso"; Path = $torsoPath }
    Write-Host "  [3] Torso: $TorsoColor" -ForegroundColor White
}

# Layer 4: Hat/Helmet
$hatPath = "$BaseDir\hat\helmet\nasal\adult\$AnimationType\$HatColor.png"
if (Test-Path $hatPath) {
    $layers += @{ Name = "Hat"; Path = $hatPath }
    Write-Host "  [4] Hat: $HatColor" -ForegroundColor White
}

# Layer 5: WEAPON ON TOP (need to convert 3-row to 4-row for walk)
if ($AnimationType -eq "walk") {
    $weaponPath = "$BaseDir\weapon\sword\$WeaponName\universal_behind\walk\$WeaponName.png"
    if (Test-Path $weaponPath) {
        Write-Host "  [5] Weapon: $WeaponName - converting 3-row to 4-row..." -ForegroundColor Yellow

        # Load 3-row weapon sprite
        $weapon3row = [System.Drawing.Image]::FromFile($weaponPath)

        # Create 4-row version (576x256)
        $weapon4row = New-Object System.Drawing.Bitmap(576, 256)
        $g = [System.Drawing.Graphics]::FromImage($weapon4row)
        $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver

        # 3-row weapon sprite has: Row0=UP, Row1=LEFT, Row2=RIGHT (at Y: 0, 64, 128)
        # Need to create 4-row: Row0=UP, Row1=LEFT, Row2=DOWN, Row3=RIGHT (at Y: 0, 64, 128, 192)

        # Row 0: UP direction (from source row 0)
        $g.DrawImage($weapon3row, (New-Object System.Drawing.Rectangle(0, 0, 576, 64)), (New-Object System.Drawing.Rectangle(0, 0, 576, 64)), [System.Drawing.GraphicsUnit]::Pixel)

        # Row 1: LEFT direction (from source row 1)
        $g.DrawImage($weapon3row, (New-Object System.Drawing.Rectangle(0, 64, 576, 64)), (New-Object System.Drawing.Rectangle(0, 64, 576, 64)), [System.Drawing.GraphicsUnit]::Pixel)

        # Row 2: DOWN direction (flip UP vertically - row 0 flipped, place at Y=128)
        $g.DrawImage($weapon3row, (New-Object System.Drawing.Rectangle(0, 192, 576, -64)), (New-Object System.Drawing.Rectangle(0, 0, 576, 64)), [System.Drawing.GraphicsUnit]::Pixel)

        # Row 3: RIGHT direction (from source row 2 at Y=128, place at Y=192)
        $g.DrawImage($weapon3row, (New-Object System.Drawing.Rectangle(0, 192, 576, 64)), (New-Object System.Drawing.Rectangle(0, 128, 576, 64)), [System.Drawing.GraphicsUnit]::Pixel)

        $g.Dispose()
        $weapon3row.Dispose()

        # Save temporary 4-row weapon
        $temp4rowPath = "$env:TEMP\weapon_4row.png"
        $weapon4row.Save($temp4rowPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $weapon4row.Dispose()

        $layers += @{ Name = "Weapon"; Path = $temp4rowPath }
        Write-Host "  [5] Weapon: $WeaponName (4-row, TOP LAYER)" -ForegroundColor Yellow
    } else {
        Write-Host "  [X] Weapon not found: $weaponPath" -ForegroundColor Red
    }
}

Write-Host ""

if ($layers.Count -eq 0) {
    Write-Host "ERROR: No layers found!" -ForegroundColor Red
    exit 1
}

# Create output canvas
Write-Host "Creating $width x $height canvas..." -ForegroundColor Green
$output = New-Object System.Drawing.Bitmap($width, $height)
$g = [System.Drawing.Graphics]::FromImage($output)
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver

# Composite all layers
Write-Host "Compositing layers..." -ForegroundColor Green
foreach ($layer in $layers) {
    Write-Host "  - Blending $($layer.Name)..." -ForegroundColor Gray
    $img = [System.Drawing.Image]::FromFile($layer.Path)
    $g.DrawImage($img, 0, 0, $width, $height)
    $img.Dispose()
}

$g.Dispose()

# Save output
$outputPath = "C:\Users\kevin\OneDrive\fantom\mmo\rhythmrpg\assets\test_sprites\$OutputName.png"
Write-Host ""
Write-Host "Saving to: $outputPath" -ForegroundColor Green
$output.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$output.Dispose()

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SUCCESS!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Generated: $OutputName.png"
Write-Host "Layers: $($layers.Count)"
Write-Host "Size: $width x $height"
