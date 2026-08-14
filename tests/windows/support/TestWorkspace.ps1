function New-BootstrapTestWorkspace {
    param([switch]$Repository)

    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("docker-student-ide-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $path -Force | Out-Null

    if ($Repository) {
        Set-Content -Path (Join-Path $path "start.ps1") -Value "# test fixture"
        Set-Content -Path (Join-Path $path "docker-compose.yml") -Value "services: {}"
    }

    [pscustomobject]@{
        Path = $path
        Cleanup = { Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
