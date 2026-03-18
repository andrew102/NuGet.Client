# Testing Central Package Management (CPM) support for legacy projects

This guide explains how to build this fork locally and verify that the CPM fix for legacy (non-SDK-style) `.csproj` projects works correctly in Visual Studio.

## Background

The fix is in `LegacyPackageReferenceProject.InstallPackageAsync` — when `ManagePackageVersionsCentrally=true`:

* `<PackageReference Include="Foo" />` is written to the `.csproj` **without a version**.
* The version is added / updated as `<PackageVersion Include="Foo" Version="x.y.z" />` inside `Directory.Packages.props`.

---

## Prerequisites

| Requirement | Details |
|---|---|
| **Windows** | The Visual Studio client code compiles only on Windows. |
| **Visual Studio 2022 17.4+** | Install the workloads listed in [`.vsconfig`](../.vsconfig). |
| **Windows PowerShell 3.0+** | Used for the build and test scripts. |
| **Git** | To clone / manage the fork. |

---

## Step 1 — Clone the fork and configure

Open a **PowerShell** console and run:

```powershell
git clone https://github.com/andrew102/NuGet.Client.git
cd NuGet.Client

# Installs required VS components and build tools
.\configure.ps1
```

> Run `configure.ps1` at least once before the first build. It installs missing tools and sets up the environment.

---

## Step 2 — Build the solution

```powershell
.\build.ps1
```

This produces the VSIX extension at:

```
artifacts\VS15\NuGet.Tools.vsix
```

To also run unit tests during the build:

```powershell
.\build.ps1 -RunUnitTests
```

---

## Step 3 — Run tests for the changed code

The unit tests for the fix are in:

```
test\NuGet.Clients.Tests\NuGet.PackageManagement.VisualStudio.Test\ProjectSystems\LegacyPackageReferenceProjectTests.cs
```

To run only those tests from PowerShell, open the **Developer PowerShell for VS 2022** and run:

```powershell
cd path\to\NuGet.Client

dotnet test `
  test\NuGet.Clients.Tests\NuGet.PackageManagement.VisualStudio.Test\NuGet.PackageManagement.VisualStudio.Test.csproj `
  --filter "FullyQualifiedName~InstallPackageAsync_WithCPMEnabled" `
  --no-restore
```

You should see:

```
Passed  InstallPackageAsync_WithCPMEnabled_AddsPackageReferenceWithoutVersion
Passed  InstallPackageAsync_WithCPMEnabled_UpdatesDirectoryPackagesProps
```

---

## Step 4 — Install the built extension in Visual Studio

You have two options:

### Option A — Experimental instance (recommended for development)

1. Open `NuGet.sln` (or `NuGet-VS.slnf`) in Visual Studio.
2. In **Solution Explorer**, right-click the `NuGet.VisualStudio.Client` project and choose **Set as Startup Project**.
3. Press **F5** (or choose **Debug > Start Debugging**).

Visual Studio will build the VSIX and automatically deploy it to a separate **experimental instance** of Visual Studio, then launch that instance. Your main VS installation remains untouched.

### Option B — Install into your main Visual Studio

1. Open the **Developer Command Prompt for VS 2022**.
2. Run:

```cmd
VSIXInstaller.exe artifacts\VS15\NuGet.Tools.vsix
```

To **revert** to the original NuGet extension afterwards:

```cmd
VSIXInstaller.exe /d:NuGet.72c5d240-f742-48d4-a0f1-7016671e405b
```

---

## Step 5 — Create a test solution

Use the helper script included in this repository to create a ready-to-use test solution with CPM enabled and a legacy `.csproj` project:

```powershell
scripts\Create-CpmLegacyTestSolution.ps1 -OutputDir C:\Temp\CpmTest
```

The script creates:

```
C:\Temp\CpmTest\
├── Directory.Packages.props    ← CPM enabled; initially empty
├── CpmTest.sln
└── LegacyApp\
    └── LegacyApp.csproj        ← non-SDK-style (legacy PackageReference) project
```

Open `CpmTest.sln` in the experimental instance of Visual Studio launched in Step 4.

---

## Step 6 — Verify the fix

1. In the **experimental** Visual Studio, open **Tools > NuGet Package Manager > Manage NuGet Packages for Solution…**
2. Select the `LegacyApp` project.
3. Browse for any package (e.g. `Newtonsoft.Json`) and click **Install**.
4. After the install completes, open the files and check:

**`LegacyApp\LegacyApp.csproj`** should contain:

```xml
<PackageReference Include="Newtonsoft.Json" />
```

(No `Version` attribute — ✅ correct CPM behavior.)

**`Directory.Packages.props`** should contain:

```xml
<ItemGroup>
  <PackageVersion Include="Newtonsoft.Json" Version="13.0.3" />
</ItemGroup>
```

(Version is stored centrally — ✅ correct CPM behavior.)

---

## Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| Version still appears in `.csproj` | The old NuGet is still loaded. Make sure you started the **experimental** instance, or re-run the VSIX installer. |
| `Directory.Packages.props` not updated | Verify that `<ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>` is present in that file. |
| Build fails with "reference assemblies not found" | You need the **.NET Framework 4.7.2 targeting pack**. Install it via the VS Installer. |
| `configure.ps1` fails | Make sure you have all workloads listed in `.vsconfig`. Re-run the VS Installer. |

---

## Related files changed in this fix

| File | What changed |
|---|---|
| `src/.../Projects/LegacyPackageReferenceProject.cs` | `InstallPackageAsync` detects CPM and writes version to `Directory.Packages.props` instead of `.csproj`. |
| `src/.../ProjectServices/VsManagedLanguagesProjectSystemServices.cs` | `AddOrUpdatePackageReference` handles `null` version (CPM path) by passing an empty string. |
| `test/.../ProjectSystems/LegacyPackageReferenceProjectTests.cs` | Two new unit tests covering the CPM path. |

See also [debugging.md](debugging.md#debugging-and-testing-nuget-in-visual-studio) for the general approach to testing NuGet changes in Visual Studio.
