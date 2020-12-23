# Write-Verbose 'Clearing old files'

# if ((Test-Path ..\docs) -eq $false) {
#     New-Item -ItemType Directory -Name ..\docs
# }

# Get-ChildItem ..\docs | Remove-Item -Force -Recurse

# Write-Verbose 'Merging Markdown files'
# if (-not (Get-Module Trackyon.Markdown -ListAvailable)) {
#     Install-Module Trackyon.Markdown -Scope CurrentUser -Force
# }

# merge-markdown $PSScriptRoot $PSScriptRoot\..\docs

# Write-Verbose 'Creating new file'

# if (-not (Get-Module platyPS -ListAvailable)) {
#     Install-Module platyPS -Scope CurrentUser -Force
# }

# $helpOutput = New-ExternalHelp ..\docs -OutputPath ..\Source\en-US -Force | Out-String

# Write-Verbose $helpOutput

$branch = $env:BUILD_SOURCEBRANCHNAME

$manifestPath = '..\Source\VenafiTppPS.psd1'
$manifest = Import-PowerShellDataFile $manifestPath
[version]$version = $Manifest.ModuleVersion

"Loading Module from $manifestPath to update docs"
Remove-Module VenafiTppPS -Force -ea SilentlyContinue -Verbose
# platyPS + AppVeyor requires the module to be loaded in Global scope
Import-Module $manifestPath -force -Verbose

#Build YAMLText starting with the header
$YMLtext = (Get-Content "$projectRoot\header-mkdocs.yml") -join "`n"
$YMLtext = "$YMLtext`n"
$parameters = @{
    Path        = $releaseNotesPath
    ErrorAction = 'SilentlyContinue'
}
$ReleaseText = (Get-Content @parameters) -join "`n"
if ($ReleaseText) {
    $ReleaseText | Set-Content "$projectRoot\docs\RELEASE.md"
    $YMLText = "$YMLtext  - Release Notes: RELEASE.md`n"
}
if ((Test-Path -Path $changeLogPath)) {
    $YMLText = "$YMLtext  - Change Log: ChangeLog.md`n"
}
$YMLText = "$YMLtext  - Functions:`n"
# Drain the swamp
$parameters = @{
    Recurse     = $true
    Force       = $true
    Path        = "$projectRoot\docs\functions"
    ErrorAction = 'SilentlyContinue'
}
$null = Remove-Item @parameters
$Params = @{
    Path        = "$projectRoot\docs\functions"
    type        = 'directory'
    ErrorAction = 'SilentlyContinue'
}
$null = New-Item @Params
$Params = @{
    Module       = $ModuleName
    Force        = $true
    OutputFolder = "$projectRoot\docs\functions"
    NoMetadata   = $true
}
New-MarkdownHelp @Params | ForEach-Object {
    $Function = $_.Name -replace '\.md', ''
    $Part = "    - {0}: functions/{1}" -f $Function, $_.Name
    $YMLText = "{0}{1}`n" -f $YMLText, $Part
    $Part
}
$YMLtext | Set-Content -Path "$projectRoot\mkdocs.yml"

$YMLtext
Get-ChildItem "$projectRoot\docs" -Recurse

try {
    Write-Output ("Updating {0} branch source" -f $branch)
    git.exe config user.email 'greg@jagtechnical.com'
    git.exe config user.name 'Greg Brownstein'
    # git.exe add *.psd1
    git.exe add *.md
    git.exe add "$projectRoot\mkdocs.yml"
    git.exe status -v
    git.exe commit -m "Updated VenafiTppPS version to $version ***NO_CI***"

    # if we are performing pull request validation, do not push the code to the repo
    if ( $env:BUILD_REASON -eq 'PullRequest') {
        Write-Output "Bypassing git push given this build is for pull request validation"
    } else {
        git.exe push https://$($GitHubPat)@github.com/gdbarron/TppTest.git ('HEAD:{0}' -f $branch)
        # git.exe push https://$($GitHubPat)@github.com/gdbarron/VenafiTppPS.git ('HEAD:{0}' -f $branch)
        Write-Output ("Updated {0} branch source" -f $branch)
    }

} catch {
    Write-Output ("Failed to update {0} branch with updated module metadata" -f $branch)
    $_ | Format-List -Force
}
