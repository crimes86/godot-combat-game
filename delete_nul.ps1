# Delete the problematic 'nul' file using .NET with extended path prefix
$extendedPath = "\\?\C:\Users\kevin\OneDrive\godot-combat-game-master\nul"

Write-Host "Attempting to delete: $extendedPath"

try {
    # Check if it's a file or directory
    if ([System.IO.File]::Exists($extendedPath)) {
        Write-Host "Found as file, deleting..."
        [System.IO.File]::Delete($extendedPath)
        Write-Host "Deleted successfully!"
    } elseif ([System.IO.Directory]::Exists($extendedPath)) {
        Write-Host "Found as directory, deleting..."
        [System.IO.Directory]::Delete($extendedPath, $true)
        Write-Host "Deleted successfully!"
    } else {
        Write-Host "File not found with extended path syntax"

        # Alternative: Try using cmd.exe
        Write-Host "Trying cmd.exe method..."
        $result = cmd /c "del /f /q `"\\?\C:\Users\kevin\OneDrive\godot-combat-game-master\nul`" 2>&1"
        Write-Host "CMD result: $result"
    }
} catch {
    Write-Host "Error: $_"
}
