#Requires -Module "ChangelogManagement"
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$ModuleName
)

# Synopsis: Initiate the entire build process
task . Clean, GetPSGalleryVersionNumber, CopyChangeLog, GetChangelog, GetNextVersionNumber, UpdateChangeLog, GetFunctionsToExport, CreateRootModule, CopyFormatFiles, CopyLicense, CreateProcessScript, CopyModuleManifest, UpdateModuleManifest, CreateReleaseAsset

# Synopsis: Empty the contents of the build and release directories. If not exist, create them.
task Clean {
    $Paths = @(
        "{0}\build" -f $BuildRoot
        "{0}\release" -f $BuildRoot
    )

    foreach ($Path in $Paths) {
        if (Test-Path $Path) {
            Remove-Item -Path $Path\* -Recurse -Force
        }
        else {
            New-Item -Path $Path -ItemType "Directory" -Force
        }
    }
}

# Synopsis: Get current version number of module in PowerShell Gallery (if published)
task GetPSGalleryVersionNumber {
    try {
        $Script:PSGalleryModuleInfo = Find-Module -Name $env:GH_PROJECTNAME -ErrorAction "Stop"
    }
    catch {
        if ($_.Exception.Message -notmatch "No match was found for the specified search criteria") {
            throw $_
        }
    }

    if (-not $PSGalleryModuleInfo) {
        $Script:PSGalleryModuleInfo = [PSCustomObject]@{
            "Name"    = $env:GH_PROJECTNAME
            "Version" = "0.0"
        }
    }
}

# Synopsis: Copy CHANGELOG.md (must exist)
task CopyChangeLog {
    Copy-Item -Path $BuildRoot\CHANGELOG.md -Destination $BuildRoot\build\$Script:ModuleName
}

# Synopsis: Read change log to get current version number and unreleased release notes
task GetChangelog {
    $ChangeLog = Get-ChangeLogData -Path $BuildRoot\CHANGELOG.md
    $EmptyUnreleasedChangeLog = $true

    $Script:ReleaseNotes = foreach ($Property in $ChangeLog.Unreleased.Data.PSObject.Properties.Name) {
        $Data = $ChangeLog.Unreleased.Data.$Property

        if ($Data) {
            $EmptyUnreleasedChangeLog = $false

            Write-Output $Property

            foreach ($item in $Data) {
                Write-Output ("- {0}" -f $item)
            }
        }
    }

    if ($EmptyUnreleasedChangeLog -eq $true -Or $Script:ReleaseNotes.Count -eq 0) {
        throw "Can not deploy with empty Unreleased section in the change log"
    }

    Write-Output "Release notes:"
    Write-Output $Script:ReleaseNotes
}

