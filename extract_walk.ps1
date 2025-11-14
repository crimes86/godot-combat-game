Add-Type -AssemblyName System.Drawing

# Load full sprite sheet
$fullSheet = [System.Drawing.Image]::FromFile("C:\Users\kevin\Downloads\Download55915.png")

# Create output image (576x256 - 4 rows of 64px height)
$output = New-Object System.Drawing.Bitmap(576, 256)
$g = [System.Drawing.Graphics]::FromImage($output)

# Extract rows 8-11 (Y=512 to Y=767, height=256)
# Row 8 (Y=512): walk up with sword in right hand
# Row 9 (Y=576): walk left with sword in right hand
# Row 10 (Y=640): walk down with sword in right hand
# Row 11 (Y=704): walk right with sword in right hand

$srcRect = New-Object System.Drawing.Rectangle(0, 512, 576, 256)
$destRect = New-Object System.Drawing.Rectangle(0, 0, 576, 256)
$g.DrawImage($fullSheet, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)

# Save
$g.Dispose()
$output.Save("C:\Users\kevin\OneDrive\fantom\mmo\rhythmrpg\assets\test_sprites\walk_longsword.png", [System.Drawing.Imaging.ImageFormat]::Png)
$output.Dispose()
$fullSheet.Dispose()

Write-Host "Extracted rows 8-11 (walk animations with weapon in right hand)"
