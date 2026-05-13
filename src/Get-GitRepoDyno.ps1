param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath,

    [Parameter(Mandatory = $true)]
    [datetime]$Since,

    [string]$AuthorName = ""
)

function Invoke-Git {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $output = & git @Arguments 2>$null
    [pscustomobject]@{
        Output = @($output)
        ExitCode = $LASTEXITCODE
    }
}

$resolvedRepoPath = (Resolve-Path -LiteralPath $RepoPath).Path

Push-Location -LiteralPath $resolvedRepoPath
try {
    $branchResult = Invoke-Git branch --show-current
    $branch = $null
    if ($branchResult.ExitCode -eq 0 -and $branchResult.Output.Count -gt 0) {
        $branch = [string]$branchResult.Output[0]
    }

    if ([string]::IsNullOrWhiteSpace($branch)) {
        $branchResult = Invoke-Git symbolic-ref --short HEAD
        if ($branchResult.ExitCode -eq 0 -and $branchResult.Output.Count -gt 0) {
            $branch = [string]$branchResult.Output[0]
        }
    }

    if ([string]::IsNullOrWhiteSpace($branch)) {
        $branchResult = Invoke-Git rev-parse --abbrev-ref HEAD
        if ($branchResult.ExitCode -eq 0 -and $branchResult.Output.Count -gt 0) {
            $branch = [string]$branchResult.Output[0]
        }
    }

    $statusResult = Invoke-Git status --porcelain
    $dirty = $statusResult.ExitCode -eq 0 -and $statusResult.Output.Count -gt 0
    $headResult = Invoke-Git rev-parse --verify HEAD
    $hasCommits = $headResult.ExitCode -eq 0

    $commitsToday = 0
    $unpushedCommits = 0
    $behindUpstream = 0
    $latestCommit = $null
    $notes = @()

    if ($hasCommits) {
        $sinceText = $Since.ToString("o")
        $logArgs = @("log", "--since=$sinceText", "--format=%H")
        if (-not [string]::IsNullOrWhiteSpace($AuthorName)) {
            $logArgs += "--author=$AuthorName"
        }

        $commitsTodayResult = Invoke-Git @logArgs
        if ($commitsTodayResult.ExitCode -eq 0) {
            $commitsToday = @($commitsTodayResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
        }

        $upstreamResult = Invoke-Git rev-parse --abbrev-ref --symbolic-full-name "@{upstream}"
        if ($upstreamResult.ExitCode -eq 0 -and $upstreamResult.Output.Count -gt 0) {
            $aheadBehindResult = Invoke-Git rev-list --left-right --count "HEAD...@{upstream}"
            if ($aheadBehindResult.ExitCode -eq 0 -and $aheadBehindResult.Output.Count -gt 0) {
                $parts = ([string]$aheadBehindResult.Output[0]).Trim() -split "\s+"
                if ($parts.Count -ge 2) {
                    [void][int]::TryParse($parts[0], [ref]$unpushedCommits)
                    [void][int]::TryParse($parts[1], [ref]$behindUpstream)
                }
            }
        }

        $latestCommitResult = Invoke-Git log -1 --format="%H%n%s%n%cI"
        if ($latestCommitResult.ExitCode -eq 0 -and $latestCommitResult.Output.Count -ge 3) {
            $latestCommit = [pscustomobject]@{
                hash = [string]$latestCommitResult.Output[0]
                message = [string]$latestCommitResult.Output[1]
                time = [string]$latestCommitResult.Output[2]
            }
        }
    }
    else {
        $notes += "Git repository has no commits yet."
    }

    $touchedToday = if ($hasCommits) { $commitsToday -gt 0 } else { $dirty }

    [pscustomobject]@{
        name = Split-Path -Leaf $resolvedRepoPath
        path = $resolvedRepoPath
        branch = $branch
        hasCommits = $hasCommits
        touchedToday = $touchedToday
        commitsToday = $commitsToday
        dirty = $dirty
        unpushedCommits = $unpushedCommits
        behindUpstream = $behindUpstream
        latestCommit = $latestCommit
        notes = $notes
    }
}
finally {
    Pop-Location
}
