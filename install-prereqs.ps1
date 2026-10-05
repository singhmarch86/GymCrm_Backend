# Installs everything a fresh Windows 10/11 laptop needs: Git, Go, Chrome, Docker Desktop, Flutter.
# Run once in an ADMINISTRATOR PowerShell:
#   powershell -ExecutionPolicy Bypass -File .\install-prereqs.ps1
# Then restart the laptop if Docker Desktop was just installed, start Docker Desktop once, open a NEW
# terminal, and run .\setup.ps1.
$FlutterVersion = '3.44.8'      # same version the project was built with
$FlutterDir     = 'C:\dev\flutter'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')) {
  Write-Host "Run this from an Administrator PowerShell (right-click > Run as administrator)."; exit 1
}
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Host "winget not found. Update 'App Installer' from the Microsoft Store (or use Windows 10 21H2+/11), then re-run."; exit 1
}

function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}
function Install-Pkg($id, $cmd) {
  if ($cmd -and (Get-Command $cmd -ErrorAction SilentlyContinue)) { Write-Host "= $id already installed"; return }
  Write-Host "> Installing $id ..."
  winget install -e --id $id --accept-package-agreements --accept-source-agreements --silent
  if ($LASTEXITCODE -ne 0) { Write-Host "  (winget exit $LASTEXITCODE - may already be installed or need a restart)" }
}

Install-Pkg 'Git.Git' 'git'
Install-Pkg 'GoLang.Go' 'go'
Install-Pkg 'Google.Chrome' $null
Install-Pkg 'Docker.DockerDesktop' 'docker'
Refresh-Path

# Flutter: the official install is a git clone of the stable channel, pinned to our version.
if (-not (Test-Path "$FlutterDir\bin\flutter.bat")) {
  Write-Host "> Installing Flutter $FlutterVersion to $FlutterDir ..."
  New-Item -ItemType Directory -Force -Path (Split-Path $FlutterDir) | Out-Null
  git clone https://github.com/flutter/flutter.git $FlutterDir
  git -C $FlutterDir checkout $FlutterVersion
} else { Write-Host "= Flutter already at $FlutterDir" }

$userPath = [Environment]::GetEnvironmentVariable('Path','User')
if ($userPath -notlike "*$FlutterDir\bin*") {
  [Environment]::SetEnvironmentVariable('Path', "$userPath;$FlutterDir\bin", 'User')
  Write-Host "> Added $FlutterDir\bin to your PATH"
}
Refresh-Path

# flutter pub get creates plugin symlinks, which Windows only allows with Developer Mode on.
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v AllowDevelopmentWithoutDevSigning /d 1 | Out-Null
Write-Host "> Developer Mode enabled (needed for Flutter plugins)"

flutter config --enable-web | Out-Null
Write-Host ""
Write-Host "DONE. Next:"
Write-Host "  1. If Docker Desktop was just installed: restart Windows, then start Docker Desktop and accept its prompts (wait until it says 'running')."
Write-Host "  2. Add an SSH key to GitHub if you haven't:  ssh-keygen -t ed25519   then add ~\.ssh\id_ed25519.pub at github.com/settings/keys"
Write-Host "  3. Open a NEW terminal, clone the repo to a folder like C:\dev, and run .\setup.ps1"