# Synopsis: Determine next version to publish by evaluating versions in PowerShell Gallery and in the change log
task GetNextVersionNumber {
    $ChangeLog = Get-ChangeLogData -Path $BuildRoot\CHANGELOG.md

    $Date = Get-Date -Format 'yyyyMMdd'

    # If the last released version in the change log and latest version available in the PowerShell gallery don't match, throw an exception - get them level!
    if ($null -ne $ChangeLog.Released[0].Version -And $ChangeLog.Released[0].Version -ne $Script:PSGalleryModuleInfo.Version) {
        throw "The latest released version in the changelog does not match the latest released version in the PowerShell gallery"
    }
    # If module isn't yet published in the PowerShell gallery, and there's no Released section in the change log, set initial version
    elseif ($Script:PSGalleryModuleInfo.Version -eq "0.0" -And $ChangeLog.Released.Count -eq 0) {
        $Script:VersionToPublish = [System.Version]::New(1, 0, $Date, 0)
    }
    # If module isn't yet published in the PowerShell gallery, and there is a Released section in the change log, update version
    elseif ($Script:PSGalleryModuleInfo.Version -eq "0.0" -And $ChangeLog.Released.Count -ge 1) {
        $CurrentVersion   = [System.Version]$ChangeLog.Released[0].Version
        $Script:VersionToPublish = [System.Version]::New($CurrentVersion.Major, $CurrentVersion.Minor + 1, $Date, 0)
    }
    # If the last Released verison in the change log and currently latest verison in the PowerShell gallery are in harmony, update version
    elseif ($ChangeLog.Released[0].Version -eq $Script:PSGalleryModuleInfo.Version) {
        $CurrentVersion   = [System.Version]$Script:PSGalleryModuleInfo.Version
        $Script:VersionToPublish = [System.Version]::New($CurrentVersion.Major, $CurrentVersion.Minor + 1, $Date, 0)
    }
    else {
        Write-Output ("Latest release version from change log: {0}" -f $ChangeLog.Released[0].Version)
        Write-Output ("Latest release version from PowerShell gallery: {0}" -f $Script:PSGalleryModuleInfo.Version)
        throw "Can not determine next version number"
    }

    # Suss out unlisted packages
    for ($i = $Script:VersionToPublish.Revision; $i -le 100; $i++) {
        if ($i -eq 100) {
            throw "You have 100 unlisted packages under the same build number? Sort your life out."
        }

        try {
            $Script:PSGalleryModuleInfo = Find-Module -Name $env:GH_PROJECTNAME -RequiredVersion $Script:VersionToPublish
            if ($Script:PSGalleryModuleInfo) {
                $Script:VersionToPublish = [System.Version]::New($Script:VersionToPublish.Major, $Script:VersionToPublish.Minor, $Script:VersionToPublish.Build, $i)
            }
            else {
                throw "Unusual no object or exception caught from Find-Module"
            }
        }
        catch {
            if ($_.Exception.Message -match "No match was found for the specified search criteria") {
                # Found next available version to use
                break
            }
            else {
                throw $_
            }
        }
    }

    Write-Output ("Version to publish: {0}" -f $Script:VersionToPublish)
    Write-Output ("::set-env name=VersionToPublish::{0}" -f $Script:VersionToPublish)
}

# Synopsis: Update CHANGELOG.md
task UpdateChangeLog {
    $LinkPattern   = @{
        FirstRelease  = "https://github.com/{0}/{1}/tree/{{CUR}}" -f $env:GH_USERNAME, $env:GH_PROJECTNAME
        NormalRelease = "https://github.com/{0}/{1}/compare/{{PREV}}..{{CUR}}" -f $env:GH_USERNAME, $env:GH_PROJECTNAME
        Unreleased    = "https://github.com/{0}/{1}/compare/{{CUR}}..HEAD" -f $env:GH_USERNAME, $env:GH_PROJECTNAME
    }

    Update-Changelog -Path $BuildRoot\build\$Script:ModuleName\CHANGELOG.md -ReleaseVersion $Script:VersionToPublish -LinkMode Automatic -LinkPattern $LinkPattern
}

# Synopsis: Gather all exported functions to populate manifest with
task GetFunctionsToExport {
    $Files = @(Get-ChildItem $BuildRoot\$Script:ModuleName\Public -Filter *.ps1)

    $Script:FunctionsToExport = foreach ($File in $Files) {
        try {
            $tokens = $errors = @()
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $File.FullName,
                [ref]$tokens,
                [ref]$errors
            )

            if ($errors[0].ErrorId -eq 'FileReadError') {
                throw [InvalidOperationException]::new($errors[0].Message)
            }

            Write-Output $Ast.EndBlock.Statements.Name
        }
        catch {
            Write-Error -Exception $_.Exception -Category "OperationStopped"
        }
    }
}

# Synopsis: Creates a single .psm1 file of all private and public functions of the to-be-published module
task CreateRootModule {
    $RootModule = New-Item -Path $BuildRoot\build\$Script:ModuleName\$Script:ModuleName.psm1 -ItemType "File" -Force

    foreach ($FunctionType in "Private","Public") {
        '#region {0} functions' -f $FunctionType | Add-Content -Path $RootModule

        $Files = @(Get-ChildItem $BuildRoot\$Script:ModuleName\$FunctionType -Filter *.ps1)

        foreach ($File in $Files) {
            Get-Content -Path $File.FullName | Add-Content -Path $RootModule

            # Add new line only if the current file isn't the last one (minus 1 because array indexes from 0)
            if ($Files.IndexOf($File) -ne ($Files.Count - 1)) {
                Write-Output "" | Add-Content -Path $RootModule
            }
        }

        '#endregion' -f $FunctionType | Add-Content -Path $RootModule
        Write-Output "" | Add-Content -Path $RootModule
    }
}

