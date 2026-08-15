BeforeAll {
    $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
    $startScript = Join-Path $repositoryRoot "start.ps1"
    $windowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    $originalMachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    . (Join-Path $repositoryRoot "tests/windows/support/TestWorkspace.ps1")
    . (Join-Path $repositoryRoot "tests/windows/support/CommandFake.ps1")
    . (Join-Path $repositoryRoot "tests/windows/support/Invoke-BootstrapScenario.ps1")
    . (Join-Path $repositoryRoot "tests/windows/support/BootstrapDriver.ps1")
    . $startScript

    function New-FakeDir {
        param([string]$Root)
        $dir = Join-Path $Root "fakes"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $dir
    }

    function Invoke-StartScenario {
        param(
            [string]$Workspace,
            [string]$Fakes,
            [string[]]$DriverBody,
            [hashtable]$ExtraEnvironment = @{}
        )
        $driver = New-BootstrapDriver -ScriptPath $startScript -Directory $Workspace -Body $DriverBody
        $environment = @{
            DOCKER_STUDENT_IDE_NONINTERACTIVE = "1"
            TEST_WORKSPACE = $Workspace
            APPDATA = (Join-Path $Workspace "appdata")
            FAKE_DIR = $Fakes
            ORIGINAL_MACHINE_PATH = $originalMachinePath
        }
        foreach ($key in $ExtraEnvironment.Keys) {
            $environment[$key] = $ExtraEnvironment[$key]
        }
        Invoke-BootstrapScenario -ScriptPath $driver -PrependPath @($Fakes) -Environment $environment
    }
}

Describe "S-01 WSL prerequisite" -Tag Unit {
    It "declines installation without attempting Docker or Compose" {
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path
            $wslLog = Join-Path $ws.Path "wsl.log"
            $dockerLog = Join-Path $ws.Path "docker.log"
            $null = New-CommandFake -Name "wsl" -Directory $fakes -LogPath $wslLog -ExitCode 1
            $null = New-CommandFake -Name "docker" -Directory $fakes -LogPath $dockerLog -ExitCode 0

            $result = Invoke-StartScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'Set-Location $env:TEST_WORKSPACE'
                '$code = Invoke-StartBootstrap'
                'exit $code'
            )

            $result.ExitCode | Should -Be 1
            (@(Get-Content $wslLog)).Count | Should -Be 1
            if (Test-Path $dockerLog) {
                (Get-Content $dockerLog -Raw) | Should -Not -Match "compose|info|install"
            }
            ($result.Output -join "`n") | Should -Match "Instala WSL manualmente"
        } finally {
            & $ws.Cleanup
        }
    }
}

