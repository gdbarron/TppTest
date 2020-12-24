[CmdletBinding(DefaultParameterSetName = "All")]
param(
   #output path of the build module
   [Parameter(ParameterSetName = "All")]
   [Parameter(ParameterSetName = "UnitTest")]
   [string]$outputDir = './dist',

   # Building help is skipped by default to speed your inner loop.
   # Use this flag to include building the help
   [Parameter(ParameterSetName = "All")]
   [Parameter(ParameterSetName = "UnitTest")]
   [switch]$buildHelp,

   # By default the build will not install dependencies
   [Parameter(ParameterSetName = "All")]
   [Parameter(ParameterSetName = "UnitTest")]
   [switch]$installDep,

   # built module will be imported into session
   [Parameter(ParameterSetName = "All")]
   [Parameter(ParameterSetName = "UnitTest")]
   [switch]$ipmo,

   # run the scripts with the PS script analyzer
   [Parameter(ParameterSetName = "All")]
   [Parameter(ParameterSetName = "UnitTest")]
   [switch]$analyzeScript,

   # runs the unit tests
   [Parameter(ParameterSetName = "UnitTest", Mandatory = $true)]
   [Parameter(ParameterSetName = "All")]
   [switch]$runTests,

   # can be used to filter the unit test parts that should be run
   # see also: https://github.com/pester/Pester/wiki/Invoke%E2%80%90Pester#testname-alias-name
   [Parameter(ParameterSetName = "UnitTest")]
   [string]$testName,

   # outputs the code coverage
   [Parameter(ParameterSetName = "UnitTest")]
   [switch]$codeCoverage,

   # runs the integration tests
   [Parameter(ParameterSetName = "UnitTest")]
   [Parameter(ParameterSetName = "All")]
   [switch]$runIntegrationTests,

   [Parameter(ParameterSetName = "UnitTest")]
   [Parameter(ParameterSetName = "All")]
   [switch]$skipLibBuild,

   [ValidateSet('LibOnly', 'Debug', 'Release')]
   [string]$configuration = "LibOnly",

   [ValidateSet('Diagnostic', 'Detailed', 'Normal', 'Minimal', 'None', 'ErrorsOnly')]
   [string]$testOutputLevel = "ErrorsOnly"
)

function Import-Pester {
   if ($null -eq $(Get-Module -ListAvailable Pester | Where-Object Version -like '5.*')) {
      Write-Output "Installing Pester 5"
      Install-Module -Name Pester -Repository PSGallery -Force -AllowPrerelease -MinimumVersion '5.0.2' -Scope CurrentUser -AllowClobber -SkipPublisherCheck
   }

   # This loads [PesterConfiguration] into scope
   Import-Module Pester -MinimumVersion 5.0.0
}

function Start-IntegrationTests {
   [CmdletBinding(DefaultParameterSetName = "All", SupportsShouldProcess, ConfirmImpact = "High")]
   param()

   process {
      Write-Output '   Testing: Functions (integration)'

      if (-not $(Test-Path -Path './Tests/TestResults')) {
         New-Item -Path './Tests/TestResults' -ItemType Directory | Out-Null
      }

      Import-Pester

      $pesterArgs = [PesterConfiguration]::Default
      $pesterArgs.Run.Path = './Tests/integration'
      $pesterArgs.Run.Exit = $true
      $pesterArgs.TestResult.Enabled = $true
      $pesterArgs.TestResult.OutputPath = './Tests/TestResults/integrationTest-results.xml'
      $pesterArgs.Run.PassThru = $false

      if ('ErrorsOnly' -eq $testOutputLevel) {
         $pesterArgs.Output.Verbosity = 'none'
         $pesterArgs.Run.PassThru = $true
         $intTestResults = Invoke-Pester -Configuration $pesterArgs
         $intTestResults.Failed | Select-Object -ExpandProperty ErrorRecord
      } else {
         $pesterArgs.Output.Verbosity = $testOutputLevel
         Invoke-Pester -Configuration $pesterArgs
      }
   }
}

. ./Merge-File.ps1

if ($installDep.IsPresent -or $analyzeScript.IsPresent) {
   # Load the psd1 file so you can read the required modules and install them
   $manifest = Import-PowerShellDataFile .\Source\VenafiTppPS.psd1

   # Install each module
   if ($manifest.RequiredModules) {
      $manifest.RequiredModules | ForEach-Object { if (-not (Get-Module $_ -ListAvailable)) { Write-Host "Installing $_"; Install-Module -SkipPublisherCheck -Name $_ -Repository PSGallery -F -Scope CurrentUser } }
   }
}

if ([System.IO.Path]::IsPathRooted($outputDir)) {
   $output = $outputDir
} else {
   $output = Join-Path (Get-Location) $outputDir
}

