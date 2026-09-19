[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PlanPath,
    [Parameter(Mandatory = $true)][string]$ApprovedPlanSha256,
    [Parameter(Mandatory = $true)][string]$VerificationPath,
    [Parameter(Mandatory = $true)][string]$ProgressPath,
    [switch]$Resume,
    [switch]$Approved
)

. (Join-Path $PSScriptRoot 'folder-organize-common.ps1')

if (-not $Approved) {
    throw '이동하려면 사용자의 계획 승인을 확인하고 -Approved를 지정해야 합니다.'
}

$actualPlanSha256 = Get-FileSha256 -Path $PlanPath
if ($actualPlanSha256 -ne $ApprovedPlanSha256) {
    throw '승인된 계획 확인값과 현재 계획 파일이 다릅니다. 변경된 계획을 다시 보여주고 승인받아야 합니다.'
}

$plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json
if ($plan.schemaVersion -ne 2 -or $plan.mode -ne 'draft-move-plan' -or $plan.deletionPlanned -ne $false -or $plan.overwritePlanned -ne $false) {
    throw '지원하지 않거나 안전하지 않은 이동 계획입니다.'
}

$target = Resolve-ProjectTarget -TargetPath ([string]$plan.target) -AllowedRootPath ([string]$plan.allowedRoot)
$verification = Resolve-PathInsideTarget -Target $target -RelativePath ([IO.Path]::GetRelativePath($target, [IO.Path]::GetFullPath($VerificationPath)))
$progress = Resolve-PathInsideTarget -Target $target -RelativePath ([IO.Path]::GetRelativePath($target, [IO.Path]::GetFullPath($ProgressPath)))
if (Test-Path -LiteralPath $verification) {
    throw "검증 파일을 덮어쓸 수 없습니다: $verification"
}
if ((Test-Path -LiteralPath $progress) -and -not $Resume) {
    throw "진행 기록이 이미 있습니다. 같은 계획을 이어가려면 -Resume을 지정하세요: $progress"
}
if (-not (Test-Path -LiteralPath $progress) -and $Resume) {
    throw "이어갈 진행 기록이 없습니다: $progress"
}
if ($Resume) {
    $progressEvents = @(Get-Content -LiteralPath $progress | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
    if ($progressEvents.Count -eq 0 -or $progressEvents[0].event -ne 'started' -or
        $progressEvents[0].planFileSha256 -ne $actualPlanSha256) {
        throw '진행 기록이 현재 승인 계획과 연결되지 않습니다.'
    }
    if (@($progressEvents | Where-Object { $_.event -eq 'completed' }).Count -gt 0) {
        throw '이미 완료된 진행 기록은 재개할 수 없습니다.'
    }
}
if (-not $Resume) {
    Add-JsonLine -Path $progress -Value ([ordered]@{
        event = 'started'; occurredAt = (Get-Date).ToString('o'); planFileSha256 = $actualPlanSha256
    })
}

$prepared = @()
try {
foreach ($item in @($plan.items)) {
    $source = Resolve-PathInsideTarget -Target $target -RelativePath ([string]$item.source)
    $destination = Resolve-PathInsideTarget -Target $target -RelativePath ([string]$item.destination)
    $sourceExists = Test-Path -LiteralPath $source
    $destinationExists = Test-Path -LiteralPath $destination
    if ($Resume -and -not $sourceExists -and $destinationExists) {
        $after = Get-ItemFingerprint -Path $destination
        if ($after.type -eq $item.type -and $after.fileCount -eq $item.fileCount -and
            $after.sizeBytes -eq $item.sizeBytes -and $after.sha256 -eq $item.sha256) {
            $prepared += [pscustomobject]@{ planItem = $item; source = $source; destination = $destination; alreadyMoved = $true }
            continue
        }
    }
    if (-not $sourceExists) { throw "원본 없음: $($item.source)" }
    if ($destinationExists) { throw "대상 이미 존재: $($item.destination)" }

    $fingerprint = Get-ItemFingerprint -Path $source
    if ($fingerprint.type -ne $item.type -or $fingerprint.fileCount -ne $item.fileCount -or
        $fingerprint.sizeBytes -ne $item.sizeBytes -or $fingerprint.sha256 -ne $item.sha256) {
        throw "계획 생성 후 원본이 달라졌습니다: $($item.source)"
    }

    $prepared += [pscustomobject]@{
        planItem    = $item
        source      = $source
        destination = $destination
        alreadyMoved = $false
    }
}
}
catch {
    Add-JsonLine -Path $progress -Value ([ordered]@{
        event = 'preflight-failed'; occurredAt = (Get-Date).ToString('o'); message = $_.Exception.Message
    })
    throw
}

$results = @()
foreach ($entry in $prepared) {
    if ($entry.alreadyMoved) {
        $results += [ordered]@{
            source = $entry.planItem.source; destination = $entry.planItem.destination
            status = 'previously-moved-unchanged'; beforeSha256 = $entry.planItem.sha256; afterSha256 = $entry.planItem.sha256
        }
        continue
    }
    $parent = Split-Path -Parent $entry.destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }

    try {
        Move-Item -LiteralPath $entry.source -Destination $entry.destination
        $after = Get-ItemFingerprint -Path $entry.destination
    }
    catch {
        Add-JsonLine -Path $progress -Value ([ordered]@{
            event = 'failed'; occurredAt = (Get-Date).ToString('o'); source = $entry.planItem.source
            destination = $entry.planItem.destination; message = $_.Exception.Message
        })
        throw
    }
    $unchanged = $after.type -eq $entry.planItem.type -and
        $after.fileCount -eq $entry.planItem.fileCount -and
        $after.sizeBytes -eq $entry.planItem.sizeBytes -and
        $after.sha256 -eq $entry.planItem.sha256 -and
        -not (Test-Path -LiteralPath $entry.source)

    $results += [ordered]@{
        source       = $entry.planItem.source
        destination  = $entry.planItem.destination
        status       = if ($unchanged) { 'moved-unchanged' } else { 'unexpected-difference' }
        beforeSha256 = $entry.planItem.sha256
        afterSha256  = $after.sha256
    }

    Add-JsonLine -Path $progress -Value ([ordered]@{
        event = if ($unchanged) { 'moved-unchanged' } else { 'unexpected-difference' }
        occurredAt = (Get-Date).ToString('o'); source = $entry.planItem.source
        destination = $entry.planItem.destination; sha256 = $after.sha256
    })

    if (-not $unchanged) {
        throw "이동 후 확인값이 다릅니다. 추가 이동을 중단합니다: $($entry.planItem.destination)"
    }
}

$report = [ordered]@{
    schemaVersion = 2
    mode          = 'post-move-verification'
    target        = $target
    verifiedAt    = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
    summary       = [ordered]@{
        plannedItems  = @($plan.items).Count
        movedUnchanged = @($results | Where-Object { $_.status -eq 'moved-unchanged' }).Count
        resumedUnchanged = @($results | Where-Object { $_.status -eq 'previously-moved-unchanged' }).Count
        failures       = @($results | Where-Object { $_.status -notin @('moved-unchanged', 'previously-moved-unchanged') }).Count
        moveIntegrity  = 'passed'
        pathUpdates    = 'pending-external-check'
        functionalTests = 'pending-external-check'
        userCheck      = 'pending'
    }
    items         = @($results)
}

Write-NewUtf8Json -Value $report -Path $verification
Add-JsonLine -Path $progress -Value ([ordered]@{
    event = 'completed'; occurredAt = (Get-Date).ToString('o'); verificationPath = $verification
})
$report | ConvertTo-Json -Depth 10
