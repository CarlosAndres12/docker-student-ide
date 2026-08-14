BeforeAll {
    $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path

    $installScript = Get-Content (Join-Path $repositoryRoot "scripts/install.ps1") -Raw
    $startScript = Get-Content (Join-Path $repositoryRoot "start.ps1") -Raw
    $installShell = Get-Content (Join-Path $repositoryRoot "scripts/install.sh") -Raw
    $startShell = Get-Content (Join-Path $repositoryRoot "start.sh") -Raw
}

Describe "Windows bootstrap contracts" {
    It "keeps the Windows entry points in the repository" {
        Test-Path (Join-Path $repositoryRoot "scripts/install.ps1") | Should -BeTrue
        Test-Path (Join-Path $repositoryRoot "start.ps1") | Should -BeTrue
    }

    It "runs start.ps1 through a child process with execution policy bypass" {
        $installScript | Should -Match "powershell\.exe -NoProfile -ExecutionPolicy Bypass -File"
    }

    It "forwards installer arguments to the child script" {
        $installScript | Should -Match 'Invoke-ChildPowerShell -ScriptPath \(Join-Path \$PWD ''start\.ps1''\) -ArgsList \$ArgsList'
    }

    It "has a documented noninteractive seam in both PowerShell scripts" {
        $installScript | Should -Match "DOCKER_STUDENT_IDE_NONINTERACTIVE"
        $startScript | Should -Match "DOCKER_STUDENT_IDE_NONINTERACTIVE"
        $startScript | Should -Match 'if \(Test-IsNonInteractive\)'
    }

    It "bounds Docker readiness polling to five minutes" {
        $startScript | Should -Match '\[int\]\$MaxRetries = 60'
        $startScript | Should -Match 'Wait-DockerDaemon -MaxRetries \$MaxRetries -SleepSeconds \$SleepSeconds'
    }

    It "checks Compose v2 before starting the stack" {
        $startScript | Should -Match 'docker compose version'
        $startScript | Should -Match 'docker compose up'
    }

    It "preserves shell-wrapper argument forwarding" {
        $installShell | Should -Match 'exec sh start\.sh "\$@"'
        $startShell | Should -Match 'docker compose up "\$@"'
    }

    It "keeps the Windows UID/GID contract" {
        $startScript | Should -Match 'Update-EnvVar -VarName "PUID" -Value "1000"'
        $startScript | Should -Match 'Update-EnvVar -VarName "PGID" -Value "1000"'
    }
}