$output = [System.IO.Path]::GetFullPath($output)

# Merge-File -inputFile ./Source/types/_types.json -outputDir $output
# Merge-File -inputFile ./Source/formats/_formats.json -outputDir $output
Merge-File -inputFile ./Source/_functions.json -outputDir $output -verbose

# Write-Output 'Publishing: About help files'
# Copy-Item -Path ./Source/en-US -Destination "$output/" -Recurse -Force

# $folders = @('Enum', 'Classes', 'Public', 'Private', 'Config')
# foreach ( $folder in $folders) {
# }
Copy-Item -Path ./Source/Config -Destination "$output/" -Recurse -Force

Write-Output 'Publishing: Manifest file'
Copy-Item -Path ./Source/VenafiTppPS.psm1 -Destination "$output/VenafiTppPS.psm1" -Force

Write-Output '  Updating: Functions To Export'
$newValue = ((Get-ChildItem -Path "./Source/Public" -Filter '*.ps1').BaseName |
   ForEach-Object -Process { Write-Output "'$_'" }) -join ','

(Get-Content "./Source/VenafiTppPS.psd1") -Replace ("FunctionsToExport.+", "FunctionsToExport = ($newValue)") | Set-Content "$output/VenafiTppPS.psd1"


# if (-not $skipLibBuild.IsPresent) {
#    Write-Output "  Building: C# project ($configuration config)"

#    if (-not $(Test-Path -Path $output\bin)) {
#       New-Item -Path $output\bin -ItemType Directory | Out-Null
#    }

#    $buildOutput = dotnet build --nologo --verbosity quiet --configuration $configuration | Out-String

#    Copy-Item -Destination "$output\bin\VenafiTppPS-lib.dll" -Path ".\Source\Classes\bin\$configuration\netstandard2.0\VenafiTppPS-lib.dll" -Force
#    Copy-Item -Destination "$output\bin\Trackyon.System.Management.Automation.Abstractions.dll" -Path ".\Source\Classes\bin\$configuration\netstandard2.0\Trackyon.System.Management.Automation.Abstractions.dll" -Force

#    if (-not ($buildOutput | Select-String -Pattern 'succeeded')) {
#       Write-Output $buildOutput
#    }
# }

Write-Output "Publishing: Complete to $output"
# run the unit tests with Pester
if ($runTests.IsPresent) {
   if (-not $skipLibBuild.IsPresent -and $configuration -ne 'LibOnly') {
      Write-Output '   Testing: C# project (unit)'
      $testOutput = dotnet.exe test --nologo --configuration $configuration | Out-String

      if (-not ($testOutput | Select-String -Pattern 'Test Run Successful')) {
         Write-Output $testOutput
      }
   }

   Write-Output '   Testing: Functions (unit)'

   if (-not $(Test-Path -Path './Tests/TestResults')) {
      New-Item -Path './Tests/TestResults' -ItemType Directory | Out-Null
   }

   Import-Pester

   $pesterArgs = [PesterConfiguration]::Default
   $pesterArgs.Run.Path = './Tests/function'
   $pesterArgs.TestResult.Enabled = $true
   $pesterArgs.TestResult.OutputPath = './Tests/TestResults/test-results.xml'

   if ($codeCoverage.IsPresent) {
      $pesterArgs.CodeCoverage.Enabled = $true
      $pesterArgs.CodeCoverage.OutputFormat = 'JaCoCo'
      $pesterArgs.CodeCoverage.OutputPath = "coverage.xml"
      $pesterArgs.CodeCoverage.Path = "./Source/**/*.ps1"
   } else {
      $pesterArgs.Run.PassThru = $false
   }

   if ($testName) {
      $pesterArgs.Filter.FullName = $testName
   }

   if ('ErrorsOnly' -eq $testOutputLevel) {
      $pesterArgs.Output.Verbosity = 'none'
      $pesterArgs.Run.PassThru = $true
      $unitTestResults = Invoke-Pester -Configuration $pesterArgs
      $unitTestResults.Failed | Select-Object -ExpandProperty ErrorRecord
   } else {
      $pesterArgs.Output.Verbosity = $testOutputLevel
      Invoke-Pester -Configuration $pesterArgs
   }
}

# reload the just built module
if ($ipmo.IsPresent -or $analyzeScript.IsPresent -or $runIntegrationTests.IsPresent) {
   # module needs to be unloaded if present
   if ((Get-Module VenafiTppPS)) {
      Remove-Module VenafiTppPS
   }

   Write-Host " Importing: Module"

   Import-Module "$output/VenafiTppPS.psd1" -Force
   Set-VenafiTppPSAlias
}

