BeforeAll {
    $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
    $installScript = Join-Path $repositoryRoot "scripts/install.ps1"
    $windowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    $originalMachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    . (Join-Path $repositoryRoot "tests/windows/support/TestWorkspace.ps1")
    . (Join-Path $repositoryRoot "tests/windows/support/CommandFake.ps1")
    . (Join-Path $repositoryRoot "tests/windows/support/Invoke-BootstrapScenario.ps1")
    . (Join-Path $repositoryRoot "tests/windows/support/BootstrapDriver.ps1")

    function New-FakeDir {
        param([string]$Root)
        $dir = Join-Path $Root "fakes"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $dir
    }

    function Invoke-InstallerScenario {
        param(
            [string]$Workspace,
            [string]$Fakes,
            [string[]]$DriverBody,
            [hashtable]$ExtraEnvironment = @{}
        )
        $driver = New-BootstrapDriver -ScriptPath $installScript -Directory $Workspace -Body $DriverBody
        $environment = @{
            DOCKER_STUDENT_IDE_NONINTERACTIVE = "1"
            TEST_WORKSPACE = $Workspace
            FAKE_DIR = $Fakes
            ORIGINAL_MACHINE_PATH = $originalMachinePath
        }
        foreach ($key in $ExtraEnvironment.Keys) {
            $environment[$key] = $ExtraEnvironment[$key]
        }
        Invoke-BootstrapScenario -ScriptPath $driver -PrependPath @($Fakes) -Environment $environment
    }
}

Describe "I-01 install from an empty directory" -Tag Unit {
    It "clones into the requested workspace and forwards startup arguments" {
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path
            $gitLog = Join-Path $ws.Path "git.log"
            $childLog = Join-Path $ws.Path "child.log"
            $extra = if ($windowsHost) {
                'mkdir docker-student-ide 2>nul & echo exit /b 0 > docker-student-ide\start.ps1'
            } else {
                'mkdir -p docker-student-ide && printf "exit 0\n" > docker-student-ide/start.ps1'
            }
            $null = New-CommandFake -Name "git" -Directory $fakes -LogPath $gitLog -ExitCode 0 -ExtraScript $extra
            $null = New-CommandFake -Name "powershell.exe" -Directory $fakes -LogPath $childLog -ExitCode 0

            $result = Invoke-InstallerScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'Set-Location $env:TEST_WORKSPACE'
                '$code = Invoke-Installer -ArgsList @("-d")'
                'exit $code'
            )

            $result.ExitCode | Should -Be 0
            (Get-Content $gitLog -Raw) | Should -Match "git clone .*docker-student-ide"
            (Get-Content $childLog -Raw) | Should -Match "-NoProfile -ExecutionPolicy Bypass -File"
            (Get-Content $childLog -Raw) | Should -Match "start\.ps1 -d"
        } finally {
            & $ws.Cleanup
        }
    }
}

Describe "I-02 install from an existing repository" -Tag Unit {
    It "does not clone and invokes the child with execution-policy bypass" {
        $ws = New-BootstrapTestWorkspace -Repository
        try {
            $fakes = New-FakeDir $ws.Path
            $gitLog = Join-Path $ws.Path "git.log"
            $childLog = Join-Path $ws.Path "child.log"
            $null = New-CommandFake -Name "git" -Directory $fakes -LogPath $gitLog -ExitCode 0
            $null = New-CommandFake -Name "powershell.exe" -Directory $fakes -LogPath $childLog -ExitCode 0

            $result = Invoke-InstallerScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'Set-Location $env:TEST_WORKSPACE'
                '$code = Invoke-Installer -ArgsList @("-d")'
                'exit $code'
            )

            $result.ExitCode | Should -Be 0
            if (Test-Path $gitLog) {
                (Get-Content $gitLog -Raw) | Should -Not -Match "clone"
            }
            (Get-Content $childLog -Raw) | Should -Match "-NoProfile -ExecutionPolicy Bypass -File"
            (Get-Content $childLog -Raw) | Should -Match "start\.ps1 -d"
        } finally {
            & $ws.Cleanup
        }
    }
}

