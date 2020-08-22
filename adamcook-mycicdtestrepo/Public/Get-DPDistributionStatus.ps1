function Get-DPDistributionStatus {
    <#
    .SYNOPSIS
        Retrieve the content distribution status of all objects for a distribution point.
    .PARAMETER DistributionPoint
        Name of distribution point (as it appears in ConfigMgr, usually FQDN) you want to query.
    .PARAMETER Distributed
        Filter on objects in distributed state
    .PARAMETER DistributionPending
        Filter on objects in distribution pending state
    .PARAMETER DistributionRetrying
        Filter on objects in distribution retrying state
    .PARAMETER DistributionFailed
        Filter on objects in distribution failed state
    .PARAMETER RemovalPending
        Filter on objects in removal pending state
    .PARAMETER RemovalRetrying
        Filter on objects in removal retrying state
    .PARAMETER RemovalFailed
        Filter on objects in removal failed state
    .PARAMETER ContentUpdating
        Filter on objects in content updating state
    .PARAMETER ContentMonitoring
        Filter on objects in content monitoring state
    .PARAMETER SiteServer
        It is not usually necessary to specify this parameter as importing the PSCMContentMgr module sets the $CMSiteServer variable which is the default value for this parameter.

        Specify this to query an alternative server, or if the module import process was unable to auto-detect and set $CMSiteServer.
    .PARAMETER SiteCode
        Site code of which the server specified by -SiteServer belongs to.

        It is not usually necessary to specify this parameter as importing the PSCMContentMgr module sets the $CMSiteCode variable which is the default value for this parameter.

        Specify this to query an alternative site, or if the module import process was unable to auto-detect and set $CMSiteCode.
    .EXAMPLE
        PS C:\> Get-DPDistributionStatus -DistributionPoint "dp1.contoso.com"

        Gets the content distribution status for all objects on "dp1.contoso.com".
    #>
    [CmdletBinding()]
    param (
        [ParameteR(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$DistributionPoint,

        [Parameter()]
        [Switch]$Distributed,

        [Parameter()]
        [Switch]$DistributionPending,

        [Parameter()]
        [Switch]$DistributionRetrying,

        [Parameter()]
        [Switch]$DistributionFailed,

        [Parameter()]
        [Switch]$RemovalPending,

        [Parameter()]
        [Switch]$RemovalRetrying,

        [Parameter()]
        [Switch]$RemovalFailed,

        [Parameter()]
        [Switch]$ContentUpdating,

        [Parameter()]
        [Switch]$ContentMonitoring,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$SiteServer = $CMSiteServer,
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$SiteCode = $CMSiteCode
    )
    begin {
        switch ($null) {
            $SiteCode {
                Write-Error -Message "Please supply a site code using the -SiteCode parameter" -Category "InvalidArgument" -ErrorAction "Stop"
            }
            $SiteServer {
                Write-Error -Message "Please supply a site server FQDN address using the -SiteServer parameter" -Category "InvalidArgument" -ErrorAction "Stop"
            }
        }

        try {
            Resolve-DP -Name $DistributionPoint -SiteServer $SiteServer -SiteCode $SiteCode
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
    process {
        $Namespace = "ROOT/SMS/Site_{0}" -f $SiteCode
        $Query = "SELECT PackageID,PackageType,State,SourceVersion FROM SMS_PackageStatusDistPointsSummarizer WHERE ServerNALPath like '%{0}%'" -f $DistributionPoint

        $conditions = switch ($true) {
            $Distributed            { "State = '{0}'" -f [Int][SMS_PackageStatusDistPointsSummarizer_State]"DISTRIBUTED" }
            $DistributionPending    { "State = '{0}'" -f [Int][SMS_PackageStatusDistPointsSummarizer_State]"DISTRIBUTION_PENDING" }
            $DistributionRetrying   { "State = '{0}'" -f [Int][SMS_PackageStatusDistPointsSummarizer_State]"DISTRIBUTION_RETRYING" }
            $DistributionFailed     { "State = '{0}'" -f [Int][SMS_PackageStatusDistPointsSummarizer_State]"DISTRIBUTION_FAILED" }
            $RemovalPending         { "State = '{0}'" -f [Int][SMS_PackageStatusDistPointsSummarizer_State]"REMOVAL_PENDING" }
            $RemovalRetrying        { "State = '{0}'" -f [Int][SMS_PackageStatusDistPointsSummarizer_State]"REMOVAL_RETRYING" }
            $RemovalFailed          { "State = '{0}'" -f [Int][SMS_PackageStatusDistPointsSummarizer_State]"REMOVAL_FAILED" }
            $ContentUpdating        { "State = '{0}'" -f [Int][SMS_PackageStatusDistPointsSummarizer_State]"CONTENT_UPDATING" }
            $ContentMonitoring      { "State = '{0}'" -f [Int][SMS_PackageStatusDistPointsSummarizer_State]"CONTENT_MONITORING" }
        }

        if ($conditions) {
            $Query = "{0} AND ( {1} )" -f $Query, ([String]::Join(" OR ", $conditions)) 
        }

        Get-CimInstance -ComputerName $SiteServer -Namespace $Namespace -Query $Query -ErrorAction "Stop" | ForEach-Object {
            [PSCustomObject]@{
                PSTypeName        = "PSCMContentMgmt"
                ObjectID          = $_.PackageID
                ObjectType        = [SMS_PackageStatusDistPointsSummarizer_PackageType]$_.PackageType
                State             = [SMS_PackageStatusDistPointsSummarizer_State]$_.State
                SourceVersion     = $_.SourceVersion
                DistributionPoint = $DistributionPoint
            }
        }
    }
    end {
    }
}
