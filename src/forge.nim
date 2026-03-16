import os, osproc, strformat, httpclient, strutils, posix, re, times
stdout.flushFile()

if getuid() != 0:
  stderr.writeLine("You need to be a superuser to run the forge package manager.")
  quit(1)
const
  TMP = "/tmp/hypernova"
  WORLD_DIR = "/var/forge/world"
  SEPARATOR = "----------------------------------------"
  VALID_PKG_PATTERN = re"^[a-zA-Z0-9][a-zA0-9._-]*$"

proc printUsage() =
    echo """Usage: forge <operation> <package>
    Operations:
        install - Install a package
        remove - Remove a package
    """

if paramCount() == 0:
  printUsage()
  quit(1)


let PARAMS = commandLineParams()
let OP = PARAMS[0]

if OP notin ["install", "remove", "list", "info"]:
  echo fmt"Error: Unknown operation '{OP}'"
  printUsage()
  quit(1)

let PKGS = if paramCount() > 1: PARAMS[1..^1] else: @[]
let REPO = readFile("/var/hypernova/repo").strip()
createDir(WORLD_DIR)

proc validatePkgName(name: string): bool =
    ## Reject anything that could be used for path traversal or injection.
    if name.len == 0 or name.len > 128:
      return false
    if ".." in name or "/" in name or "\\" in name:
      return false

    return name.match(VALID_PKG_PATTERN)

let lockPath = TMP / "forge.lock"

proc acquireLock() =
  createDir(TMP)
  if fileExists(lockPath):
    let age = getTime() - getLastModificationTime(lockPath)
    if age.inHours < 1:
      stderr.writeLine("Error: Another forge process is running (lockfile exists).")
      stderr.writeLine("If this is stale, remove ", & lockPath)
      quit(1)
    else:
      echo "Removing stale lockfile."
      removeFile(lockPath)
  writeFile(lockPath, $getCurrentProcessId())

proc releaseLock() =
  if fileExists(lockPath):
    removeFile(lockPath)

proc install(name: string) =
    echo "Downloading source."
    echo fmt"Connecting to {REPO}..."

    let workdir = TMP / name
    createDir(workdir)
    let pkgsrc = workdir / (name & ".tar.gz")
    let client = newHttpClient()
    client.downloadFile(fmt"{REPO}/{name}.tar.gz", pkgsrc)
    echo fmt"Successfully downloaded {name} from {REPO}"

    echo SEPARATOR

    echo "Extracting source.\n"

    discard execCmd(fmt"tar -xzvf {pkgsrc} -C {TMP}/{name}")
    echo "Source extracted."

    if fileExists(fmt"{TMP}/{name}/depends"):
        for dep in readFile(fmt"{TMP}/{name}/depends").splitLines():
            let i = dep.strip()

            if i.len == 0:
                continue

            if fileExists(fmt"/var/forge/world/{i}"):
                echo fmt"Dependency {i} is already installed, skipping."
                continue
            echo fmt"Installing dependency: {i}"
            sleep(1000)
            try:
              install(dep)
            except Exception as e:
              stderr.writeLine(fmt"Error: Failed to install dependency {i}: {e.msg}")
              quit(1)
    else:
        echo "No dependencies found."

    echo SEPARATOR

    echo "Building package."
    echo SEPARATOR

    let timeMarker = TMP / (name & "_marker")
    sleep(1000)
    discard execCmd("touch " & timeMarker)
    sleep(1000)
    let buildsh = readFile(fmt"{TMP}/{name}/build.sh")
    echo buildsh

    echo SEPARATOR

    if execCmd(fmt"cd {TMP}/{name} && sh build.sh") != 0:
        echo "Error: Build failed."
        quit(1)
    
    let dirs = "/bin /sbin /usr/bin /usr/sbin /usr/include /usr/share /usr/lib /usr/lib64 /usr/local/bin /usr/local/lib /etc /lib /lib64"
    let installLog = fmt"/var/forge/world/{name}_installed"
    echo "Tracking installed files..."
    discard execCmd(fmt"find {dirs} -newer {timeMarker} ! -type d 2>/dev/null > {installLog}")
    writeFile(fmt"/var/forge/world/{name}", "")
    removeFile(timeMarker)
    echo fmt"{name} has been installed succesfully."
proc remove(name: string) =
    let tbr = readFile(fmt"/var/forge/world/{name}_installed").splitLines()
    for item in tbr:
        let path = item.strip()
        if path.len == 0: continue
        if fileExists(path) or symlinkExists(path): # changed that cuz remove script literally removed my /usr/bin
          removeFile(path)
          echo "Removed: ", path
    echo "Deregestering from world set."
    removeFile(fmt"/var/forge/world/{name}_installed")
    removeFile(fmt"/var/forge/world/{name}")

case OP
of "install":
  acquireLock()
  try:
    for pkg in PKGS:
      install(pkg)
  finally:
    releaseLock()
of "remove":
  acquireLock()
  try:
    for pkg in PKGS:
      remove(pkg)
  finally:
      releaseLock()
else:
  echo fmt"Error: Unknown operation '{OP}'"
  printUsage()
  quit(1)
