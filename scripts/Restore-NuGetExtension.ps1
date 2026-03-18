<#
.SYNOPSIS
    Safely uninstalls the custom NuGet extension and restores Visual Studio's
    original (bundled) NuGet version.

.DESCRIPTION
    When you install a locally built NuGet.Tools.vsix into your main Visual Studio
    installation, NuGet is treated as a system component and cannot be removed
    through the normal Extensions Manager UI.

    This script:
      1. Locates your Visual Studio installation automatically via vswhere.
      2. Closes any running VS processes for that instance.
      3. Calls VSIXInstaller.exe /d to remove the custom NuGet extension.
         Visual Studio will then fall back to its own bundled NuGet version.
      4. Clears the MEF component cache so VS picks up the change cleanly.
      5. Runs /updateConfiguration to finish the revert.

    If the VSIX downgrade fails with a "previous install not completed" error, the
    script triggers a "vs_installer.exe resume" pass before retrying.

    NOTE: This script requires an elevated (Administrator) PowerShell prompt.

    If you used the RECOMMENDED approach (F5 from NuGet.VisualStudio.Client) the
    custom NuGet was deployed only to the ISOLATED experimental instance and your
    main VS installation was never touched.  In that case you do NOT need to run
    this script — just reset the experimental instance (see -ResetExperimental).

.PARAMETER InstanceId
    Optional.  The specific Visual Studio instance ID to target.
    When omitted the script targets the latest installed VS 2022 instance.

.PARAMETER ResetExperimental
    When specified the script resets the VS experimental instance instead of
    uninstalling the VSIX from your main VS installation.  This is a safe,
    isolated operation that does not affect your main VS at all.

.PARAMETER TimeoutSeconds
    How long (in seconds) to wait for VSIXInstaller.exe to finish.
    Default: 120.

.EXAMPLE
    # Run from an elevated prompt — revert main VS installation:
    .\scripts\Restore-NuGetExtension.ps1

.EXAMPLE
    # Reset only the experimental instance (F5 path — no admin needed):
    .\scripts\Restore-NuGetExtension.ps1 -ResetExperimental

.EXAMPLE
    # Target a specific VS instance by its ID:
    .\scripts\Restore-NuGetExtension.ps1 -InstanceId 3f9abc12
#>

[CmdletBinding(DefaultParameterSetName = 'Main')]
param (
    [Parameter(ParameterSetName = 'Main')]
    [string]$InstanceId,

    [Parameter(ParameterSetName = 'Experimental')]
    [switch]$ResetExperimental,

    [int]$TimeoutSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── NuGet extension product ID (constant across versions) ─────────────────────
$NuGetExtensionId = 'NuGet.72c5d240-f742-48d4-a0f1-7016671e405b'

# ── helpers ───────────────────────────────────────────────────────────────────

function Find-VsWhere {
    $path = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $path)) {
        throw "vswhere.exe not found at '$path'. Make sure Visual Studio is installed."
    }
    return $path
}

function Get-VSInstance {
    param([string]$InstanceId)

    $vswhere = Find-VsWhere

    if ($InstanceId) {
        $instances = & $vswhere -prerelease -nologo -format json | ConvertFrom-Json
        $instance  = $instances | Where-Object { $_.instanceId -eq $InstanceId }
        if (-not $instance) { throw "VS instance '$InstanceId' not found." }
        return $instance
    }

    # latest VS 2022
    $instance = & $vswhere -latest -prerelease -version '[17.0,18.0)' -nologo -format json | ConvertFrom-Json
    if (-not $instance) {
        $instance = & $vswhere -latest -prerelease -nologo -format json | ConvertFrom-Json
    }
    if (-not $instance) { throw 'No Visual Studio installation found.' }
    return $instance
}

function Get-VsixInstallerPath {
    param($VSInstance)
    $exe = Get-ChildItem -Recurse -ErrorAction SilentlyContinue `
                         -Path $VSInstance.installationPath `
                         -Filter 'VSIXInstaller.exe' |
           Select-Object -First 1
    if (-not $exe) { throw 'VSIXInstaller.exe not found in VS installation.' }
    return $exe.FullName
}

function Stop-VSProcesses {
    param($VSInstance)
    $installPath = $VSInstance.installationPath
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and $_.Path.StartsWith($installPath, [StringComparison]::OrdinalIgnoreCase)
    } | ForEach-Object {
        Write-Host "  Stopping process: $($_.Name) (PID $($_.Id))"
        Stop-Process $_ -Force -ErrorAction SilentlyContinue
    }
}

function Clear-MEFCache {
    param($VSInstance)
    $exeVersion = $VSInstance.installationVersion
    $major      = $exeVersion.Substring(0, $exeVersion.IndexOf('.'))
    $cachePath  = Join-Path $env:LOCALAPPDATA `
                            "Microsoft\VisualStudio\${major}.0_$($VSInstance.instanceId)\ComponentModelCache"
    if (Test-Path $cachePath) {
        Write-Host "  Clearing MEF cache: $cachePath"
        Remove-Item -Recurse -Force $cachePath
        Write-Host '  MEF cache cleared.'
    } else {
        Write-Host '  MEF cache not found (nothing to clear).'
    }
}

function Invoke-VsixInstaller {
    param(
        [string]$InstallerPath,
        [string]$Arguments
    )
    Write-Host "  Running: `"$InstallerPath`" $Arguments"
    $p = Start-Process -FilePath $InstallerPath `
                       -ArgumentList $Arguments `
                       -Wait -PassThru -NoNewWindow
    return $p.ExitCode
}

