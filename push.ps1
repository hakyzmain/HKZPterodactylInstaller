#Requires -Version 5.1
param(
  [string]$RepoPath = $PSScriptRoot,
  [string]$Message = "UPDATED",
  [string]$Description = "hakyz btw",
  [string]$AuthorName = "hakyzmain",
  [string]$AuthorEmail = "hakyzmain@users.noreply.github.com",
  [switch]$NoDescription
)

$ErrorActionPreference = "Stop"

$GitExe = @(
  "$env:ProgramFiles\Git\cmd\git.exe",
  "${env:ProgramFiles(x86)}\Git\cmd\git.exe",
  "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $GitExe) {
  throw "git.exe not found. Install Git for Windows."
}

$RepoPath = (Resolve-Path $RepoPath).Path
Set-Location $RepoPath

function Invoke-Git {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
  & $GitExe -C $RepoPath @GitArgs
  if ($LASTEXITCODE -ne 0) {
    throw ("git failed ({0}): git {1}" -f $LASTEXITCODE, ($GitArgs -join " "))
  }
}

Write-Host "git: $GitExe"
Write-Host "repo: $RepoPath"

$env:GIT_AUTHOR_NAME = $AuthorName
$env:GIT_AUTHOR_EMAIL = $AuthorEmail
$env:GIT_COMMITTER_NAME = $AuthorName
$env:GIT_COMMITTER_EMAIL = $AuthorEmail
$env:GIT_EDITOR = "true"
Remove-Item Env:GIT_TRAILER_INFO -ErrorAction SilentlyContinue

Invoke-Git config user.name $AuthorName
Invoke-Git config user.email $AuthorEmail
Invoke-Git config trailer.ifexists doNothing

$status = & $GitExe -C $RepoPath status --porcelain
if ($status) {
  Invoke-Git add -A
  $commitArgs = @(
    "-c", "trailer.ifexists=doNothing",
    "commit",
    "--cleanup=strip",
    "-m", $Message
  )
  & $GitExe -C $RepoPath @commitArgs
  if ($LASTEXITCODE -ne 0) {
    throw ("git commit failed ({0})" -f $LASTEXITCODE)
  }
  Write-Host "commit: $Message"
} else {
  Write-Host "no local changes"
}

$branch = (& $GitExe -C $RepoPath rev-parse --abbrev-ref HEAD).Trim()
if (-not $branch) { $branch = "main" }

$remote = & $GitExe -C $RepoPath remote
if ($remote -notcontains "origin") {
  throw "remote 'origin' missing"
}

Invoke-Git push -u origin ("HEAD:{0}" -f $branch)

$log = (& $GitExe -C $RepoPath log -1 --format="%H%n%an <%ae>%n%B").Trim()
if ($log -match "cursoragent|Co-authored-by:\s*Cursor") {
  throw "cursoragent detected in commit - abort"
}
Write-Host $log

if (-not $NoDescription) {
  $url = (& $GitExe -C $RepoPath remote get-url origin).Trim()
  if ($url -match "github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+)") {
    $owner = $Matches.owner
    $repo = $Matches.repo
    if (Get-Command gh -ErrorAction SilentlyContinue) {
      gh repo edit "$owner/$repo" --description $Description | Out-Null
      Write-Host "description: $Description"
    } else {
      Write-Warning "gh not found - skip description"
    }
  }
}

Write-Host "ok"
