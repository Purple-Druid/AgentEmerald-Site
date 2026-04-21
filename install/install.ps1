# install.ps1 — AgentEmerald installer for Windows (PowerShell)
#
# Usage (run in an elevated PowerShell window):
#   irm https://raw.githubusercontent.com/Purple-Druid/AgentEmerald/main/install.ps1 | iex
#
# Or with options:
#   $env:AGEM_INSTALL_DIR = "$HOME\AppData\Local\agem"
#   irm .../install.ps1 | iex
#
# Options (set as env vars before piping):
#   AGEM_INSTALL_DIR     Install directory (default: $HOME\bin)
#   AGEM_VERSION         Release tag to install (default: latest)
#   AGEM_SKIP_GH         Set to "1" to skip GitHub CLI check
#   AGEM_SKIP_NODE       Set to "1" to skip Node.js check
#   AGEM_CLEAN_INSTALL   Set to "1" to remove existing install before installing

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"  # faster Invoke-WebRequest

# ── Config ─────────────────────────────────────────────────────────────
$InstallDir    = if ($env:AGEM_INSTALL_DIR)    { $env:AGEM_INSTALL_DIR }    else { "$HOME\bin" }
$Version       = if ($env:AGEM_VERSION)       { $env:AGEM_VERSION }       else { "latest" }
$SkipGh        = $env:AGEM_SKIP_GH        -eq "1"
$SkipNode      = $env:AGEM_SKIP_NODE      -eq "1"
$CleanInstall  = $env:AGEM_CLEAN_INSTALL  -eq "1"
$MinNode    = 20
$Repo       = "Purple-Druid/AgentEmerald"

# ── Helpers ─────────────────────────────────────────────────────────────
function Info    { Write-Host "  → $args" -ForegroundColor Cyan }
function Success { Write-Host "  ✓ $args" -ForegroundColor Green }
function Warn    { Write-Host "  ⚠ $args" -ForegroundColor Yellow }
function Banner  { Write-Host "`n$args" -ForegroundColor White }
function Die     { Write-Host "  ✗ $args" -ForegroundColor Red; exit 1 }

function Test-Command($cmd) {
  $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)
}

function Get-NodeMajor {
  try { (node --version).TrimStart("v").Split(".")[0] -as [int] } catch { 0 }
}

# ── Node.js ─────────────────────────────────────────────────────────────
Banner "Checking Node.js"

if (-not $SkipNode) {
  if (Test-Command node) {
    $major = Get-NodeMajor
    if ($major -lt $MinNode) {
      Warn "Node.js $major found but >= $MinNode is required."
      Warn "Please install Node.js from https://nodejs.org (LTS) then re-run."
      exit 1
    }
    Success "Node.js $(node --version) (>= $MinNode ✓)"
  } else {
    Warn "Node.js not found."
    if (Test-Command winget) {
      Info "Installing Node.js LTS via winget…"
      winget install OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements
      # Refresh PATH
      $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                  [System.Environment]::GetEnvironmentVariable("PATH", "User")
      if (-not (Test-Command node)) {
        Die "Node.js installation failed. Install from https://nodejs.org then re-run."
      }
      Success "Node.js $(node --version) installed"
    } else {
      Warn "winget not available. Install Node.js >= $MinNode from https://nodejs.org then re-run."
      exit 1
    }
  }
} else {
  Info "Skipping Node.js check (AGEM_SKIP_NODE=1)"
}

# ── pnpm ─────────────────────────────────────────────────────────────────
Banner "Checking pnpm"

if (-not (Test-Command pnpm)) {
  Info "Installing pnpm…"
  if (Test-Command npm) {
    npm install -g pnpm
  } else {
    # pnpm standalone installer
    Invoke-WebRequest -UseBasicParsing "https://get.pnpm.io/install.ps1" | Invoke-Expression
    $env:PNPM_HOME = "$HOME\.pnpm"
    $env:PATH = "$env:PNPM_HOME;$env:PATH"
  }
}

if (Test-Command pnpm) {
  Success "pnpm $(pnpm --version)"
} else {
  Die "pnpm installation failed. Install from https://pnpm.io/installation then re-run."
}

# ── GitHub CLI ───────────────────────────────────────────────────────────
Banner "Checking GitHub CLI"

if (-not $SkipGh) {
  if (-not (Test-Command gh)) {
    Info "Installing GitHub CLI via winget…"
    if (Test-Command winget) {
      winget install GitHub.cli --silent --accept-package-agreements --accept-source-agreements
      $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                  [System.Environment]::GetEnvironmentVariable("PATH", "User")
    } else {
      Warn "winget not available. Install GitHub CLI from https://cli.github.com"
    }
  }

  if (Test-Command gh) {
    Success "gh $(gh --version | Select-Object -First 1 | ForEach-Object { ($_ -split " ")[2] })"
    try {
      gh auth status 2>&1 | Out-Null
      Success "GitHub CLI authenticated ✓"
    } catch {
      Warn "GitHub CLI not authenticated. Run: gh auth login"
    }
  }
} else {
  Info "Skipping GitHub CLI check (AGEM_SKIP_GH=1)"
}

# ── Fetch & build AgentEmerald ───────────────────────────────────────────
Banner "Installing AgentEmerald"

