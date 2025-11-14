Add-Type -AssemblyName System.Drawing

# Load the composite sprite (body + weapon)
$compositePath = "C:\Users\kevin\OneDrive\fantom\mmo\rhythmrpg\assets\test_sprites\walk_longsword.png"
$composite = [System.Drawing.Image]::FromFile($compositePath)

# Load the body-only sprite
$bodyPath = "C:\Fraps\Universal-LPC-Spritesheet-Character-Generator-master (1)\Universal-LPC-Spritesheet-Character-Generator-master\spritesheets\body\bodies\male\slash\light.png"
$body = [System.Drawing.Image]::FromFile($bodyPath)

# Create output image (same size as composite)
$output = New-Object System.Drawing.Bitmap(576, 256)

Write-Host "Extracting weapon layer by comparing composite vs body-only..."

# Compare pixel by pixel - keep only pixels that differ (the weapon)
for ($y = 0; $y -lt 256; $y++) {
    for ($x = 0; $x -lt 576; $x++) {
        $compositePixel = $composite.GetPixel($x, $y)
        $bodyPixel = $body.GetPixel($x, $y)

        # If pixels are different, it's the weapon - keep it
        if ($compositePixel.ToArgb() -ne $bodyPixel.ToArgb()) {
            $output.SetPixel($x, $y, $compositePixel)
        }
        # Otherwise keep transparent
        else {
            $output.SetPixel($x, $y, [System.Drawing.Color]::Transparent)
        }
    }

    # Progress indicator every 32 pixels
    if ($y % 32 -eq 0) {
        Write-Host "  Processing row $y / 256..."
    }
}

$composite.Dispose()
$body.Dispose()

# Save the weapon-only layer
$outputPath = "C:\Users\kevin\OneDrive\fantom\mmo\rhythmrpg\assets\weapons\walk\longsword_extracted.png"
$output.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$output.Dispose()

Write-Host "`nDONE! Weapon layer extracted to: $outputPath"
Write-Host "This is a 576x256 sprite with ONLY the weapon pixels (4 rows)"
