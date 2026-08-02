param(
  [string]$Version,
  [Parameter(Mandatory=$true)] [string]$Changelog
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path $PSScriptRoot -Parent
Push-Location $scriptRoot

# ── Read current version from pubspec ────────────────────────────────────
$pubspec = Get-Content pubspec.yaml -Raw
$current = [regex]::Match($pubspec, 'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)')
if (-not $current.Success) { throw "Cannot parse pubspec.yaml version" }
$major = [int]$current.Groups[1].Value
$minor = [int]$current.Groups[2].Value
$patch = [int]$current.Groups[3].Value
$build = [int]$current.Groups[4].Value

if (-not $Version) {
  $newPatch = $patch + 1
  $newMinor = $minor
  $newMajor = $major
  if ($newPatch -gt 99) { $newMinor++; $newPatch = 0 }
  if ($newMinor -gt 99) { $newMajor++; $newMinor = 0 }
  $Version = "$newMajor.$newMinor.$newPatch"
}

$newBuild = $build + 1

Write-Output "=== v$($major).$minor.$patch -> v$Version ==="

# ── Bump pubspec.yaml ────────────────────────────────────────────────────
$pubspec = $pubspec -replace 'version:\s*\d+\.\d+\.\d+\+\d+', "version: $Version+$newBuild"
Set-Content pubspec.yaml -Value $pubspec -NoNewline

# ── Build APK ────────────────────────────────────────────────────────────
Write-Output "Building APK..."
flutter build apk --release
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "server\app-release.apk" -Force

# ── Update server files ──────────────────────────────────────────────────
Push-Location server

$update = [ordered]@{
  version = $Version
  apk_url = "PLACEHOLDER"
  changelog = $Changelog
}
($update | ConvertTo-Json -Depth 2).Replace('"PLACEHOLDER"', '""') | Set-Content update.json -NoNewline
# Fix: put a real placeholder value
$json = Get-Content update.json -Raw
$json = $json -replace '""', '"https://github.com/akingofcrows/pokemon-triad-updates/releases/download/v__VERSION__/app-release.apk"'
$json = $json -replace 'v__VERSION__', "v$Version"
Set-Content update.json -Value $json -NoNewline

git add update.json app-release.apk
git commit -m "v$Version : $Changelog"
git push

# ── Create GitHub release ───────────────────────────────────────────────
Write-Output "Creating GitHub release..."
gh release create "v$Version" app-release.apk --title "v$Version" --notes $Changelog -R akingofcrows/pokemon-triad-updates

# ── Get the actual asset URL ─────────────────────────────────────────────
$asset = gh release view "v$Version" -R akingofcrows/pokemon-triad-updates --json assets --jq '.assets[0].url'
Write-Output "Asset: $asset"

# Update apk_url with the real URL
$json = Get-Content update.json -Raw
$json = $json -replace "https://github.com/akingofcrows/pokemon-triad-updates/releases/download/v$Version/app-release.apk", $asset
Set-Content update.json -Value $json -NoNewline

git add update.json
git commit -m "Set apk_url for v$Version"
git push

# ── Purge CDN ────────────────────────────────────────────────────────────
Write-Output "Purging CDN..."
Invoke-WebRequest "https://purge.jsdelivr.net/gh/akingofcrows/pokemon-triad-updates@main/update.json" -UseBasicParsing | Out-Null

# ── Post to Discord ──────────────────────────────────────────────────────
$webhook = "https://discord.com/api/webhooks/1530620264746848277/JWAM55LyiuXzhCc2IqRPuQIEtI1SeQp0dWdkhv1J11WNgxBwblw6i0HE68Qnu-c_yO_h"
$embed = @{
  title = "v$Version Now Available"
  description = $Changelog
  color = 0xC9A44C
  url = "https://github.com/akingofcrows/pokemon-triad-updates/releases/tag/v$Version"
  footer = @{ text = "Pokémon Triple Triad - Open the app to update" }
  timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
} | ConvertTo-Json -Depth 3

$body = @{ embeds = @( $embed | ConvertFrom-Json ) } | ConvertTo-Json -Depth 4
$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
Invoke-RestMethod -Uri $webhook -Method Post -Body $bodyBytes -ContentType "application/json; charset=utf-8" | Out-Null
Write-Output "Posted to Discord"

Pop-Location
Pop-Location

Write-Output "=== v$Version deployed! ==="
Write-Output "Changelog: $Changelog"

