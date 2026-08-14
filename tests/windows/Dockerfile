# Test runner image for the Windows bootstrap Pester suite.
# Runs PowerShell on Linux so unit contracts can execute without a
# native Windows host. This proves parsing and unit seams only; it
# does not prove winget, WSL, Docker Desktop, or execution-policy
# behavior.
FROM mcr.microsoft.com/powershell:lts

SHELL ["pwsh", "-NoProfile", "-Command"]

RUN Install-Module Pester -RequiredVersion 5.7.1 -Force -Scope AllUsers -SkipPublisherCheck

WORKDIR /workspace
ENTRYPOINT ["pwsh", "-NoProfile", "-NonInteractive"]