function Resume-VSInstall {
    param($VSInstance)

    $pfx86 = ${env:ProgramFiles(x86)}
    if (-not $pfx86) { $pfx86 = $env:ProgramFiles }
    $vsInstallerPath = "$pfx86\Microsoft Visual Studio\Installer\vs_installer.exe"
    if (-not (Test-Path $vsInstallerPath)) { return $false }

    $installPath = $VSInstance.installationPath
    Write-Host "  Resuming interrupted VS install: vs_installer.exe resume --installPath `"$installPath`" -q"
    $p = Start-Process $vsInstallerPath -ArgumentList "resume --installPath `"$installPath`" -q" `
                       -Wait -PassThru -NoNewWindow
    return $p.ExitCode -eq 0
}

# ── experimental instance reset ───────────────────────────────────────────────

function Reset-ExperimentalInstance {
    Write-Host ''
    Write-Host '=== Resetting the VS experimental instance ==='
    Write-Host ''
    Write-Host 'The experimental instance stores its data in:'
    Write-Host "  %LOCALAPPDATA%\Microsoft\VisualStudio\<version>_<instanceId>Exp"
    Write-Host ''

    $vsExperimentalBase = Join-Path $env:LOCALAPPDATA 'Microsoft\VisualStudio'
    $expDirs = Get-ChildItem -Path $vsExperimentalBase -Directory -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -match 'Exp$' }

    if (-not $expDirs) {
        Write-Host 'No experimental instance directories found — nothing to do.'
        return
    }

    foreach ($dir in $expDirs) {
        Write-Host "  Found experimental instance: $($dir.FullName)"
        $answer = Read-Host '  Delete this directory? [y/N]'
        if ($answer -ieq 'y') {
            Remove-Item -Recurse -Force $dir.FullName
            Write-Host "  Deleted: $($dir.FullName)"
        } else {
            Write-Host '  Skipped.'
        }
    }

    Write-Host ''
    Write-Host 'Done. The experimental instance will be recreated fresh the next time you press F5.'
}

# ── main revert logic ─────────────────────────────────────────────────────────

function Restore-NuGetVsix {
    # Admin check
    $currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This script must be run from an elevated (Administrator) PowerShell prompt.'
    }

    Write-Host ''
    Write-Host '=== Reverting custom NuGet extension from main VS installation ==='
    Write-Host ''

    $vsInstance    = Get-VSInstance -InstanceId $InstanceId
    $vsixInstaller = Get-VsixInstallerPath $vsInstance

    Write-Host "Target VS instance : $($vsInstance.displayName) $($vsInstance.installationVersion)"
    Write-Host "Installation path  : $($vsInstance.installationPath)"
    Write-Host "VSIXInstaller.exe  : $vsixInstaller"
    Write-Host ''

    # ── 1. Close Visual Studio ─────────────────────────────────────────────────
    Write-Host 'Step 1: Closing Visual Studio processes...'
    Stop-VSProcesses $vsInstance
    Write-Host '  Done.'
    Write-Host ''

    # ── 2. Downgrade / remove custom NuGet extension ──────────────────────────
    Write-Host 'Step 2: Removing custom NuGet extension...'
    $args    = "/q /a /d:$NuGetExtensionId /instanceIds:$($vsInstance.instanceId)"
    $maxTries = 3
    $attempt  = 0
    $success  = $false

    while (-not $success -and $attempt -lt $maxTries) {
        $attempt++
        Write-Host "  Attempt $attempt of $maxTries..."

        $exitCode = Invoke-VsixInstaller -InstallerPath $vsixInstaller -Arguments $args

        switch ($exitCode) {
            0 {
                Write-Host '  Extension removed successfully.'
                $success = $true
            }
            1001 {
                # Extension was not installed — already clean
                Write-Host '  Custom extension was not installed (already clean).'
                $success = $true
            }
            -2146233079 {
                Write-Host '  Previous VSIX install appears incomplete. Attempting to resume VS install...'
                if (Resume-VSInstall $vsInstance) {
                    Write-Host '  VS install resumed. Retrying VSIX removal...'
                } else {
                    Write-Warning '  Could not resume VS install. Proceeding anyway.'
                    $success = $true   # continue — VS repair is the fallback
                }
            }
            default {
                Write-Warning "  VSIXInstaller.exe returned exit code $exitCode."
                if ($attempt -ge $maxTries) {
                    Write-Warning '  All attempts exhausted. Falling back to VS repair (see note below).'
                    $success = $true   # let the user run repair manually
                }
            }
        }
    }
    Write-Host ''

    # ── 3. Clear MEF cache ─────────────────────────────────────────────────────
    Write-Host 'Step 3: Clearing MEF component cache...'
    Clear-MEFCache $vsInstance
    Write-Host ''

    # ── 4. Update VS configuration ─────────────────────────────────────────────
    Write-Host 'Step 4: Updating VS configuration...'
    $p = Start-Process -FilePath $vsInstance.productPath `
                       -ArgumentList '/updateConfiguration' `
                       -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -eq 0) {
        Write-Host '  Configuration updated.'
    } else {
        Write-Warning "  /updateConfiguration exited with code $($p.ExitCode) — this is usually harmless."
    }
    Write-Host ''

    # ── 5. Summary ─────────────────────────────────────────────────────────────
    Write-Host '=== Revert complete ==='
    Write-Host ''
    Write-Host 'Visual Studio will use its own bundled NuGet version the next time it starts.'
    Write-Host ''
    Write-Host 'If NuGet still misbehaves after launching VS, run a repair from the VS Installer:'
    Write-Host '  1. Open the Visual Studio Installer.'
    Write-Host "  2. Find the instance: $($vsInstance.displayName)"
    Write-Host '  3. Click the "More" dropdown and select "Repair".'
}

# ── entry point ────────────────────────────────────────────────────────────────

if ($ResetExperimental) {
    Reset-ExperimentalInstance
} else {
    Restore-NuGetVsix
}
