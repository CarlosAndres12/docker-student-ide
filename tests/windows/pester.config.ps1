Import-Module Pester -Force

$configuration = New-PesterConfiguration
$testPath = $env:PESTER_TEST_PATH
if (-not $testPath) {
    $testPath = Join-Path $PSScriptRoot "unit"
} elseif (-not [System.IO.Path]::IsPathRooted($testPath)) {
    $testPath = Join-Path $PSScriptRoot $testPath
}
$configuration.Run.Path = $testPath
$configuration.Run.Exit = $true
$configuration.Output.Verbosity = "Detailed"
$configuration.TestResult.Enabled = $true
$configuration.TestResult.OutputFormat = "JUnitXml"
$resultPath = $env:PESTER_RESULTS_PATH
if (-not $resultPath) {
    $resultPath = Join-Path ([System.IO.Path]::GetTempPath()) "docker-student-ide-windows-unit.xml"
}
$configuration.TestResult.OutputPath = $resultPath

$configuration