Describe "S-03 Docker CLI installation" -Tag Unit {
    It "stops with the CLI guard when winget installs but the CLI stays missing" {
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path
            $wslLog = Join-Path $ws.Path "wsl.log"
            $wingetLog = Join-Path $ws.Path "winget.log"
            $null = New-CommandFake -Name "wsl" -Directory $fakes -LogPath $wslLog -ExitCode 0
            $null = New-CommandFake -Name "winget" -Directory $fakes -LogPath $wingetLog -ExitCode 0

            $result = Invoke-StartScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'Set-Location $env:TEST_WORKSPACE'
                '$code = Invoke-StartBootstrap'
                'exit $code'
            )

            $result.ExitCode | Should -Be 1
            (@(Get-Content $wingetLog)).Count | Should -Be 1
            ($result.Output -join "`n") | Should -Match "Docker CLI not found"
        } finally {
            & $ws.Cleanup
        }
    }

    It "falls back to Chocolatey when winget is unavailable" {
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path
            $wslLog = Join-Path $ws.Path "wsl.log"
            $chocoLog = Join-Path $ws.Path "choco.log"
            $null = New-CommandFake -Name "wsl" -Directory $fakes -LogPath $wslLog -ExitCode 0
            $null = New-CommandFake -Name "choco" -Directory $fakes -LogPath $chocoLog -ExitCode 0

            $result = Invoke-StartScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'function Get-Command {'
                '    param([string]$Name, [string]$ErrorAction)'
                '    if ($Name -eq "winget") { return $null }'
                '    Microsoft.PowerShell.Core\Get-Command @PSBoundParameters'
                '}'
                'Set-Location $env:TEST_WORKSPACE'
                '$code = Invoke-StartBootstrap'
                'exit $code'
            )

            $result.ExitCode | Should -Be 1
            (@(Get-Content $chocoLog)).Count | Should -Be 1
            (Get-Content $chocoLog -Raw) | Should -Match "install docker-desktop -y"
        } finally {
            & $ws.Cleanup
        }
    }

    It "directs to the manual download when every package manager fails" {
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path
            $wslLog = Join-Path $ws.Path "wsl.log"
            $null = New-CommandFake -Name "wsl" -Directory $fakes -LogPath $wslLog -ExitCode 0

            $result = Invoke-StartScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'function Get-Command {'
                '    param([string]$Name, [string]$ErrorAction)'
                '    if ($Name -eq "winget" -or $Name -eq "choco") { return $null }'
                '    Microsoft.PowerShell.Core\Get-Command @PSBoundParameters'
                '}'
                'Set-Location $env:TEST_WORKSPACE'
                '$code = Invoke-StartBootstrap'
                'exit $code'
            )

            $result.ExitCode | Should -Be 1
            ($result.Output -join "`n") | Should -Match "docs.docker.com/desktop/install/windows-install"
        } finally {
            & $ws.Cleanup
        }
    }
}

Describe "S-04 Docker daemon readiness" -Tag Unit {
    It "bounds failed probes and avoids later mutations" {
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path
            $wslLog = Join-Path $ws.Path "wsl.log"
            $dockerLog = Join-Path $ws.Path "docker.log"
            $null = New-CommandFake -Name "wsl" -Directory $fakes -LogPath $wslLog -ExitCode 0
            $null = New-CommandFake -Name "docker" -Directory $fakes -LogPath $dockerLog -ExitCode 1

            $result = Invoke-StartScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'Set-Location $env:TEST_WORKSPACE'
                '$code = Invoke-StartBootstrap -MaxRetries 3 -SleepSeconds 0'
                'exit $code'
            )

            $result.ExitCode | Should -Be 1
            (@(Get-Content $dockerLog | Where-Object { $_ -match "docker info" })).Count | Should -Be 4
            Test-Path (Join-Path $ws.Path ".env") | Should -BeFalse
            (Get-Content $dockerLog -Raw) | Should -Not -Match "compose"
            ($result.Output -join "`n") | Should -Match "Docker did not start"
        } finally {
            & $ws.Cleanup
        }
    }
}

