param(
  [Parameter(Mandatory=$true)][string]$Version,
  [Parameter(Mandatory=$true)][string]$Message
)

$wh = "https://discord.com/api/webhooks/1530620264746848277/JWAM55LyiuXzhCc2IqRPuQIEtI1SeQp0dWdkhv1J11WNgxBwblw6i0HE68Qnu-c_yO_h"

# Pick random Pokemon sprite for thumbnail
$spriteDir = "$PSScriptRoot\..\assets\sprites\front"
$shinyDir = "$PSScriptRoot\..\assets\sprites\front_shiny"
$allPoke = @(Get-ChildItem $spriteDir -Filter *.png -ErrorAction SilentlyContinue)
if ($allPoke.Count -eq 0) {
  Write-Output "Discord: no sprites found, sending text-only"
  $payload = @{ content = "**v$Version Now Available**`n$Message`nhttps://github.com/akingofcrows/pokemon-triad-updates/releases/tag/v$Version" } | ConvertTo-Json
  Invoke-WebRequest -Uri $wh -Method Post -Body $payload -ContentType "application/json" -UseBasicParsing | Out-Null
  exit 0
}

$hasShiny = (Get-ChildItem $shinyDir -Filter *.png -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
if ($hasShiny -and (Get-Random -Maximum 100) -lt 50) {
  $shinyFiles = @(Get-ChildItem $shinyDir -Filter *.png -ErrorAction SilentlyContinue)
  if ($shinyFiles.Count -gt 0) { $allPoke = $shinyFiles }
}
$thumb = $allPoke | Get-Random

$embed = @{
  title = "v$Version Now Available"
  description = $Message
  color = 0xC9A44C
  url = "https://github.com/akingofcrows/pokemon-triad-updates/releases/tag/v$Version"
  footer = @{ text = "Pokemon Triple Triad - Open the app to update" }
  thumbnail = @{ url = "attachment://$($thumb.Name)" }
}
$payloadJson = @{ embeds = @($embed) } | ConvertTo-Json -Depth 4

try {
  Add-Type -AssemblyName System.Net.Http
  $http = New-Object System.Net.Http.HttpClient
  $form = New-Object System.Net.Http.MultipartFormDataContent
  $form.Add([System.Net.Http.StringContent]::new($payloadJson, [Text.Encoding]::UTF8, "application/json"), "payload_json")
  $fs = [System.IO.File]::OpenRead($thumb.FullName)
  $fc = New-Object System.Net.Http.StreamContent($fs)
  $fc.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue("image/png")
  $form.Add($fc, "file", $thumb.Name)
  $result = $http.PostAsync($wh, $form).Result
  $fs.Dispose(); $http.Dispose()
  Write-Output "Discord: $($thumb.BaseName) thumbnail ($($result.StatusCode))"
} catch {
  Write-Output "Discord: image upload failed ($_), falling back to text"
  $payload = @{ content = "**v$Version Now Available**`n$Message" } | ConvertTo-Json
  Invoke-WebRequest -Uri $wh -Method Post -Body $payload -ContentType "application/json" -UseBasicParsing | Out-Null
}
