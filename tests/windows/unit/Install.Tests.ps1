BeforeAll {
    $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
    . (Join-Path $repositoryRoot "tests/windows/support/TestWorkspace.ps1")
    . (Join-Path $repositoryRoot "tests/windows/support/CommandFake.ps1")
    . (Join-Path $repositoryRoot "tests/windows/support/Invoke-BootstrapScenario.ps1")
}

Describe "I-01 install from an empty directory" -Tag Unit {
    It "clones into the requested workspace and forwards startup arguments" -Pending {
        # Implement with a staged git and child-launcher fake.
    }
}

Describe "I-02 install from an existing repository" -Tag Unit {
    It "does not clone and invokes the child with execution-policy bypass" -Pending {
        # Implement with a repository fixture and a failing git fake.
    }
}

Describe "I-03 missing Git" -Tag Unit {
    It "covers winget success, failure, and still-missing PATH branches" -Pending {
        # Implement with mocked Get-Command and winget outcomes.
    }
}
