param([Parameter(Mandatory=$true)][string]$Changelog)

$ErrorActionPreference = "Stop"
Push-Location "$PSScriptRoot\.."

# Bump version (supports "X.Y.Z-pre+build" semver format)
$pubspec = Get-Content pubspec.yaml -Raw
$m = [regex]::Match($pubspec, 'version:\s*(\d+)\.(\d+)\.(\d+)(?:-([\w.]+))?\+(\d+)')
$ma,$mi,$pa = [int]$m.Groups[1].Value,[int]$m.Groups[2].Value,[int]$m.Groups[3].Value
$pre = if ($m.Groups[4].Success) { "-$($m.Groups[4].Value)" } else { '' }
$bu = [int]$m.Groups[5].Value + 1
$pa++
$v = "$ma.$mi.$pa$pre"; $b = $bu
$pubspec = $pubspec -replace [regex]::Escape($m.Value), "version: $v+$b"
Set-Content pubspec.yaml $pubspec -NoNewline

# Build
Write-Output "=== Building v$v ==="
$env:CI = "true"  # suppress interactive prompts in flutter.bat
flutter build apk --release
if ($LASTEXITCODE -ne 0) {
  Write-Output "BUILD FAILED"
  Pop-Location; exit 1
}
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "server\app-release.apk" -Force

# Generate asset manifest and sync to server
Write-Output "=== Syncing assets to server ==="
$assetDir = (Resolve-Path "$PSScriptRoot\..\assets").Path + "\"
$serverAssetDir = "akingofcrows@192.168.0.162:~/assets"
$manifestFile = "$PSScriptRoot\..\server\assets\manifest.json"

# Create server assets directory locally
New-Item -ItemType Directory -Force -Path "$PSScriptRoot\..\server\assets" | Out-Null

# Build manifest: {path: md5}
$manifest = @{ version = 1; files = @{} }
Get-ChildItem $assetDir -Recurse -File | ForEach-Object {
  $rel = $_.FullName.Replace($assetDir, "").TrimStart("\").Replace("\", "/")
  $hash = (Get-FileHash $_.FullName -Algorithm MD5).Hash.ToLower()
  $manifest.files[$rel] = $hash
  # Copy to server assets folder
  $dest = "$PSScriptRoot\..\server\assets\$rel"
  New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
  Copy-Item $_.FullName $dest -Force
}
$manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestFile -NoNewline
Write-Output "  Manifest: $($manifest.files.Count) files"

# Upload assets to server via scp (skip if unreachable)
# Quick connectivity check (1-second timeout via dotnet)
$serverUp = $false
try {
  $tcp = New-Object System.Net.Sockets.TcpClient
  $tcp.ConnectAsync("192.168.0.162", 22).Wait(2000)
  $serverUp = $tcp.Connected
  $tcp.Close()
} catch { $serverUp = $false }
if ($serverUp) {
  try {
    $scpOpts = "-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no"
    # Copy manifest first
    Start-Process scp -ArgumentList "$scpOpts $manifestFile akingofcrows@192.168.0.162:~/assets/manifest.json" -Wait -NoNewWindow -Timeout 15
    # Upload all assets zip
    $assetZip = "$PSScriptRoot\..\server\asset_sync.zip"
    Compress-Archive -Path "$PSScriptRoot\..\server\assets\*" -DestinationPath $assetZip -Force
    Start-Process scp -ArgumentList "$scpOpts $assetZip akingofcrows@192.168.0.162:~/asset_sync.zip" -Wait -NoNewWindow -Timeout 30
    Write-Output "  Assets uploaded to server"
  } catch {
    Write-Output "  Asset upload skipped (scp failed)"
  }
} else {
  Write-Output "  Asset upload skipped (server offline)"
}

# Push + release
Push-Location server
git add -A; git commit -m "v$v : $Changelog"; git push
# Delete any existing release first to avoid untagged collision
try { & "C:\Program Files\GitHub CLI\gh.exe" release delete "v$v" -R akingofcrows/pokemon-triad-updates --yes --cleanup-tag 2>&1 | Out-Null } catch {}
# Push tag explicitly, then create release
git tag -f "v$v"; git push origin "v$v"
& "C:\Program Files\GitHub CLI\gh.exe" release create "v$v" app-release.apk --title "v$v" --notes $Changelog -R akingofcrows/pokemon-triad-updates

# ── Discord webhook (fires immediately after release, before cleanup) ──
& "$PSScriptRoot\discord.ps1" -Version "$v" -Message $Changelog

# Cleanup: keep only the latest 10 releases
$oldReleases = & "C:\Program Files\GitHub CLI\gh.exe" release list -R akingofcrows/pokemon-triad-updates --limit 100 --json tagName --jq '.[].tagName' | Select-Object -Skip 10
foreach ($tag in $oldReleases) {
  Write-Output "  Deleting old release: $tag"
  try { & "C:\Program Files\GitHub CLI\gh.exe" release delete $tag -R akingofcrows/pokemon-triad-updates --yes --cleanup-tag 2>&1 | Out-Null } catch {}
}

Pop-Location; Pop-Location
Write-Output "=== v$v deployed + Discord ==="