# Run this last so the results can be seen even if tests were also run
# if not the results scroll off and my not be in the buffer.
# run PSScriptAnalyzer
if ($analyzeScript.IsPresent) {
   Write-Output "Starting static code analysis..."
   if ($null -eq $(Get-Module -Name PSScriptAnalyzer)) {
      Install-Module -Name PSScriptAnalyzer -Repository PSGallery -Force -Scope CurrentUser
   }

   $r = Invoke-ScriptAnalyzer -Path $output -Recurse
   $r | ForEach-Object { Write-Host "##vso[task.logissue type=$($_.Severity);sourcepath=$($_.ScriptPath);linenumber=$($_.Line);columnnumber=$($_.Column);]$($_.Message)" }
   Write-Output "Static code analysis complete."
}

# run integration tests with Pester
if ($runIntegrationTests.IsPresent) {
   Start-IntegrationTests
}

# Build the help
if ($buildHelp.IsPresent) {
   Write-Output 'Building help'
   # Push-Location
   # Set-Location ./.docs
   # Try {
   #    ./gen-help.ps1 -verbose
   # } Finally {
   #    Pop-Location
   # }
   # Install-PackageProvider -Name Nuget -Scope CurrentUser -Force -Confirm:$false
   if (-not (Get-Module platyPS -ListAvailable)) {
      Install-Module platyPS -Scope CurrentUser -Force
   }

   $branch = $env:BUILD_SOURCEBRANCHNAME

   # $manifestPath = '..\Source\VenafiTppPS.psd1'
   $manifest = Import-PowerShellDataFile .\Source\VenafiTppPS.psd1
   [version]$version = $Manifest.ModuleVersion

   # "Loading Module from $manifestPath to update docs"
   # Remove-Module VenafiTppPS -Force -ea SilentlyContinue -Verbose
   # platyPS + AppVeyor requires the module to be loaded in Global scope
   Import-Module "$output/VenafiTppPS.psd1" -Force

   #Build YAMLText starting with the header
   $YMLtext = (Get-Content ".\header-mkdocs.yml") -join "`n"
   $YMLtext = "$YMLtext`n"
   $parameters = @{
      Path        = '.\release.md'
      ErrorAction = 'SilentlyContinue'
   }
   $ReleaseText = (Get-Content @parameters) -join "`n"
   if ($ReleaseText) {
      $ReleaseText | Set-Content ".\docs\RELEASE.md"
      $YMLText = "$YMLtext  - Release Notes: RELEASE.md`n"
   }
   if ((Test-Path -Path $'.\changelog.md')) {
      $YMLText = "$YMLtext  - Change Log: ChangeLog.md`n"
   }
   $YMLText = "$YMLtext  - Functions:`n"
   # Drain the swamp
   $parameters = @{
      Recurse     = $true
      Force       = $true
      Path        = ".\docs\functions"
      ErrorAction = 'SilentlyContinue'
   }
   $null = Remove-Item @parameters
   $Params = @{
      Path        = ".\docs\functions"
      type        = 'directory'
      ErrorAction = 'SilentlyContinue'
   }
   $null = New-Item @Params
   $Params = @{
      Module       = 'VenafiTppPS'
      Force        = $true
      OutputFolder = ".\docs\functions"
      NoMetadata   = $true
   }
   New-MarkdownHelp @Params | ForEach-Object {
      $Function = $_.Name -replace '\.md', ''
      $Part = "    - {0}: functions/{1}" -f $Function, $_.Name
      $YMLText = "{0}{1}`n" -f $YMLText, $Part
      $Part
   }
   $YMLtext | Set-Content -Path ".\mkdocs.yml"

   $YMLtext
   Get-ChildItem ".\docs" -Recurse

   try {
      Write-Output ("Updating {0} branch source" -f $branch)
      git.exe config user.email 'greg@jagtechnical.com'
      git.exe config user.name 'Greg Brownstein'
      # git.exe add *.psd1
      git.exe add *.md
      git.exe add ".\mkdocs.yml"
      git.exe status -v
      git.exe commit -m "Updated to v$version ***NO_CI***"

      # if we are performing pull request validation, do not push the code to the repo
      if ( $env:BUILD_REASON -eq 'PullRequest') {
         Write-Output "Bypassing git push given this build is for pull request validation"
      } else {
         ('https://{0}@github.com/gdbarron/TppTest.git' -f $env:GITHUBPAT)
         git.exe push ('https://{0}@github.com/gdbarron/TppTest.git' -f ${env:GITHUBPAT}) ('HEAD:{0}' -f $branch)
         # git.exe push https://$($GitHubPat)@github.com/gdbarron/VenafiTppPS.git ('HEAD:{0}' -f $branch)
         Write-Output ("Updated {0} branch source" -f $branch)
      }

   } catch {
      Write-Output ("Failed to update {0} branch with updated module metadata" -f $branch)
      $_ | Format-List -Force
   }

}

