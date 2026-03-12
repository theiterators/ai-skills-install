$ErrorActionPreference = "Stop"

$Repo = "theiterators/ai-skills"
$TmpDir = Join-Path $env:TEMP "ai-skills-$PID"
$HomeDir = $env:USERPROFILE
$ItDir = Join-Path $HomeDir ".iterators"
$VersionFile = Join-Path $ItDir "ai-skills-version.json"
$Command = if ($args.Count -gt 0) { $args[0] } else { "init" }

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

function Write-VersionMarker {
    param([string]$Tools)
    New-Item -ItemType Directory -Path $ItDir -Force | Out-Null
    $pkg = Get-Content (Join-Path $TmpDir "package.json") -Raw | ConvertFrom-Json
    $version = if ($pkg.version) { $pkg.version } else { "unknown" }
    $marker = @{
        version = $version
        installedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        tools = $Tools
    } | ConvertTo-Json
    Set-Content -Path $VersionFile -Value $marker
}

function Invoke-Init {
    Show-Banner
    Write-Host "Downloading latest skills..."
    Clone-Repo
    Write-Host ""

    $selected = @()

    $tools = @(
        @{ key = "claude";  name = "Claude Code";     dir = Join-Path $HomeDir ".claude" },
        @{ key = "copilot"; name = "GitHub Copilot";   dir = Join-Path $HomeDir ".github\copilot" },
        @{ key = "cursor";  name = "Cursor";           dir = Join-Path $HomeDir ".cursor" }
    )

    foreach ($tool in $tools) {
        if (Ask-YN "Install for $($tool.name)?") {
            Copy-ToTool -ToolName $tool.name -ToolDir $tool.dir
            $selected += $tool.key
        }
        Write-Host ""
    }

    if ($selected.Count -eq 0) {
        Write-Host "No tools selected. Nothing to install."
        Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
        return
    }

    Write-VersionMarker -Tools ($selected -join ",")

    # Offer Jira token setup
    Write-Host ""
    $envFile = Join-Path $ItDir ".env"
    if ((Test-Path $envFile) -and (Select-String -Path $envFile -Pattern "JIRA_API_TOKEN" -Quiet)) {
        Write-Host "Jira token: already configured in ~/.iterators/.env"
    } elseif (Ask-YN "Set up Jira API token now?") {
        Write-Host ""
        Write-Host "  Get your token at: https://id.atlassian.com/manage-profile/security/api-tokens"
        Write-Host ""
        $token = Read-Host "  Paste your Jira API token"
        if ($token) {
            New-Item -ItemType Directory -Path $ItDir -Force | Out-Null
            Set-Content -Path $envFile -Value "JIRA_API_TOKEN=$token"
            Write-Host "  [+] Token saved to ~/.iterators/.env"
        } else {
            Write-Host "  Skipped - you can set it later with /it-setup"
        }
    }

    Write-Host ""
    Write-Host "--- Done! ---"
    Write-Host "Tools: $($selected -join ', ')"
    Write-Host ""
    Write-Host "Next: run /it-setup in your project to configure Jira."

    Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
}

function Invoke-Update {
    Show-Banner

    if (-not (Test-Path $VersionFile)) {
        Write-Error "No previous installation found. Run 'init' first."
        exit 1
    }

    $marker = Get-Content $VersionFile -Raw | ConvertFrom-Json
    $tools = $marker.tools -split ","
    Write-Host "Previous tools: $($marker.tools)"
    Write-Host "Downloading latest skills..."
    Clone-Repo
    Write-Host ""

    $toolMap = @{
        claude  = @{ name = "Claude Code";   dir = Join-Path $HomeDir ".claude" }
        copilot = @{ name = "GitHub Copilot"; dir = Join-Path $HomeDir ".github\copilot" }
        cursor  = @{ name = "Cursor";         dir = Join-Path $HomeDir ".cursor" }
    }

    foreach ($t in $tools) {
        if ($toolMap.ContainsKey($t)) {
            Copy-ToTool -ToolName $toolMap[$t].name -ToolDir $toolMap[$t].dir
        } else {
            Write-Host "  [!] Unknown tool: $t, skipping."
        }
    }

    Write-VersionMarker -Tools $marker.tools
    Write-Host ""
    Write-Host "--- Updated! ---"

    Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
}

function Invoke-Doctor {
    Show-Banner
    $issues = 0

    Write-Host "Checking skills..."
    $skills = @("it-brainstorming", "it-start-task", "it-code-review", "it-setup")
    foreach ($skill in $skills) {
        $dir = Join-Path $HomeDir ".claude\skills\$skill"
        if (Test-Path $dir) {
            Write-Host "  [ok] $skill"
        } else {
            Write-Host "  [!!] $skill - not found at $dir"
            $issues++
        }
    }

    Write-Host ""
    Write-Host "Checking jira.sh..."
    $jiraPath = Join-Path $HomeDir ".claude\scripts\jira.sh"
    if (Test-Path $jiraPath) {
        Write-Host "  [ok] $jiraPath"
    } else {
        Write-Host "  [!!] $jiraPath - not found"
        $issues++
    }

    Write-Host ""
    Write-Host "Checking Jira token..."
    $envFile = Join-Path $ItDir ".env"
    if ($env:JIRA_API_TOKEN) {
        Write-Host "  [ok] JIRA_API_TOKEN is set (environment)"
    } elseif ((Test-Path $envFile) -and (Select-String -Path $envFile -Pattern "JIRA_API_TOKEN" -Quiet)) {
        Write-Host "  [ok] JIRA_API_TOKEN found in ~/.iterators/.env"
    } else {
        Write-Host "  [!!] JIRA_API_TOKEN not found"
        Write-Host "       Run install.ps1 init or /it-setup to configure"
        $issues++
    }

    Write-Host ""
    Write-Host "Version marker..."
    if (Test-Path $VersionFile) {
        Get-Content $VersionFile
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
