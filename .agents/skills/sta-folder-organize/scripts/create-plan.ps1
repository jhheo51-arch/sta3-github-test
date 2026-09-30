[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [Parameter(Mandatory = $true)][string]$AllowedRootPath,
    [Parameter(Mandatory = $true)][string]$MoveMapPath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

. (Join-Path $PSScriptRoot 'folder-organize-common.ps1')

$target = Resolve-ProjectTarget -TargetPath $TargetPath -AllowedRootPath $AllowedRootPath
$allowedRoot = (Resolve-Path -LiteralPath $AllowedRootPath).Path.TrimEnd('\', '/')
$map = Get-Content -LiteralPath $MoveMapPath -Raw | ConvertFrom-Json
if ($null -eq $map.items -or @($map.items).Count -eq 0) {
    throw '이동표에 items가 없습니다.'
}

$seenSources = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$seenDestinations = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$resolvedItems = @()
$allowedRoles = @('current', 'version', 'package', 'tool', 'qa', 'asset', 'review')
$textExtensions = @('.md', '.txt', '.html', '.htm', '.css', '.js', '.cjs', '.mjs', '.ts', '.tsx', '.jsx', '.json', '.yaml', '.yml', '.ps1', '.py')
$excludedParts = @('node_modules', '.git', 'dist', '.next', '.wrangler', '.vercel', '.cache', 'coverage')

foreach ($item in @($map.items)) {
    $sourceRelative = [string]$item.source
    $destinationRelative = [string]$item.destination
    $role = [string]$item.role
    $reason = [string]$item.reason
    if ([string]::IsNullOrWhiteSpace($sourceRelative) -or [string]::IsNullOrWhiteSpace($destinationRelative)) {
        throw '모든 이동 항목에는 source와 destination이 필요합니다.'
    }
    if ($allowedRoles -notcontains $role) {
        throw "지원하지 않는 역할입니다: $role (허용: $($allowedRoles -join ', '))"
    }
    if ([string]::IsNullOrWhiteSpace($reason)) {
        throw "분류 이유가 필요합니다: $sourceRelative"
    }
    $reviewAfter = $null
    if ($role -eq 'review') {
        if (-not $destinationRelative.Replace('\', '/').StartsWith('review/', [StringComparison]::OrdinalIgnoreCase)) {
            throw "review 역할은 review/ 아래로만 이동할 수 있습니다: $destinationRelative"
        }
        $reviewAfter = [string]$item.reviewAfter
        $parsedReviewDate = [datetime]::MinValue
        if ([string]::IsNullOrWhiteSpace($reviewAfter) -or
            -not [datetime]::TryParseExact($reviewAfter, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedReviewDate)) {
            throw "review 역할에는 yyyy-MM-dd 형식의 reviewAfter가 필요합니다: $sourceRelative"
        }
    }
    if (-not $seenSources.Add($sourceRelative)) { throw "중복 원본: $sourceRelative" }
    if (-not $seenDestinations.Add($destinationRelative)) { throw "중복 대상: $destinationRelative" }

    $source = Resolve-PathInsideTarget -Target $target -RelativePath $sourceRelative
    $destination = Resolve-PathInsideTarget -Target $target -RelativePath $destinationRelative
    if (-not (Test-Path -LiteralPath $source)) { throw "원본 없음: $sourceRelative" }
    if (Test-Path -LiteralPath $destination) { throw "대상 이미 존재: $destinationRelative" }
    if ($source -eq $destination) { throw "원본과 대상이 같습니다: $sourceRelative" }

    $sourceItem = Get-Item -LiteralPath $source -Force
    if ($sourceItem.PSIsContainer) {
        $sourcePrefix = $source.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        if ($destination.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "폴더를 자기 안으로 이동할 수 없습니다: $sourceRelative"
        }
    }

    $fingerprint = Get-ItemFingerprint -Path $source
    $references = @()
    $searchValues = @($sourceRelative.Replace('\', '/'), $sourceRelative.Replace('/', '\')) | Select-Object -Unique
    $candidateTextFiles = @(Get-ChildItem -LiteralPath $target -Recurse -File -Force | Where-Object {
        $relative = $_.FullName.Substring($target.Length).TrimStart('\', '/')
        $parts = $relative -split '[\\/]'
        $_.Length -le 5MB -and $textExtensions -contains $_.Extension.ToLowerInvariant() -and
            -not ($parts | Where-Object { $excludedParts -contains $_ })
    })
    foreach ($textFile in $candidateTextFiles) {
        foreach ($searchValue in $searchValues) {
            $matches = @(Select-String -LiteralPath $textFile.FullName -SimpleMatch -Pattern $searchValue -ErrorAction SilentlyContinue)
            foreach ($match in $matches) {
                $references += [ordered]@{
                    path       = $textFile.FullName.Substring($target.Length).TrimStart('\', '/').Replace('\', '/')
                    lineNumber = $match.LineNumber
                }
            }
        }
    }
    $references = @($references | Sort-Object path, lineNumber -Unique | Select-Object -First 100)
    $resolvedItems += [ordered]@{
        type        = $fingerprint.type
        source      = $sourceRelative.Replace('\', '/')
        destination = $destinationRelative.Replace('\', '/')
        fileCount   = $fingerprint.fileCount
        sizeBytes   = $fingerprint.sizeBytes
        sha256      = $fingerprint.sha256
        role        = $role
        reason      = $reason
        reviewAfter = $reviewAfter
        pathReferences = $references
    }
}

for ($i = 0; $i -lt $resolvedItems.Count; $i++) {
    $left = Resolve-PathInsideTarget -Target $target -RelativePath $resolvedItems[$i].source
    $leftPrefix = $left.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $leftDestination = Resolve-PathInsideTarget -Target $target -RelativePath $resolvedItems[$i].destination
    $leftDestinationPrefix = $leftDestination.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    for ($j = 0; $j -lt $resolvedItems.Count; $j++) {
        if ($i -eq $j) { continue }
        $right = Resolve-PathInsideTarget -Target $target -RelativePath $resolvedItems[$j].source
        $rightDestination = Resolve-PathInsideTarget -Target $target -RelativePath $resolvedItems[$j].destination
        if ($right.StartsWith($leftPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "부모와 자식 원본을 함께 이동할 수 없습니다: $($resolvedItems[$i].source), $($resolvedItems[$j].source)"
        }
        if ($rightDestination.StartsWith($leftDestinationPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "부모와 자식 대상 경로를 함께 사용할 수 없습니다: $($resolvedItems[$i].destination), $($resolvedItems[$j].destination)"
        }
        if ($rightDestination.StartsWith($leftPrefix, [StringComparison]::OrdinalIgnoreCase) -or
            $right.StartsWith($leftDestinationPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "한 항목의 이동이 다른 항목의 원본 또는 대상 안에 들어갈 수 없습니다: $($resolvedItems[$i].source), $($resolvedItems[$j].destination)"
        }
    }
}

$output = Resolve-PathInsideTarget -Target $target -RelativePath ([IO.Path]::GetRelativePath($target, [IO.Path]::GetFullPath($OutputPath)))
$plan = [ordered]@{
    schemaVersion    = 2
    mode             = 'draft-move-plan'
    target           = $target
    allowedRoot      = $allowedRoot
    createdAt        = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
    deletionPlanned  = $false
    overwritePlanned = $false
    items            = @($resolvedItems)
}

Write-NewUtf8Json -Value $plan -Path $output
$planFileSha256 = Get-FileSha256 -Path $output
[ordered]@{
    plan = $plan
    approval = [ordered]@{
        planPath       = $output
        planFileSha256 = $planFileSha256
        instruction    = '사용자에게 이동표와 이 확인값을 함께 보여주고, 승인받은 뒤 같은 확인값으로 실행하세요.'
    }
} | ConvertTo-Json -Depth 12
