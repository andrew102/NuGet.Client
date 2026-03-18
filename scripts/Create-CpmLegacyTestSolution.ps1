<#
.SYNOPSIS
    Creates a minimal test solution that reproduces the scenario for the CPM legacy-project fix.

.DESCRIPTION
    Generates a solution containing:
      - Directory.Packages.props with ManagePackageVersionsCentrally=true
      - A non-SDK-style (legacy PackageReference) .csproj project
      - A .sln file that references the project

    Open the generated .sln in the experimental Visual Studio instance (started by pressing F5
    on the NuGet.VisualStudio.Client project) to verify that installing a package:
      * writes <PackageReference> WITHOUT a Version into the .csproj
      * writes <PackageVersion> WITH the version into Directory.Packages.props

.PARAMETER OutputDir
    Directory where the test solution will be created.  Defaults to %TEMP%\CpmLegacyTest.

.EXAMPLE
    .\scripts\Create-CpmLegacyTestSolution.ps1 -OutputDir C:\Temp\CpmTest
#>

[CmdletBinding()]
param (
    [string]$OutputDir = (Join-Path $env:TEMP 'CpmLegacyTest')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── paths ──────────────────────────────────────────────────────────────────────
$projectDir  = Join-Path $OutputDir 'LegacyApp'
$projectFile = Join-Path $projectDir 'LegacyApp.csproj'
$propsFile   = Join-Path $OutputDir 'Directory.Packages.props'
$slnFile     = Join-Path $OutputDir 'CpmTest.sln'

Write-Host "Creating test solution in: $OutputDir"
New-Item -ItemType Directory -Force -Path $projectDir | Out-Null

# ── Directory.Packages.props ───────────────────────────────────────────────────
@'
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>
</Project>
'@ | Set-Content -Encoding UTF8 -Path $propsFile

Write-Host "  Created: $propsFile"

# ── LegacyApp.csproj (non-SDK-style / legacy PackageReference format) ──────────
@'
<?xml version="1.0" encoding="utf-8"?>
<Project ToolsVersion="15.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props"
          Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
  <PropertyGroup>
    <Configuration Condition=" '$(Configuration)' == '' ">Debug</Configuration>
    <Platform Condition=" '$(Platform)' == '' ">AnyCPU</Platform>
    <ProjectGuid>{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}</ProjectGuid>
    <OutputType>Library</OutputType>
    <AppDesignerFolder>Properties</AppDesignerFolder>
    <RootNamespace>LegacyApp</RootNamespace>
    <AssemblyName>LegacyApp</AssemblyName>
    <TargetFrameworkVersion>v4.7.2</TargetFrameworkVersion>
    <FileAlignment>512</FileAlignment>
    <Deterministic>true</Deterministic>
  </PropertyGroup>
  <ItemGroup>
    <Reference Include="System" />
  </ItemGroup>
  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
</Project>
'@ | Set-Content -Encoding UTF8 -Path $projectFile

Write-Host "  Created: $projectFile"

# ── CpmTest.sln ────────────────────────────────────────────────────────────────
# Project GUID for the solution entry must match ProjectGuid in the .csproj
$projectGuid  = 'A1B2C3D4-E5F6-7890-ABCD-EF1234567890'
$solutionGuid = [System.Guid]::NewGuid().ToString('B').ToUpper()

@"

Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 17
VisualStudioVersion = 17.0.31903.59
MinimumVisualStudioVersion = 10.0.40219.1
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "LegacyApp", "LegacyApp\LegacyApp.csproj", "{$projectGuid}"
EndProject
Global
	GlobalSection(SolutionConfigurationPlatforms) = preSolution
		Debug|Any CPU = Debug|Any CPU
		Release|Any CPU = Release|Any CPU
	EndGlobalSection
	GlobalSection(ProjectConfigurationPlatforms) = postSolution
		{$projectGuid}.Debug|Any CPU.ActiveCfg = Debug|AnyCPU
		{$projectGuid}.Debug|Any CPU.Build.0 = Debug|AnyCPU
		{$projectGuid}.Release|Any CPU.ActiveCfg = Release|AnyCPU
		{$projectGuid}.Release|Any CPU.Build.0 = Release|AnyCPU
	EndGlobalSection
	GlobalSection(SolutionProperties) = preSolution
		HideSolutionNode = FALSE
	EndGlobalSection
	GlobalSection(ExtensibilityGlobals) = postSolution
		SolutionGuid = $solutionGuid
	EndGlobalSection
EndGlobal
"@ | Set-Content -Encoding UTF8 -Path $slnFile

Write-Host "  Created: $slnFile"
Write-Host ""
Write-Host "Done!  Open this solution in the NuGet experimental VS instance to test the CPM fix:"
Write-Host "  $slnFile"
Write-Host ""
Write-Host "Expected behavior after installing a package via the Package Manager UI:"
Write-Host "  - LegacyApp\LegacyApp.csproj   => <PackageReference Include='X' />  (no Version)"
Write-Host "  - Directory.Packages.props      => <PackageVersion Include='X' Version='y.y.y' />"
