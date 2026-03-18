# SPDX-License-Identifier: BSD-3-Clause
# Copyright (C) 2025-2026 Taylor (Wakana Kisarazu)

# REMOVE WHEN SEEN - But, when others make changes to
# forge, add your ID/Name/Email/Discord whatever to
# the copyright notice to indicate your changes
import std/[posix, os, osproc, strformat, strutils, httpclient, re, times]
import zippy/tarballs
import regex
import "console", "handler", "lock"


when not defined(debug):
    {.push optimization:speed, checks:off, warnings:off.}

const
    TEMP_DIR    = "/tmp/forge"
    WORLD_DIR   = "/var/forge/world"
    REPO_DIR    = "/var/forge/repo"
    LOCK_PATH   = TEMP_DIR / "forge.lock"
    PKG_RE      = re2"^[a-zA-Z0-9][a-zA0-9._-]*$"


if not checkCanExecute():
  programExit("Cannot execute: insufficient permissions or no operation specified.")

let
    CMDLINE     = commandLineParams()
    REPO_DATA   = readFile(REPO_DIR).strip()
    OPERATION   = CMDLINE[0]


if OPERATION notin ["install", "remove", "list", "info"]:
    programExit(fmt"Operation not supported: {OPERATION}")
    printUsage()


let PKGS = if paramCount() > 1: CMDLINE[1..^1] else: @[]

let FIND_DIRS = ["/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/local/bin", "/usr/lib", "/usr/local/lib", "/usr/share", "/usr/include", "lib", "lib64", "/usr/libexec", "/usr/src"]

createDir(WORLD_DIR)

proc install(name: string) =
    consoleInfo(fmt"Downloading source for {name}")
    consoleDebug(fmt"Connecting to {REPO_DIR}...")

    let workdir = TEMP_DIR / name
    let pkgsrc = fmt"{TEMP_DIR}/{name}.tar.gz"
    let client = newHttpClient()
    client.downloadFile(fmt"{REPO_DATA}/{name}.tar.gz", pkgsrc)
    consoleOkay(fmt"Downloaded {name} from {REPO_DIR}")

    consoleDimSep()

    consoleInfo("Extracting source.\n")

    extractAll(pkgsrc, workdir)
    consoleOkay("Source extracted.")
    if fileExists(fmt"{workdir}/depends"):
        for dep in lines(fmt"{workdir}/depends"):
            let i = dep.strip()

            if i.len == 0:
                continue

            if fileExists(fmt"/var/forge/world/{i}"):
                consoleWarn(fmt"Dependency {i} is already installed, skipping.")
                continue
            consoleInfo(fmt"Installing dependency: {i}")
            sleep(1000)
            try:
              install(i)
            except Exception as e:
              consoleFail(fmt"Failed to install dependency {i}: {e.msg}")
              programExit("Dependency error")
    else:
      consoleInfo("No dependencies found.")

    consoleDimSep()

    consoleInfo("Building package.")
    consoleDimSep()

    let markerTime = getTime()
    sleep(1000)
    let buildsh = readFile(fmt"{TEMP_DIR}/{name}/build.sh")
    echo buildsh

    consoleDimSep()

    if execCmd(fmt"cd {TEMP_DIR}/{name} && sh build.sh") != 0:
        consoleFail("Build failed.")
        programExit("Build error")

    let installLog = fmt"/var/forge/world/{name}_installed"
    consoleInfo("Tracking installed files...")

    var logFile = open(installLog, fmWrite)
    try:
        for dir in FIND_DIRS:
            if dirExists(dir):
                for path in walkDirRec(dir, yieldFilter={pcFile, pcLinkToFile}):
                    try:
                        if getLastModificationTime(path) > markerTime:
                            logFile.writeLine(path)
                    except OSError:
                        discard
    finally:
        logFile.close()

    writeFile(fmt"/var/forge/world/{name}", "")
    consoleOkay(fmt"{name} has been installed successfully.")
    removeDir(workDir)

proc list() =
    var count = 0
    for kind, path in walkDir(WORLD_DIR):
        if kind == pcFile:
            let name = extractFilename(path)
            if not name.endsWith("_installed"):
                echo name
                inc count
    if count == 0:
        consoleInfo("No packages installed.")
    else:
      consoleInfo(fmt"{count} package(s) installed.")



proc info(name: string) =
    let markerPath = WORLD_DIR / name
    let installedPath = WORLD_DIR / (name & "_installed")

    if not fileExists(markerPath):
        consoleFail(fmt"{name} is not installed.")
        return

    consoleInfo(fmt"Package: {name}")

    if fileExists(installedPath):
        let files = readFile(installedPath).splitLines()
        var fileCount = 0
        for f in files:
            if f.strip().len > 0:
                inc fileCount
        consoleInfo(fmt"Installed files: {fileCount}")
        consoleDimSep()
        for f in files:
            let path = f.strip()
            if path.len > 0:
                echo "  ", path
    else:
        consoleWarn("No installed file manifest found.")

proc remove(name: string) =
    let tbr = readFile(fmt"/var/forge/world/{name}_installed").splitLines()
    for item in tbr:
        let path = item.strip()
        if path.len == 0: continue
        if fileExists(path) or symlinkExists(path): # changed that cuz remove script literally removed my /usr/bin
          removeFile(path)
          echo "Removed: ", path
    consoleInfo("Deregestering from world set.")
    removeFile(fmt"/var/forge/world/{name}_installed")
    removeFile(fmt"/var/forge/world/{name}")
    consoleOkay(fmt"{name} has been removed.")

case OPERATION
of "install":
  withLock(LOCK_PATH):
    for pkg in PKGS:
      install(pkg)
of "remove":
  withLock(LOCK_PATH):
    for pkg in PKGS:
      remove(pkg)
of "list":
  list()
of "info":
  for pkg in PKGS:
    info(pkg)
else:
    programExit("Operation not supported: {OPERATION}")
    printUsage()
