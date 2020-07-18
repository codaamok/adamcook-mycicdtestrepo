#region Private functions
function Get-UserName {
    param (
        
    )
    Write-Output $env:USERNAME
}
#endregion Private functions

#region Public functions
function Get-ComputerName {
    param (
        
    )
    Write-Output $env:COMPUTERNAME
}

function Get-HomeDirectory {
    param (
        
    )
    Write-Output $env:HOME
}
#endregion Public functions