Describe "S-05 Compose v2" -Tag Unit {
    It "fails before any mutation when Compose v2 is missing" {
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path
            $wslLog = Join-Path $ws.Path "wsl.log"
            $dockerLog = Join-Path $ws.Path "docker.log"
            $null = New-CommandFake -Name "wsl" -Directory $fakes -LogPath $wslLog -ExitCode 0
            $extra = if ($windowsHost) {
                'if /I "%1"=="compose" exit /b 1'
            } else {
                '[ "$1" = "compose" ] && exit 1'
            }
            $null = New-CommandFake -Name "docker" -Directory $fakes -LogPath $dockerLog -ExitCode 0 -ExtraScript $extra

            $result = Invoke-StartScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'Set-Location $env:TEST_WORKSPACE'
                '$code = Invoke-StartBootstrap'
                'exit $code'
            )

            $result.ExitCode | Should -Be 1
            Test-Path (Join-Path $ws.Path ".env") | Should -BeFalse
            (Get-Content $dockerLog -Raw) | Should -Match "compose version"
            (Get-Content $dockerLog -Raw) | Should -Not -Match "compose up"
            ($result.Output -join "`n") | Should -Match "compose \(v2\) not available"
        } finally {
            & $ws.Cleanup
        }
    }

    It "writes the env contract and forwards arguments to compose up" {
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path
            $wslLog = Join-Path $ws.Path "wsl.log"
            $dockerLog = Join-Path $ws.Path "docker.log"
            $null = New-CommandFake -Name "wsl" -Directory $fakes -LogPath $wslLog -ExitCode 0
            $null = New-CommandFake -Name "docker" -Directory $fakes -LogPath $dockerLog -ExitCode 0

            $result = Invoke-StartScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'Set-Location $env:TEST_WORKSPACE'
                '$code = Invoke-StartBootstrap -ArgsList @("-d", "--build")'
                'exit $code'
            )

            $result.ExitCode | Should -Be 0
            (Get-Content $dockerLog -Raw) | Should -Match "compose up -d --build"
            $envContent = Get-Content (Join-Path $ws.Path ".env") -Raw
            $envContent | Should -Match "(?m)^PUID=1000"
            $envContent | Should -Match "(?m)^PGID=1000"
        } finally {
            & $ws.Cleanup
        }
    }
}

Describe "S-06 env idempotence" -Tag Unit {
    It "copies .env.example and applies the value when .env is absent" {
        Push-Location $TestDrive
        try {
            Set-Content -Path ".env.example" -Value "PUID=999`nPASSWORD=student"
            Update-EnvVar -VarName "PUID" -Value "1000" -FilePath (Join-Path $TestDrive ".env")
            $content = Get-Content (Join-Path $TestDrive ".env") -Raw
            ($content -split "`n" | Where-Object { $_ -match '^PUID=' }).Count | Should -Be 1
            $content | Should -Match "(?m)^PUID=1000"
            $content | Should -Match "(?m)^PASSWORD=student"
        } finally {
            Pop-Location
        }
    }

    It "preserves unrelated values in an incomplete .env" {
        $path = Join-Path $TestDrive "incomplete.env"
        Set-Content -Path $path -Value "PUID=900`nPASSWORD=student"
        Update-EnvVar -VarName "PGID" -Value "1000" -FilePath $path
        $content = Get-Content -Path $path -Raw
        ($content -split "`n" | Where-Object { $_ -match '^PGID=' }).Count | Should -Be 1
        $content | Should -Match "(?m)^PGID=1000"
        $content | Should -Match "(?m)^PUID=900"
        $content | Should -Match "(?m)^PASSWORD=student"
    }

    It "keeps an already-correct .env byte-identical" {
        $path = Join-Path $TestDrive "correct.env"
        Set-Content -Path $path -Value "PUID=1000`nPGID=1000`nPASSWORD=student"
        $before = Get-Content -Path $path -Raw
        Update-EnvVar -VarName "PUID" -Value "1000" -FilePath $path
        Update-EnvVar -VarName "PGID" -Value "1000" -FilePath $path
        Get-Content -Path $path -Raw | Should -Be $before
    }

    It "is idempotent across a second run" {
        $path = Join-Path $TestDrive "repeat.env"
        Set-Content -Path $path -Value "PASSWORD=student"
        Update-EnvVar -VarName "PUID" -Value "1000" -FilePath $path
        Update-EnvVar -VarName "PGID" -Value "1000" -FilePath $path
        Update-EnvVar -VarName "PUID" -Value "1000" -FilePath $path
        Update-EnvVar -VarName "PGID" -Value "1000" -FilePath $path
        $content = Get-Content -Path $path
        ($content | Where-Object { $_ -match '^PUID=' }).Count | Should -Be 1
        ($content | Where-Object { $_ -match '^PGID=' }).Count | Should -Be 1
        ($content | Where-Object { $_ -match '^PASSWORD=' }).Count | Should -Be 1
    }
}