$WorkDir = Join-Path $env:TEMP "agem-install-$(Get-Random)"
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

try {
  # Resolve version
  if ($Version -eq "latest") {
    Info "Fetching latest release info…"
    try {
      $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest"
      $Version = $rel.tag_name
    } catch {
      Warn "Could not fetch latest release. Falling back to main branch."
      $Version = "main"
    }
  }

  Info "Installing version: $Version"

  # Clone
  if (-not (Test-Command git)) {
    Die "git is required. Install from https://git-scm.com"
  }

  Info "Cloning repository…"
  $cloneArgs = @("clone", "--depth", "1")
  if ($Version -ne "main") { $cloneArgs += @("--branch", $Version) }
  $cloneArgs += @("https://github.com/$Repo.git", (Join-Path $WorkDir "AgentEmerald"))
  & git @cloneArgs 2>&1 | Out-Null

  $RepoDir = Join-Path $WorkDir "AgentEmerald"
  Set-Location $RepoDir

  Info "Installing dependencies…"
  pnpm install --frozen-lockfile 2>&1 | Select-Object -Last 3 | ForEach-Object { Info $_ }

  Info "Building…"
  pnpm run build 2>&1 | Select-Object -Last 3 | ForEach-Object { Info $_ }

  Info "Bundling…"
  pnpm run bundle 2>&1 | Select-Object -Last 3 | ForEach-Object { Info $_ }

  # ── Install ──────────────────────────────────────────────────────────
  Banner "Installing binary"

  New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

  # Copy bundle
  Copy-Item (Join-Path $RepoDir "dist\agem.js") (Join-Path $InstallDir "agem.js") -Force

  # Write package.json so Node treats the bundle as ESM without re-parsing
  Set-Content (Join-Path $InstallDir "package.json") '{"type":"module"}'

  # Copy copilot SDK
  $copilotSrc  = Join-Path $RepoDir "node_modules\@github\copilot"
  $copilotDest = Join-Path $InstallDir "node_modules\@github"
  New-Item -ItemType Directory -Path $copilotDest -Force | Out-Null
  if (Test-Path (Join-Path $copilotDest "copilot")) {
    Remove-Item (Join-Path $copilotDest "copilot") -Recurse -Force
  }
  Copy-Item $copilotSrc (Join-Path $copilotDest "copilot") -Recurse -Force

  # Write .cmd launcher for Windows PATH resolution
  $launcher = Join-Path $InstallDir "agem.cmd"
  Set-Content $launcher "@echo off`nnode `"%~dp0agem.js`" %*"

  Success "agem installed to $InstallDir"
  Success "Launcher: $launcher"

} finally {
  Set-Location $HOME
  Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ── Clean install ─────────────────────────────────────────────────────────
if ($CleanInstall) {
  Banner "Cleaning existing installation"
  $cleanTargets = @(
    (Join-Path $InstallDir "agem.cmd"),
    (Join-Path $InstallDir "agem.js"),
    (Join-Path $InstallDir "package.json"),
    (Join-Path $InstallDir "node_modules\@github\copilot")
  )
  $removed = 0
  foreach ($target in $cleanTargets) {
    if (Test-Path $target) {
      Info "Removing: $target"
      Remove-Item $target -Recurse -Force
      $removed++
    }
  }
  # Prune empty parent dirs
  $ghDir = Join-Path $InstallDir "node_modules\@github"
  if ((Test-Path $ghDir) -and ((Get-ChildItem $ghDir -ErrorAction SilentlyContinue).Count -eq 0)) {
    Remove-Item $ghDir -Force -ErrorAction SilentlyContinue
  }
  $nmDir = Join-Path $InstallDir "node_modules"
  if ((Test-Path $nmDir) -and ((Get-ChildItem $nmDir -ErrorAction SilentlyContinue).Count -eq 0)) {
    Remove-Item $nmDir -Force -ErrorAction SilentlyContinue
  }
  if ($removed -eq 0) { Info "No existing installation found in $InstallDir" }
  else { Success "Removed $removed item(s) from $InstallDir" }
}

Banner "Finalising"

$userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$InstallDir*") {
  Warn "$InstallDir is not in your PATH."
  Info "Adding it to your user PATH permanently…"
  [System.Environment]::SetEnvironmentVariable(
    "PATH",
    "$userPath;$InstallDir",
    "User"
  )
  $env:PATH = "$env:PATH;$InstallDir"
  Success "PATH updated. Changes take effect in new terminals."
} else {
  Success "$InstallDir is already in PATH ✓"
}

# ── Done ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Agent Emerald is installed!" -ForegroundColor Green
Write-Host ""

if (-not (Test-Command gh) -or -not (& gh auth status 2>&1)) {
  Write-Host "  1. Authenticate with GitHub: " -NoNewline
  Write-Host "gh auth login" -ForegroundColor Cyan
  Write-Host "  2. Launch the TUI:           " -NoNewline
  Write-Host "agem" -ForegroundColor Cyan
} else {
  Write-Host "  → Launch the TUI: " -NoNewline
  Write-Host "agem" -ForegroundColor Cyan
}
Write-Host "  Docs: https://github.com/$Repo#readme" -ForegroundColor DarkGray
Write-Host ""
