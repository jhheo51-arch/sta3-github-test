Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ProjectTarget {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [string]$AllowedRootPath
    )

    $resolved = (Resolve-Path -LiteralPath $TargetPath).Path.TrimEnd('\', '/')
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "대상 프로젝트 폴더를 찾을 수 없습니다: $TargetPath"
    }

    $root = [IO.Path]::GetPathRoot($resolved).TrimEnd('\', '/')
    if ($resolved -eq $root) {
        throw '드라이브 루트는 정리 대상으로 사용할 수 없습니다.'
    }

    if (-not [string]::IsNullOrWhiteSpace($AllowedRootPath)) {
        $allowedRoot = (Resolve-Path -LiteralPath $AllowedRootPath).Path.TrimEnd('\', '/')
        if (-not (Test-Path -LiteralPath $allowedRoot -PathType Container)) {
            throw "허용된 상위 폴더를 찾을 수 없습니다: $AllowedRootPath"
        }
        $allowedPrefix = $allowedRoot + [IO.Path]::DirectorySeparatorChar
        if ($resolved -ne $allowedRoot -and -not $resolved.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "정리 대상이 허용된 상위 폴더 밖에 있습니다: $resolved"
        }
        if ($resolved -eq $allowedRoot) {
            throw '허용된 상위 폴더 전체는 정리 대상으로 사용할 수 없습니다. 그 안의 프로젝트 하나를 지정하세요.'
        }
    }

    return $resolved
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Add-JsonLine {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $json = $Value | ConvertTo-Json -Depth 10 -Compress
    [IO.File]::AppendAllText($Path, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

function Resolve-PathInsideTarget {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if ([IO.Path]::IsPathRooted($RelativePath)) {
        throw "절대 경로는 이동표에 사용할 수 없습니다: $RelativePath"
    }

    $normalizedTarget = [IO.Path]::GetFullPath($Target).TrimEnd('\', '/')
    $candidate = [IO.Path]::GetFullPath((Join-Path $normalizedTarget $RelativePath))
    $prefix = $normalizedTarget + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "프로젝트 밖 경로는 사용할 수 없습니다: $RelativePath"
    }

    return $candidate
}

function Get-DirectoryFingerprint {
    param([Parameter(Mandatory = $true)][string]$Path)

    $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force | Sort-Object FullName)
    $lines = [Collections.Generic.List[string]]::new()
    $totalBytes = [int64]0

    foreach ($file in $files) {
        $relative = $file.FullName.Substring($Path.Length).TrimStart('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        $lines.Add("$relative|$($file.Length)|$hash")
        $totalBytes += $file.Length
    }

    $payload = [Text.Encoding]::UTF8.GetBytes([string]::Join([Environment]::NewLine, $lines))
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $fingerprint = [BitConverter]::ToString($sha.ComputeHash($payload)).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }

    [pscustomobject]@{
        type      = 'directory'
        fileCount = $files.Count
        sizeBytes = $totalBytes
        sha256    = $fingerprint
    }
}

function Get-ItemFingerprint {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer) {
        return Get-DirectoryFingerprint -Path $item.FullName
    }

    [pscustomobject]@{
        type      = 'file'
        fileCount = 1
        sizeBytes = [int64]$item.Length
        sha256    = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
    }
}

function Write-NewUtf8Json {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        throw "기존 파일을 덮어쓸 수 없습니다: $Path"
    }

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw "출력할 상위 폴더가 없습니다: $parent"
    }

    $json = $Value | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}
