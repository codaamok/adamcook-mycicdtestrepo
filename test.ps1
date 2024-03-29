function New-BuildEnvironmentVariable {
    <#
    .SYNOPSIS
        Build
        Set build and platform specific environment variables.
    .DESCRIPTION
        Set build and platform specific environment variables.
    .EXAMPLE
        PS C:\> New-BuildEnvironmentVariable -Variables @{ VersionToBuild = "1.2.3" } -Platform "GitHubActions"
        
        Writes to GitHub Action's environment variable file to create environment variable "VersionToBuild" with value of "1.2.3".
    #>
    param (
        [Parameter(Mandatory)]
        [Hashtable]$Variable,

        [Parameter(Mandatory)]
        [ValidateSet("GitHubActions", "Session")]
        [String[]]$Platform
    )

    switch ($Platform) {
        "GitHubActions" {
            foreach ($var in $Variable.GetEnumerator()) {
                Write-Output ("{0}={1}" -f $var.Key, $var.Value) | Add-Content -Path $env:GITHUB_ENV 
            }
        }
        "Session" {
            foreach ($var in $Variable.GetEnumerator()) {
                Set-Item -Path env:$var.Key -Value $var.Value
            }
        }
    }
}

New-BuildEnvironmentVariable -Platform "GitHubActions","Session" -Variable @{
    MyTestVariable = "Hello world"
}

Write-Host "Within script: $env:MyTestVariable"