{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Strings;

{$mode objfpc}{$H+}

interface

resourcestring
  { Identity page }
  SDescName        = 'The project name used in generated files and dependency references.';
  SDescVersion     = 'Semantic version (e.g. 1.0.0). Leave blank to inherit from a parent POM.';
  SDescAuthor      = 'Author name or contact, written into generated project files.';
  SDescLicense     = 'SPDX license identifier (e.g. MIT, BSD-3-Clause, GPL-3.0-only).';
  SDescDescription = 'Short human-readable description of what this project does.';
  SDescProjectUrl  = 'URL of the project homepage or documentation site.';
  SDescRepoUrl     = 'URL of the source code repository (e.g. GitHub clone URL).';
  SDescProfiles    = 'Named build profiles (e.g. debug, release) with their own defines and compiler options.';

  { Main page }
  SDescBuildDeps   = 'Compiler settings, source paths, and external package dependencies for this project.';

  { Build page }
  SDescMainSource    = 'Entry-point source file passed to the compiler (e.g. Main.pas).';
  SDescOutputDir     = 'Directory where compiled binaries and units are written.';
  SDescSourceDir     = 'Root of the source tree; used to locate units automatically.';
  SDescExeName       = 'Name of the produced executable (without extension).';
  SDescUnitPaths     = 'Extra paths searched for compiled units, with optional conditions.';
  SDescDefines       = 'Conditional defines passed to the compiler (e.g. DEBUG, UNICODE).';
  SDescDependencies      = 'External package dependencies resolved from the local repository.';
  SDescModuleDeps        = 'Sibling modules in this multi-module project that this module depends on.';
  SDescBootstrapExclude  = 'Units excluded from the auto-generated bootstrap program.';
  SDescSourcePkgIncludes = 'Extra paths included when running pasbuild source-package.';
  SDescIncludePaths      = 'Extra directories searched for include files (FPC -Fi flag).';

  { Profiles page }
  SDescProfileID      = 'Unique identifier for this profile, used with -p on the command line.';
  SDescProfileDefines = 'Conditional defines added when this profile is active.';
  SDescProfileOptions = 'Extra compiler flags added when this profile is active (e.g. -gw -O2).';
  SDescDeleteProfile  = 'Permanently remove this profile from the project.';
  SDescDupProfile     = 'Create a copy of this profile with a new name.';

  { Modules page }
  SDescModules    = 'Sub-projects managed as part of this multi-module build.';
  SDescCreateMod  = 'Run pasbuild init to scaffold a new sub-module in a subdirectory.';
  SDescScanMods   = 'Scan subdirectories for existing project.xml files to add as modules.';
  SDescAddModPath = 'Manually enter the relative path of an existing module.';

  { Dependencies }
  SDescDepVersion = 'The version of this package to use. Choose from available repository versions.';
  SDescRemoveDep  = 'Remove this dependency from the project.';

implementation

end.
