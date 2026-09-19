[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath,

    [string]$AllowedRootPath,

    [ValidateRange(1, 50)]
    [int]$CandidateLimit = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$excludedDirectoryNames = @(
    'node_modules', '.git', 'dist', '.next', '.wrangler', '.vercel',
    '.cache', 'coverage', '.vinext', '.open-next'
)

. (Join-Path $PSScriptRoot 'folder-organize-common.ps1')
$resolvedTarget = Resolve-ProjectTarget -TargetPath $TargetPath -AllowedRootPath $AllowedRootPath

function Test-ManagedPath {
    param([string]$FullName)

    $relative = $FullName.Substring($resolvedTarget.Length).TrimStart('\', '/')
    if ([string]::IsNullOrWhiteSpace($relative)) {
        return $true
    }

    $parts = $relative -split '[\\/]'
    return -not ($parts | Where-Object { $excludedDirectoryNames -contains $_ })
}

function Get-VersionInfo {
    param([string]$Name)

    $matches = [regex]::Matches($Name, '(?i)(?:^|[-_])v(?<number>\d+)(?<suffix>[a-z]?)')
    if ($matches.Count -eq 0) {
        return $null
    }

    $match = $matches[$matches.Count - 1]
    [pscustomobject]@{
        label  = 'v' + $match.Groups['number'].Value + $match.Groups['suffix'].Value.ToLowerInvariant()
        number = [int]$match.Groups['number'].Value
        suffix = $match.Groups['suffix'].Value.ToLowerInvariant()
    }
}

function Convert-ToCandidate {
    param(
        [System.IO.FileSystemInfo]$Item,
        [string]$Kind
    )

    $version = Get-VersionInfo -Name $Item.Name
    if ($null -eq $version) {
        return $null
    }

    [pscustomobject]@{
        kind          = $Kind
        path          = $Item.FullName.Substring($resolvedTarget.Length).TrimStart('\', '/')
        version       = $version.label
        versionNumber = $version.number
        suffix        = $version.suffix
        modifiedAt    = $Item.LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
        isDirectory   = $Item.PSIsContainer
    }
}

$allFiles = @(Get-ChildItem -LiteralPath $resolvedTarget -Recurse -File -Force -ErrorAction Stop)
$managedFiles = @($allFiles | Where-Object { Test-ManagedPath -FullName $_.FullName })
$managedDirectories = @(Get-ChildItem -LiteralPath $resolvedTarget -Recurse -Directory -Force -ErrorAction Stop |
    Where-Object { Test-ManagedPath -FullName $_.FullName })
$emptyDirectories = @($managedDirectories | Where-Object {
    @(Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction Stop).Count -eq 0
} | ForEach-Object { $_.FullName.Substring($resolvedTarget.Length).TrimStart('\', '/').Replace('\', '/') })

$duplicateGroups = @($managedFiles | Group-Object Length | Where-Object { $_.Count -gt 1 } | ForEach-Object {
    $_.Group | ForEach-Object {
        [pscustomobject]@{
            path = $_.FullName.Substring($resolvedTarget.Length).TrimStart('\', '/').Replace('\', '/')
            sizeBytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    } | Group-Object sha256 | Where-Object { $_.Count -gt 1 } | ForEach-Object {
        [pscustomobject]@{
            sha256 = $_.Name
            sizeBytes = $_.Group[0].sizeBytes
            paths = @($_.Group.path | Sort-Object)
        }
    }
})

$candidates = @()
$candidates += $managedFiles |
    Where-Object { $_.Extension -ieq '.html' } |
    ForEach-Object { Convert-ToCandidate -Item $_ -Kind 'html' }
$candidates += $managedFiles |
    Where-Object { $_.Extension -ieq '.md' -and $_.Name -match '(?i)(PRD|기획서)' } |
    ForEach-Object { Convert-ToCandidate -Item $_ -Kind 'prd' }
$candidates += $managedFiles |
    Where-Object { $_.Name -match '(?i)\.(?:zip|tar\.gz)$' } |
    ForEach-Object { Convert-ToCandidate -Item $_ -Kind 'package' }
$candidates += $managedDirectories |
    Where-Object { $_.Name -match '(?i)^site-v\d+[a-z]?$' } |
    ForEach-Object { Convert-ToCandidate -Item $_ -Kind 'site' }
$candidates = @($candidates | Where-Object { $null -ne $_ })

$latestByKind = [ordered]@{}
foreach ($kind in @('html', 'prd', 'site', 'package')) {
    $items = @($candidates | Where-Object { $_.kind -eq $kind } |
        Sort-Object -Property @{ Expression = 'versionNumber'; Descending = $true },
        @{ Expression = 'suffix'; Descending = $true },
        @{ Expression = 'modifiedAt'; Descending = $true })
    if ($items.Count -gt 0) {
        $latestByKind[$kind] = @($items | Select-Object -First $CandidateLimit)
    }
}

$topLevel = @(Get-ChildItem -LiteralPath $resolvedTarget -Force | Sort-Object Name | ForEach-Object {
    if ($_.PSIsContainer) {
        [pscustomobject]@{
            name              = $_.Name
            type              = 'directory'
            directFiles       = @(Get-ChildItem -LiteralPath $_.FullName -File -Force -ErrorAction Stop).Count
            directDirectories = @(Get-ChildItem -LiteralPath $_.FullName -Directory -Force -ErrorAction Stop).Count
        }
    }
    else {
        [pscustomobject]@{
            name      = $_.Name
            type      = 'file'
            sizeBytes = $_.Length
        }
    }
})

$warnings = [System.Collections.Generic.List[string]]::new()
if ((Test-Path -LiteralPath (Join-Path $resolvedTarget 'index.html') -PathType Leaf) -and $latestByKind.Contains('html')) {
    $warnings.Add('최상위 index.html과 버전 표시 HTML이 함께 있습니다. 이름만으로 최신본을 확정하지 마세요.')
}
if ((Test-Path -LiteralPath (Join-Path $resolvedTarget 'current')) -and $candidates.Count -gt 0) {
    $warnings.Add('current 폴더와 버전 후보가 함께 있습니다. current의 내용이 실제 최신본인지 문서 또는 검사로 확인하세요.')
}

$hasCurrent = Test-Path -LiteralPath (Join-Path $resolvedTarget 'current') -PathType Container
$hasReadme = Test-Path -LiteralPath (Join-Path $resolvedTarget 'README.md') -PathType Leaf
$structureStatus = if ($hasCurrent -and $hasReadme) { 'already-organized-candidate' } else { 'needs-review' }
$suggestedAction = if ($structureStatus -eq 'already-organized-candidate') {
    'README의 최신본 근거와 기능 검사만 확인하고, 변경할 항목이 없으면 이동 계획을 만들지 마세요.'
} else {
    '항목을 current, version, package, tool, qa, asset, review 또는 판단불가로 분류하세요.'
}

$allBytes = ($allFiles | Measure-Object -Property Length -Sum).Sum
$managedBytes = ($managedFiles | Measure-Object -Property Length -Sum).Sum
if ($null -eq $allBytes) { $allBytes = 0 }
if ($null -eq $managedBytes) { $managedBytes = 0 }

$result = [ordered]@{
    schemaVersion         = 2
    mode                  = 'read-only-inventory'
    target                = $resolvedTarget
    generatedAt           = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
    writeActionsPerformed = 0
    structureStatus       = $structureStatus
    suggestedAction       = $suggestedAction
    reviewCandidates      = [ordered]@{
        emptyDirectories = @($emptyDirectories)
        duplicateGroups  = @($duplicateGroups)
        instruction      = '자동 삭제하지 말고 역할을 확인한 뒤 필요하면 review/ 이동 계획에만 포함하세요.'
    }
    excludedDirectoryNames = $excludedDirectoryNames
    counts = [ordered]@{
        allFiles     = $allFiles.Count
        managedFiles = $managedFiles.Count
        excludedFiles = $allFiles.Count - $managedFiles.Count
        allBytes     = [int64]$allBytes
        managedBytes = [int64]$managedBytes
    }
    topLevel       = $topLevel
    suggestedLatest = $latestByKind
    warnings       = @($warnings)
}

$result | ConvertTo-Json -Depth 8
