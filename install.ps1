$ErrorActionPreference = "Stop"

$Repo = "theiterators/ai-skills"
$TmpDir = Join-Path $env:TEMP "ai-skills-$PID"
$HomeDir = $env:USERPROFILE
$Command = if ($args.Count -gt 0) { $args[0] } else { "init" }

# Scope-dependent variables (set by Resolve-Scope)
$script:BaseDir = $null
$script:ItDir = $null
$script:VersionFile = $null

function Show-Banner {
    Write-Host ""
    Write-Host "============================================"
    Write-Host "  Iterators AI Skills Installer"
    Write-Host "============================================"
    Write-Host ""
}

function Clone-Repo {
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        Write-Host "Cloning via gh..."
        gh repo clone $Repo $TmpDir -- --depth=1 -q
    } elseif (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Host "Cloning via git SSH..."
        git clone --depth=1 -q "git@github.com:${Repo}.git" $TmpDir
    } else {
        Write-Error "gh or git is required. Install gh: https://cli.github.com"
        exit 1
    }
}

function Copy-ToTool {
    param([string]$ToolName, [string]$ToolDir)

    $dirs = @("skills", "references", "scripts")
    foreach ($d in $dirs) {
        $src = Join-Path $TmpDir $d
        $dest = Join-Path $ToolDir $d
        if (Test-Path $src) {
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            Copy-Item -Path "$src\*" -Destination $dest -Recurse -Force
            Write-Host "  [+] ${ToolName}: $d -> $dest"
        }
    }
}

function Ask-YN {
    param([string]$Prompt, [string]$Default = "n")
    $answer = Read-Host "$Prompt (y/n) [$Default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
    return $answer -match "^[Yy]"
}

function Resolve-Scope {
    param([string]$Scope)
    if ($Scope -eq "project") {
        $script:BaseDir = (Get-Location).Path
    } else {
        $script:BaseDir = $HomeDir
    }
    $script:ItDir = Join-Path $script:BaseDir ".iterators"
    $script:VersionFile = Join-Path $script:ItDir "ai-skills-version.json"
}

function Get-ToolDir {
    param([string]$Tool)
    switch ($Tool) {
        "claude"  { return Join-Path $script:BaseDir ".claude" }
        "copilot" { return Join-Path $script:BaseDir ".github\copilot" }
        "cursor"  { return Join-Path $script:BaseDir ".cursor" }
    }
}

function Write-VersionMarker {
    param([string]$Tools, [string]$Scope)
    New-Item -ItemType Directory -Path $script:ItDir -Force | Out-Null
    $pkgPath = Join-Path $TmpDir "package.json"
    $version = "unknown"
    if (Test-Path $pkgPath) {
        $pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json
        if ($pkg.version) { $version = $pkg.version }
    }
    $marker = @{
        version = $version
        installedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        tools = $Tools
        scope = $Scope
    } | ConvertTo-Json
    Set-Content -Path $script:VersionFile -Value $marker
}

function Detect-Scope {
    # Per-project version file takes priority
    $projectVf = Join-Path (Get-Location).Path ".iterators\ai-skills-version.json"
    $globalVf = Join-Path $HomeDir ".iterators\ai-skills-version.json"

    if (Test-Path $projectVf) {
        Resolve-Scope "project"
        return $true
    } elseif (Test-Path $globalVf) {
        Resolve-Scope "global"
        return $true
    }
    return $false
}

function Invoke-Init {
    Show-Banner
    Write-Host "Where do you want to install skills?"
    Write-Host ""
    Write-Host "  1) Globally     - into ~/  (available in all projects)"
    Write-Host "  2) Per-project  - into current directory ($(Get-Location))"
    Write-Host ""
    $scopeChoice = Read-Host "Choose [1/2]"

    $scope = if ($scopeChoice -eq "2") { "project" } else { "global" }
    Resolve-Scope $scope

    Write-Host ""
    Write-Host "Downloading latest skills..."
    Clone-Repo
    Write-Host ""

    $selected = @()

    $tools = @(
        @{ key = "claude";  name = "Claude Code" },
        @{ key = "copilot"; name = "GitHub Copilot" },
        @{ key = "cursor";  name = "Cursor" }
    )

    foreach ($tool in $tools) {
        if (Ask-YN "Install for $($tool.name)?") {
            Copy-ToTool -ToolName $tool.name -ToolDir (Get-ToolDir $tool.key)
            $selected += $tool.key
        }
        Write-Host ""
    }

    if ($selected.Count -eq 0) {
        Write-Host "No tools selected. Nothing to install."
        Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
        return
    }

    Write-VersionMarker -Tools ($selected -join ",") -Scope $scope

    # Offer Jira credentials setup (always in home dir)
    Write-Host ""
    $credDir = Join-Path $HomeDir ".iterators"
    $envFile = Join-Path $credDir ".env"
    if ((Test-Path $envFile) -and (Select-String -Path $envFile -Pattern "JIRA_EMAIL" -Quiet) -and (Select-String -Path $envFile -Pattern "JIRA_API_TOKEN" -Quiet)) {
        Write-Host "Jira credentials: already configured in ~/.iterators/.env"
    } elseif (Ask-YN "Set up Jira credentials now?") {
        New-Item -ItemType Directory -Path $credDir -Force | Out-Null
        Write-Host ""
        $jiraEmail = Read-Host "  Your Jira email"
        Write-Host ""
        Write-Host "  Get your token at: https://id.atlassian.com/manage-profile/security/api-tokens"
        Write-Host ""
        $jiraToken = Read-Host "  Paste your Jira API token"
        if ($jiraEmail -and $jiraToken) {
            Set-Content -Path $envFile -Value "JIRA_EMAIL=$jiraEmail`nJIRA_API_TOKEN=$jiraToken"
            Write-Host "  [+] Credentials saved to ~/.iterators/.env"
        } else {
            Write-Host "  Skipped - you can set it later with /it-setup"
        }
    }

    Write-Host ""
    Write-Host "--- Done! ---"
    Write-Host "Scope: $scope"
    Write-Host "Tools: $($selected -join ', ')"

    if ($scope -eq "project") {
        Write-Host ""
        Write-Host "NOTE: Skills installed into $(Get-Location)"
        Write-Host "  You need to run this installer from your project directory."
        Write-Host "  To update, run this script with 'update' from the same directory."
        Write-Host "  Consider adding the installed directories to .gitignore or committing them."
    }

    Write-Host ""
    Write-Host "Next: run /it-setup in your project to configure Jira."

    Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
}

