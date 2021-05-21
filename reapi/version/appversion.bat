@setlocal enableextensions enabledelayedexpansion
@echo off
::
:: Pre-build auto-versioning script
::

chcp 65001

set srcdir=%~1
set repodir=%~2
set fileinc=%~3

set old_version=
set old_version_inc=
set version_major=0
set version_minor=0
set version_maintenance=0
set version_modifed=
set genereate_inc=0

set commitSHA=
set commitURL=
set commitCount=0
set branch_name=master

for /f "delims=" %%a in ('wmic OS Get localdatetime  ^| find "."') do set "dt=%%a"
set "YYYY=%dt:~0,4%"
set "MM=%dt:~4,2%"
set "DD=%dt:~6,2%"
set "hour=%dt:~8,2%"
set "min=%dt:~10,2%"
set "sec=%dt:~12,2%"

::
:: Remove leading zero from MM (e.g 09 > 9)
::
for /f "tokens=* delims=0" %%I in ("%MM%") do set MM=%%I

::
:: Index into array to get month name
::
for /f "tokens=%MM%" %%I in ("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec") do set "month=%%I"

::
:: Check for git.exe presence
::
CALL git.exe describe >NUL 2>&1
set errlvl="%ERRORLEVEL%"

::
:: Read old appversion.h, if present
::
IF EXIST "%srcdir%\appversion.h" (
	FOR /F "usebackq tokens=1,2,3" %%i in ("%srcdir%\appversion.h") do (
		IF %%i==#define (
			IF %%j==APP_VERSION (
				:: Remove quotes
				set v=%%k
				set old_version=!v:"=!
			)
		)
	)
)

::
:: Check %fileinc% if present to generate
::
IF NOT [%fileinc%]==[] (
	set genereate_inc=1
)

::
:: Read old %fileinc%, if present
::
IF [%genereate_inc%]==[1] (
	IF EXIST "%srcdir%\%fileinc%" (
		FOR /F "usebackq tokens=1,2,3" %%i in ("%srcdir%\%fileinc%") do (
			IF %%i==#define (
				IF %%j==REAPI_VERSION (
					:: Remove quotes
					set v=%%k
					set old_version_inc=!v:"=!
				)
			)
		)
	)
)

IF %errlvl% == "1" (
	echo can't locate git.exe - auto-versioning step won't be performed

	:: if we haven't appversion.h, we need to create it
	IF NOT "%old_version%" == "" (
		set commitCount=0
	)
)

::
:: Read major, minor and maintenance version components from Version.h
::
IF EXIST "%srcdir%\version.h" (
	FOR /F "usebackq tokens=1,2,3" %%i in ("%srcdir%\version.h") do (
		IF %%i==#define (
			IF %%j==VERSION_MAJOR set version_major=%%k
			IF %%j==VERSION_MINOR set version_minor=%%k
			IF %%j==VERSION_MAINTENANCE set version_maintenance=%%k
		)
	)
)

::
:: Read revision and release date from it
::
IF NOT %errlvl% == "1" (
	:: Get current branch
	FOR /F "tokens=*" %%i IN ('"git -C "%repodir%\." rev-parse --abbrev-ref HEAD"') DO (
		set branch_name=%%i
	)

	FOR /F "tokens=*" %%i IN ('"git -C "%repodir%\." rev-list --count !branch_name!"') DO (
		IF NOT [%%i] == [] (
			set commitCount=%%i
		)
	)
)

::
:: Get remote url repository
::
IF NOT %errlvl% == "1" (

	set branch_remote=origin
	:: Get remote name by current branch
	FOR /F "tokens=*" %%i IN ('"git -C "%repodir%\." config branch.!branch_name!.remote"') DO (
		set branch_remote=%%i
	)
	:: Get remote url
	FOR /F "tokens=2 delims=@" %%i IN ('"git -C "%repodir%\." config remote.!branch_remote!.url"') DO (
		set commitURL=%%i
	)
	:: Get commit id
	FOR /F "tokens=*" %%i IN ('"git -C "%repodir%\." rev-parse --verify HEAD"') DO (
		set shafull=%%i
		set commitSHA=!shafull:~0,+7!
	)

	IF [!commitURL!] == [] (

		FOR /F "tokens=1" %%i IN ('"git -C "%repodir%\." config remote.!branch_remote!.url"') DO (
			set commitURL=%%i
		)

		:: strip .git
		if "x!commitURL:~-4!"=="x.git" (
			set commitURL=!commitURL:~0,-4!
		)

		:: append extra string
		If NOT "!commitURL!"=="!commitURL:bitbucket.org=!" (
			set commitURL=!commitURL!/commits/
		) ELSE (
			set commitURL=!commitURL!/commit/
		)

	) ELSE (
		:: strip .git
		if "x!commitURL:~-4!"=="x.git" (
			set commitURL=!commitURL:~0,-4!
		)
		:: replace : to /
		set commitURL=!commitURL::=/!

		:: append extra string
		If NOT "!commitURL!"=="!commitURL:bitbucket.org=!" (
			set commitURL=https://!commitURL!/commit/
		) ELSE (
			set commitURL=https://!commitURL!/commits/
		)
	)
)

