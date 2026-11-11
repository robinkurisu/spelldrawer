# Points Umbrella's deadlock_scripts at a checkout, so the loader runs that worktree.
# Run it from the worktree you want loaded:  .\link.ps1
# Or name one:                               .\link.ps1 C:\path\to\worktree
param([string]$Target = $PSScriptRoot)
$ErrorActionPreference = 'Stop'

$link = "$env:APPDATA\hnEjgwFIDmRDFzdc\deadlock_scripts"
$Target = (Resolve-Path -LiteralPath $Target).Path
if (-not (Test-Path -LiteralPath "$Target\spelldrawer.lua")) { throw "no spelldrawer.lua in $Target" }

# non-recursive: removes a link (even a dangling one), but throws on a real folder with files in it
try { [IO.Directory]::Delete($link) } catch [IO.DirectoryNotFoundException] {}
# a junction, not a symlink: needs no admin rights
New-Item -ItemType Junction -Path $link -Target $Target | Out-Null
"deadlock_scripts -> $Target"