# Synopsis: Create a single Process.ps1 script file for all script files under ScriptsToProcess\* (if any)
task CreateProcessScript {
    $ScriptsToProcessFolder = "{0}\{1}\ScriptsToProcess" -f $BuildRoot, $Script:ModuleName

    if (Test-Path $ScriptsToProcessFolder) {
        $Script:ProcessFile = New-Item -Path $BuildRoot\build\$Script:ModuleName\Process.ps1 -ItemType "File" -Force
        $Files = @(Get-ChildItem $ScriptsToProcessFolder -Filter *.ps1)
    }

    foreach ($File in $Files) {
        Get-Content -Path $File.FullName | Add-Content -Path $Script:ProcessFile

        # Add new line only if the current file isn't the last one (minus 1 because array indexes from 0)
        if ($Files.IndexOf($File) -ne ($Files.Count - 1)) {
            Write-Output "" | Add-Content -Path $Script:ProcessFile
        }
    }
}

# Synopsis: Copy format files (if any)
task CopyFormatFiles {
    $Script:FormatFiles = Get-ChildItem $BuildRoot\$Script:ModuleName -Filter "*format.ps1xml" | Copy-Item -Destination $BuildRoot\build\$Script:ModuleName
}

# Synopsis: Copy LICENSE file (must exist)
task CopyLicense {
    Copy-Item -Path $BuildRoot\LICENSE -Destination $BuildRoot\build\$Script:ModuleName
}

task CopyModuleManifest {
    $Script:ManifestFile = Copy-Item -Path $BuildRoot\$Script:ModuleName\$Script:ModuleName.psd1 -Destination $BuildRoot\build\$Script:ModuleName -PassThru
}

# Synopsis: Copy and update the manifest in build directory. If successfully, replace manifest in the module directory
task UpdateModuleManifest {  
    $UpdateModuleManifestSplat = @{
        Path = $Script:ManifestFile
    }

    $UpdateModuleManifestSplat["ModuleVersion"] = $Script:VersionToPublish

    $UpdateModuleManifestSplat["ReleaseNotes"] = $Script:ReleaseNotes

    if ($Script:FormatFiles) {
        $UpdateModuleManifestSplat["FormatsToProcess"] = $Script:FormatFiles.Name
    }

    if ($Script:ProcessFile) {
        # Use this instead of Updatet-ModuleManifest due to https://github.com/PowerShell/PowerShellGet/issues/196
        (Get-Content -Path $Script:ManifestFile.FullName) -replace '(#? ?ScriptsToProcess.+)', ('ScriptsToProcess = "{0}"' -f $Script:ProcessFile.Name) | Set-Content -Path $ManifestFile
    }

    if ($Script:FunctionsToExport) {
        $UpdateModuleManifestSplat["FunctionsToExport"] = $Script:FunctionsToExport
    }
    
    Update-ModuleManifest @UpdateModuleManifestSplat

    # Arguably a moot point as Update-MooduleManifest obviously does some testing to ensure a valid manifest is there first before updating it
    # However with the regex replace for ScriptsToProcess, I want to be sure
    $null = Test-ModuleManifest -Path $Script:ManifestFile
}

# Synopsis: Create release asset (archived module)
task CreateReleaseAsset {
    $ReleaseAsset = "{0}_{1}.zip" -f $Script:ModuleName, $Script:VersionToPublish
    Compress-Archive -Path $BuildRoot\build\$Script:ModuleName\* -DestinationPath $BuildRoot\release\$ReleaseAsset -Force
}
