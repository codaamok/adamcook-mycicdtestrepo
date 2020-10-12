function Get-Year {
    [CmdletBinding()]
    param (
    )
    Get-Date -Format "yyyy"
}