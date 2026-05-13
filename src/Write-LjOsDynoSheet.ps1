param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
)

function Resolve-ConfiguredPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    [Environment]::ExpandEnvironmentVariables($Path)
}

function Get-DefaultRepoIgnoreNames {
    @(
        '$RECYCLE.BIN',
        'System Volume Information',
        'node_modules',
        '.git',
        'vendor'
    )
}

function New-RepoIgnoreNameSet {
    param(
        [string[]]$RepoIgnoreNames
    )

    $ignoredNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @((Get-DefaultRepoIgnoreNames) + @($RepoIgnoreNames))) {
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            [void]$ignoredNames.Add($name.Trim())
        }
    }

    $ignoredNames
}

function Test-IsBlockedSystemPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $normalizedPath = "\$(($Path -replace '/', '\').TrimEnd('\'))\"

    $normalizedPath -like '*\$RECYCLE.BIN\*' -or
        $normalizedPath -like '*\System Volume Information\*'
}

function Get-ConfiguredGitRepos {
    param(
        [string[]]$RepoRoots,
        [string[]]$RepoIgnoreNames
    )

    $ignoredNames = New-RepoIgnoreNameSet -RepoIgnoreNames $RepoIgnoreNames
    $seen = @{}
    $repos = New-Object System.Collections.Generic.List[string]

    foreach ($root in $RepoRoots) {
        if ([string]::IsNullOrWhiteSpace($root)) {
            continue
        }

        $resolvedRoot = Resolve-ConfiguredPath -Path $root
        if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
            Write-Warning "Repo root not found: $resolvedRoot"
            continue
        }

        $pending = New-Object System.Collections.Generic.Stack[string]
        $pending.Push((Resolve-Path -LiteralPath $resolvedRoot).Path)

        while ($pending.Count -gt 0) {
            $currentPath = $pending.Pop()
            if (Test-IsBlockedSystemPath -Path $currentPath) {
                continue
            }

            $currentName = Split-Path -Leaf $currentPath
            if (-not [string]::IsNullOrWhiteSpace($currentName) -and $ignoredNames.Contains($currentName)) {
                continue
            }

            $childDirs = @(Get-ChildItem -LiteralPath $currentPath -Force -Directory -ErrorAction SilentlyContinue)
            $hasGitDir = @($childDirs | Where-Object { $_.Name -ieq ".git" }).Count -gt 0

            if ($hasGitDir) {
                $resolvedRepoPath = (Resolve-Path -LiteralPath $currentPath).Path
                if (-not (Test-IsBlockedSystemPath -Path $resolvedRepoPath)) {
                    $key = $resolvedRepoPath.ToLowerInvariant()
                    if (-not $seen.ContainsKey($key)) {
                        $seen[$key] = $true
                        $repos.Add($resolvedRepoPath)
                    }
                }
            }

            foreach ($childDir in $childDirs) {
                if ($ignoredNames.Contains($childDir.Name)) {
                    continue
                }

                if (Test-IsBlockedSystemPath -Path $childDir.FullName) {
                    continue
                }

                $pending.Push($childDir.FullName)
            }
        }
    }

    $repos | Sort-Object
}

function Get-RepoPropertySum {
    param(
        [object[]]$Repos,
        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    $sum = 0
    foreach ($repo in @($Repos)) {
        if ($null -ne $repo -and $null -ne $repo.$PropertyName) {
            $sum += [int]$repo.$PropertyName
        }
    }

    $sum
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Config file not found: $ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace([string]$config.vaultPath)) {
    throw "Config is missing vaultPath."
}

$today = Get-Date
$date = $today.ToString("yyyy-MM-dd")
$since = $today.Date
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$getRepoDynoScript = Join-Path -Path $scriptDir -ChildPath "Get-GitRepoDyno.ps1"

$repoRoots = @($config.repoRoots)
$repoIgnoreNames = @($config.repoIgnoreNames)
$authorName = [string]$config.authorName
$includeReposWithNoActivity = [bool]$config.includeReposWithNoActivity
$includeEmptyRepos = $false
if ($config.PSObject.Properties.Name -contains "includeEmptyRepos") {
    $includeEmptyRepos = [bool]$config.includeEmptyRepos
}

$repoPaths = @(Get-ConfiguredGitRepos -RepoRoots $repoRoots -RepoIgnoreNames $repoIgnoreNames)
$allRepos = foreach ($repoPath in $repoPaths) {
    & $getRepoDynoScript -RepoPath $repoPath -Since $since -AuthorName $authorName
}

$repos = @($allRepos)
if (-not $includeReposWithNoActivity) {
    $repos = @(
        $allRepos | Where-Object {
            if (-not $_.hasCommits) {
                $_.dirty -or $includeEmptyRepos
            }
            else {
                $_.touchedToday -or
                $_.dirty -or
                $_.unpushedCommits -gt 0 -or
                $_.behindUpstream -gt 0
            }
        }
    )
}

$summary = [pscustomobject]@{
    reposScanned = @($allRepos).Count
    reposIncluded = @($repos).Count
    reposTouchedToday = @($allRepos | Where-Object { $_.touchedToday }).Count
    commitsToday = Get-RepoPropertySum -Repos $allRepos -PropertyName "commitsToday"
    dirtyRepos = @($allRepos | Where-Object { $_.dirty }).Count
    unpushedCommits = Get-RepoPropertySum -Repos $allRepos -PropertyName "unpushedCommits"
    behindCommits = Get-RepoPropertySum -Repos $allRepos -PropertyName "behindUpstream"
}

$sheet = [pscustomobject]@{
    schemaVersion = "0.1.0"
    date = $date
    generatedAt = $today.ToString("o")
    source = "obsidian-lj-os-cli"
    machine = [pscustomobject]@{
        name = [Environment]::MachineName
        user = [Environment]::UserName
    }
    summary = $summary
    repos = $repos
    notes = @()
}

$vaultPath = Resolve-ConfiguredPath -Path ([string]$config.vaultPath)
$statsOutputPath = [string]$config.statsOutputPath
if ([string]::IsNullOrWhiteSpace($statsOutputPath)) {
    $outputDir = $vaultPath
}
else {
    $outputDir = Join-Path -Path $vaultPath -ChildPath $statsOutputPath
}

New-Item -Path $outputDir -ItemType Directory -Force | Out-Null

$outputPath = Join-Path -Path $outputDir -ChildPath "$date.json"
$sheet | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPath -Encoding UTF8

$outputPath
