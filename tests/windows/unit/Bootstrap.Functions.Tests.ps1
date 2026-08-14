BeforeAll {
    $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
    . (Join-Path $repositoryRoot "scripts/install.ps1")
    . (Join-Path $repositoryRoot "start.ps1")
}

Describe "Bootstrap test seams" {
    It "detects the explicit noninteractive mode" {
        $originalValue = $env:DOCKER_STUDENT_IDE_NONINTERACTIVE
        try {
            $env:DOCKER_STUDENT_IDE_NONINTERACTIVE = "1"
            Test-IsNonInteractive | Should -BeTrue

            Remove-Item Env:DOCKER_STUDENT_IDE_NONINTERACTIVE -ErrorAction SilentlyContinue
            Test-IsNonInteractive | Should -BeFalse
        } finally {
            if ($null -eq $originalValue) {
                Remove-Item Env:DOCKER_STUDENT_IDE_NONINTERACTIVE -ErrorAction SilentlyContinue
            } else {
                $env:DOCKER_STUDENT_IDE_NONINTERACTIVE = $originalValue
            }
        }
    }

    It "updates an existing env value without duplicating the key" {
        $path = Join-Path $TestDrive "existing.env"
        Set-Content -Path $path -Value "PUID=900`nPGID=800`nPASSWORD=student"

        Update-EnvVar -VarName "PUID" -Value "1000" -FilePath $path

        $content = Get-Content -Path $path
        ($content | Where-Object { $_ -match '^PUID=' }).Count | Should -Be 1
        $content | Should -Contain "PUID=1000"
        $content | Should -Contain "PGID=800"
        $content | Should -Contain "PASSWORD=student"
    }

    It "creates a missing env value" {
        $path = Join-Path $TestDrive "missing.env"

        Update-EnvVar -VarName "PGID" -Value "1000" -FilePath $path

        Get-Content -Path $path | Should -Contain "PGID=1000"
    }

    It "allows Docker polling timing to be controlled by the caller" {
        (Get-Command Wait-DockerDaemon).Parameters.Keys | Should -Contain "MaxRetries"
        (Get-Command Wait-DockerDaemon).Parameters.Keys | Should -Contain "SleepSeconds"
    }
}
