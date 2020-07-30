param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [String]$ModuleName
)

# Synopsis: Initiate the entire build process
task . clean, CreateSinglePSM1, UpdateManifest

# Synopsis: Cleans the build directory
task clean {
    remove 'build'
}

# Synopsis: Creates a single .psm1 file of all private and public functions of the to-be-published module
task CreateSinglePSM1 {
    New-Item -Path $BuildRoot\build\$ModuleName\$ModuleName.psm1 -ItemType "File" -Force

    foreach ($FunctionType in "Private","Public") {
        '#region {0} functions' -f $FunctionType | Add-Content -Path $BuildRoot\build\$ModuleName\$ModuleName.psm1
        $Files = @(Get-ChildItem $BuildRoot\$ModuleName\$FunctionType -Filter *.ps1)
        $Files | ForEach-Object {
            Get-Content $_ | Add-Content -Path $BuildRoot\build\$ModuleName\$ModuleName.psm1
            if ($Files.IndexOf($_) -ne ($Files.Count - 1)) {
                Write-Output "" | Add-Content -Path $BuildRoot\build\$ModuleName\$ModuleName.psm1
            }
        }
        '#endregion {0} functions' -f $FunctionType | Add-Content -Path $BuildRoot\build\$ModuleName\$ModuleName.psm1
        Write-Output "" | Add-Content -Path $BuildRoot\build\$ModuleName\$ModuleName.psm1
    }
}

# Synopsis: Copy and update the manifest
task UpdateManifest {
    Copy-Item -Path $BuildRoot\$ModuleName\$ModuleName.psd1 -Destination $BuildRoot\build\$ModuleName

    $UpdateModuleManifestSplat = @{
        Path = '{0}\build\{1}\{2}.psd1' -f $BuildRoot, $ModuleName, $ModuleName
    }

    # Only ever increments the minor, I wonder how I could handle major. Maybe just trigger workflow based on releases and use the version from that instead?
    # Understand that if module isn't currently in the gallery, Invoke-Build will produce a terminating error and the build will fail!
    $PSGallery = Find-Module $ModuleName
    if ($PSGallery) {
        $UpdateModuleManifestSplat["ModuleVersion"] = '{0}.{1}' -f ([System.Version]$PSGallery.Version).Major, (([System.Version]$PSGallery.Version).Minor + 1)
    }
    
    Update-ModuleManifest @UpdateModuleManifestSplat
}