::
:: Detect local modifications
::
set localChanged=0
IF NOT %errlvl% == "1" (
	FOR /F "tokens=*" %%i IN ('"git -C "%repodir%\." ls-files -m"') DO (
		set localChanged=1
	)
)

IF [%localChanged%]==[1] (
	set version_modifed=+m
)

::
:: Now form full version string like 1.0.0.1
::

set new_version_inc=%version_major%%version_minor%%commitCount%
set new_version=%version_major%.%version_minor%.%version_maintenance%.%commitCount%-dev%version_modifed%

::
:: Update appversion.h if version has changed or modifications/mixed revisions detected
::
IF NOT "%new_version%"=="%old_version%" (
	goto _update
)

::
:: Update %fileinc% if version has changed or modifications/mixed revisions detected
::

IF [%genereate_inc%]==[1] (
	IF NOT "%new_version_inc%"=="%old_version_inc%" (
		goto _update
	)
)

goto _exit

:_update

::
:: Write %fileinc%
::
IF [%genereate_inc%]==[1] (
	echo Updating %fileinc%, new version is "%new_version_inc%", the old one was %old_version_inc%

	echo #if defined _reapi_version_included>"%srcdir%\%fileinc%"
	echo 	#endinput>>"%srcdir%\%fileinc%"
	echo #endif>>"%srcdir%\%fileinc%"
	echo #define _reapi_version_included>>"%srcdir%\%fileinc%"

	echo.>>"%srcdir%\%fileinc%"
	>>"%srcdir%\%fileinc%" echo // REAPI version
	>>"%srcdir%\%fileinc%" echo #define REAPI_VERSION %version_major%%version_minor%%commitCount%
	>>"%srcdir%\%fileinc%" echo #define REAPI_VERSION_MAJOR %version_major%
	>>"%srcdir%\%fileinc%" echo #define REAPI_VERSION_MINOR %version_minor%
)

::
:: Write appversion.h
::
echo Updating appversion.h, new version is "%new_version%", the old one was %old_version%

echo #ifndef __APPVERSION_H__>"%srcdir%\appversion.h"
echo #define __APPVERSION_H__>>"%srcdir%\appversion.h"
echo.>>"%srcdir%\appversion.h"
echo //>>"%srcdir%\appversion.h"
echo // This file is generated automatically.>>"%srcdir%\appversion.h"
echo // Don't edit it.>>"%srcdir%\appversion.h"
echo //>>"%srcdir%\appversion.h"
echo.>>"%srcdir%\appversion.h"
echo // Version defines>>"%srcdir%\appversion.h"
echo #define APP_VERSION "%new_version%">>"%srcdir%\appversion.h"

>>"%srcdir%\appversion.h" echo #define APP_VERSION_C %version_major%,%version_minor%,%version_maintenance%,%commitCount%
echo #define APP_VERSION_STRD "%version_major%.%version_minor%.%version_maintenance%.%commitCount%">>"%srcdir%\appversion.h"
echo #define APP_VERSION_FLAGS 0x0L>>"%srcdir%\appversion.h"

echo.>>"%srcdir%\appversion.h"
echo #define APP_COMMIT_DATE "%month% %DD% %YYYY%">>"%srcdir%\appversion.h"
echo #define APP_COMMIT_TIME "%hour%:%min%:%sec%">>"%srcdir%\appversion.h"

echo.>>"%srcdir%\appversion.h"
echo #define APP_COMMIT_SHA "%commitSHA%">>"%srcdir%\appversion.h"
echo #define APP_COMMIT_URL "%commitURL%">>"%srcdir%\appversion.h"
echo.>>"%srcdir%\appversion.h"

echo #endif //__APPVERSION_H__>>"%srcdir%\appversion.h"
echo.>>"%srcdir%\appversion.h"

:_exit
exit /B 0