function Invoke-Update {
    Show-Banner

    if (-not (Detect-Scope)) {
        Write-Error "No previous installation found. Run 'init' first, or cd into a project with a per-project install."
        exit 1
    }

    $marker = Get-Content $script:VersionFile -Raw | ConvertFrom-Json
    $scope = if ($marker.scope) { $marker.scope } else { "global" }
    $tools = $marker.tools -split ","

    Write-Host "Scope: $scope"
    Write-Host "Previous tools: $($marker.tools)"
    Write-Host "Downloading latest skills..."
    Clone-Repo
    Write-Host ""

    foreach ($t in $tools) {
        $dir = Get-ToolDir $t
        if ($dir) {
            $toolName = switch ($t) {
                "claude"  { "Claude Code" }
                "copilot" { "GitHub Copilot" }
                "cursor"  { "Cursor" }
                default   { $null }
            }
            if ($toolName) {
                Copy-ToTool -ToolName $toolName -ToolDir $dir
            } else {
                Write-Host "  [!] Unknown tool: $t, skipping."
            }
        } else {
            Write-Host "  [!] Unknown tool: $t, skipping."
        }
    }

    Write-VersionMarker -Tools $marker.tools -Scope $scope
    Write-Host ""
    Write-Host "--- Updated! ---"

    Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
}

function Invoke-Doctor {
    Show-Banner
    $issues = 0

    if (-not (Detect-Scope)) {
        Write-Host "No installation found (checked current directory and global)."
        Write-Host "Run 'install.ps1' first."
        exit 1
    }

    $marker = Get-Content $script:VersionFile -Raw | ConvertFrom-Json
    $scope = if ($marker.scope) { $marker.scope } else { "global" }
    Write-Host "Scope: $scope (base: $script:BaseDir)"
    Write-Host ""

    Write-Host "Checking skills..."
    $skills = @("it-brainstorming", "it-start-task", "it-code-review", "it-setup")
    foreach ($skill in $skills) {
        $dir = Join-Path $script:BaseDir ".claude\skills\$skill"
        if (Test-Path $dir) {
            Write-Host "  [ok] $skill"
        } else {
            Write-Host "  [!!] $skill - not found at $dir"
            $issues++
        }
    }

    Write-Host ""
    Write-Host "Checking jira scripts..."
    $jiraPath = Join-Path $script:BaseDir ".claude\scripts\jira.sh"
    if (Test-Path $jiraPath) {
        Write-Host "  [ok] $jiraPath"
    } else {
        Write-Host "  [!!] $jiraPath - not found"
        $issues++
    }
    $jiraPsPath = Join-Path $script:BaseDir ".claude\scripts\jira.ps1"
    if (Test-Path $jiraPsPath) {
        Write-Host "  [ok] $jiraPsPath"
    } else {
        Write-Host "  [!!] $jiraPsPath - not found"
        $issues++
    }

    Write-Host ""
    Write-Host "Checking Jira credentials..."
    $credDir = Join-Path $HomeDir ".iterators"
    $envFile = Join-Path $credDir ".env"
    if ($env:JIRA_API_TOKEN) {
        Write-Host "  [ok] JIRA_API_TOKEN is set (environment)"
    } elseif ((Test-Path $envFile) -and (Select-String -Path $envFile -Pattern "JIRA_API_TOKEN" -Quiet)) {
        Write-Host "  [ok] JIRA_API_TOKEN found in ~/.iterators/.env"
    } else {
        Write-Host "  [!!] JIRA_API_TOKEN not found"
        Write-Host "       Run install.ps1 init or /it-setup to configure"
        $issues++
    }
    if ((Test-Path $envFile) -and (Select-String -Path $envFile -Pattern "JIRA_EMAIL" -Quiet)) {
        Write-Host "  [ok] JIRA_EMAIL found in ~/.iterators/.env"
    } else {
        Write-Host "  [!!] JIRA_EMAIL not found"
        $issues++
    }

    Write-Host ""
    Write-Host "Version marker..."
    if (Test-Path $script:VersionFile) {
        Get-Content $script:VersionFile
    } else {
        Write-Host "  [!!] No version marker found"
        $issues++
    }

    Write-Host ""
    if ($issues -eq 0) {
        Write-Host "All checks passed!"
    } else {
        Write-Host "Found $issues issue(s). Run install.ps1 to fix."
    }
}

switch ($Command) {
    "init"   { Invoke-Init }
    "update" { Invoke-Update }
    "doctor" { Invoke-Doctor }
    default  {
        Write-Host "Unknown command: $Command"
        Write-Host "Usage: install.ps1 [init|update|doctor]"
        exit 1
    }
}