Describe "I-03 missing Git" -Tag Unit {
    It "fails with actionable guidance when winget installation fails" {
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path
            $wingetLog = Join-Path $ws.Path "winget.log"
            $null = New-CommandFake -Name "winget" -Directory $fakes -LogPath $wingetLog -ExitCode 1

            $result = Invoke-InstallerScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'function Get-Command {'
                '    param([string]$Name, [string]$ErrorAction)'
                '    if ($Name -eq "git") { return $null }'
                '    Microsoft.PowerShell.Core\Get-Command @PSBoundParameters'
                '}'
                'Set-Location $env:TEST_WORKSPACE'
                '$code = Invoke-Installer'
                'exit $code'
            )

            $result.ExitCode | Should -Be 1
            (@(Get-Content $wingetLog)).Count | Should -Be 1
            ($result.Output -join "`n") | Should -Match "git-scm.com/download/win"
        } finally {
            & $ws.Cleanup
        }
    }

    It "stops with a specific diagnostic when Git is installed but missing from PATH" {
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path
            $wingetLog = Join-Path $ws.Path "winget.log"
            $null = New-CommandFake -Name "winget" -Directory $fakes -LogPath $wingetLog -ExitCode 0

            $result = Invoke-InstallerScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'function Get-Command {'
                '    param([string]$Name, [string]$ErrorAction)'
                '    if ($Name -eq "git") { return $null }'
                '    Microsoft.PowerShell.Core\Get-Command @PSBoundParameters'
                '}'
                'Set-Location $env:TEST_WORKSPACE'
                '$code = Invoke-Installer'
                'exit $code'
            )

            $result.ExitCode | Should -Be 1
            (@(Get-Content $wingetLog)).Count | Should -Be 1
            ($result.Output -join "`n") | Should -Match "installed but is not detected"
        } finally {
            & $ws.Cleanup
        }
    }

    It "continues to clone after winget installs Git successfully" {
        # On Windows the bootstrap rebuilds PATH from the registry after
        # winget, which cannot be simulated without mutating the machine
        # registry; live winget coverage belongs to the disposable-VM layer.
        if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
            Set-ItResult -Skipped -Because "requires PATH injection beyond the registry refresh"
            return
        }
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path
            $wingetLog = Join-Path $ws.Path "winget.log"
            $gitLog = Join-Path $ws.Path "git.log"
            $childLog = Join-Path $ws.Path "child.log"
            $null = New-CommandFake -Name "winget" -Directory $fakes -LogPath $wingetLog -ExitCode 0
            $extra = if ($windowsHost) {
                'mkdir docker-student-ide 2>nul & echo exit /b 0 > docker-student-ide\start.ps1'
            } else {
                'mkdir -p docker-student-ide && printf "exit 0\n" > docker-student-ide/start.ps1'
            }
            $null = New-CommandFake -Name "git" -Directory $fakes -LogPath $gitLog -ExitCode 0 -ExtraScript $extra
            $null = New-CommandFake -Name "powershell.exe" -Directory $fakes -LogPath $childLog -ExitCode 0

            $result = Invoke-InstallerScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                '$script:gitChecks = 0'
                'function Get-Command {'
                '    param([string]$Name, [string]$ErrorAction)'
                '    if ($Name -eq "git") {'
                '        $script:gitChecks++'
                '        if ($script:gitChecks -le 1) { return $null }'
                '        return [pscustomobject]@{ Name = "git"; Source = (Join-Path $env:FAKE_DIR "git.cmd") }'
                '    }'
                '    Microsoft.PowerShell.Core\Get-Command @PSBoundParameters'
                '}'
                'Set-Location $env:TEST_WORKSPACE'
                '$code = Invoke-Installer'
                'exit $code'
            ) -ExtraEnvironment @{ FAKE_DIR = $fakes }

            $result.ExitCode | Should -Be 0
            (@(Get-Content $wingetLog)).Count | Should -Be 1
            (Get-Content $gitLog -Raw) | Should -Match "git clone .*docker-student-ide"
            (Get-Content $childLog -Raw) | Should -Match "-ExecutionPolicy Bypass -File"
        } finally {
            & $ws.Cleanup
        }
    }
}
