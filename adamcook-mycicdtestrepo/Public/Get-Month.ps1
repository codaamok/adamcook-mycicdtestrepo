function Get-Month {
    [CmdletBinding()]
    param (
    )
    Get-Date -Format "MM"
}