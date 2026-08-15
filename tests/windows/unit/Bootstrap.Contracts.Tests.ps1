BeforeAll {
    $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path

    $installScript = Get-Content (Join-Path $repositoryRoot "scripts/install.ps1") -Raw
    $startScript = Get-Content (Join-Path $repositoryRoot "start.ps1") -Raw
    $installShell = Get-Content (Join-Path $repositoryRoot "scripts/install.sh") -Raw
    $startShell = Get-Content (Join-Path $repositoryRoot "start.sh") -Raw
    $nativeScript = Get-Content (Join-Path $repositoryRoot "setup-windows.ps1") -Raw
    $nativeInstallScript = Get-Content (Join-Path $repositoryRoot "scripts/install-native.ps1") -Raw
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

Describe "Native Windows setup contracts" {
    It "keeps the native Windows entry point in the repository" {
        Test-Path (Join-Path $repositoryRoot "setup-windows.ps1") | Should -BeTrue
        Test-Path (Join-Path $repositoryRoot "requirements-windows.txt") | Should -BeTrue
    }

    It "installs the toolchain through pinned winget package IDs" {
        $nativeScript | Should -Match 'Invoke-WingetInstall -Id "Git\.Git"'
        $nativeScript | Should -Match 'Invoke-WingetInstall -Id "OpenJS\.NodeJS\.LTS"'
        $nativeScript | Should -Match 'Invoke-WingetInstall -Id "Python\.Python\.3\.13"'
        $nativeScript | Should -Match 'Invoke-WingetInstall -Id "Microsoft\.VisualStudioCode"'
    }

    It "installs the Antigravity CLI from the official installer, never npm" {
        $nativeScript | Should -Match 'irm https://antigravity\.google/cli/install\.ps1'
        $nativeScript | Should -Not -Match 'npm install -g antigravity'
    }

    It "has the documented noninteractive seam" {
        $nativeScript | Should -Match "DOCKER_STUDENT_IDE_NONINTERACTIVE"
        $nativeScript | Should -Match 'if \(Test-IsNonInteractive\)'
    }

    It "is Docker-free (no compose, no daemon, no .env mutation)" {
        $nativeScript | Should -Not -Match 'docker compose|docker-compose|docker info'
        $nativeScript | Should -Not -Match 'Update-EnvVar'
    }

    It "enforces version gating for Node and Python" {
        $nativeScript | Should -Match 'function Get-NodeMajorVersion'
        $nativeScript | Should -Match 'function Resolve-PythonLauncher'
        $nativeScript | Should -Match '\$nodeMajor -ge 22'
        $nativeScript | Should -Match 'Python\.Python\.3\.13'
    }
}

Describe "Native Windows installer contracts" {
    It "keeps the native one-liner entry point in the repository" {
        Test-Path (Join-Path $repositoryRoot "scripts/install-native.ps1") | Should -BeTrue
    }

    It "downloads the repository as a ZIP instead of cloning with git" {
        $nativeInstallScript | Should -Match 'archive/refs/heads/main\.zip'
        $nativeInstallScript | Should -Not -Match 'git clone'
    }

    It "enforces TLS 1.2 for PowerShell 5.1 downloads" {
        $nativeInstallScript | Should -Match 'ServicePointManager'
        $nativeInstallScript | Should -Match 'Tls12'
    }

    It "runs setup-windows.ps1 through a child process with execution-policy bypass" {
        $nativeInstallScript | Should -Match 'powershell\.exe -NoProfile -ExecutionPolicy Bypass -File'
        $nativeInstallScript | Should -Match "setup-windows\.ps1"
    }

    It "has the documented noninteractive seam" {
        $nativeInstallScript | Should -Match "DOCKER_STUDENT_IDE_NONINTERACTIVE"
    }
}
