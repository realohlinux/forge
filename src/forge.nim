import std/[os, osproc, strformat, httpclient, strutils, posix, re, times]
import zippy/tarballs

const
  Reset = "\e[0m"
  Bold = "\e[1m"
  Red = "\e[31m"
  Green = "\e[32m"
  Yellow = "\e[33m"
  Blue = "\e[34m"
  Cyan = "\e[36m"
  Dim = "\e[2m"

proc error(msg: string) =
  stderr.writeLine(fmt"{Bold}{Red}Error:{Reset} {msg}")

proc success(msg: string) =
  echo fmt"{Bold}{Green}✓{Reset} {msg}"

proc info(msg: string) =
  echo fmt"{Bold}{Blue}::{Reset} {msg}"

proc status(msg: string) =
  echo fmt"{Bold}{Cyan}>{Reset} {msg}"

proc warn(msg: string) =
  echo fmt"{Bold}{Yellow}Warning:{Reset} {msg}"

proc dimLine(msg: string) =
  echo fmt"{Dim}{msg}{Reset}"

if getuid() != 0:
  error("You need to be a superuser to run the forge package manager.")
  quit(1)
const
  TMP = "/tmp/forge"
  SEPARATOR = "----------------------------------------"
  WORLD_DIR = "/var/forge/world/"

let VALID_PKG_PATTERN = re"^[a-zA-Z0-9][a-zA0-9._-]*$"

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
let REPO = readFile("/var/forge/repo").strip()
let OP = PARAMS[0]

if OP notin ["install", "remove", "list", "info"]:
  error(fmt"Unknown operation '{OP}'")
  printUsage()
  quit(1)

let PKGS = if paramCount() > 1: PARAMS[1..^1] else: @[]
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
      error("Another forge process is running (lockfile exists).")
      warn("If this is stale, remove " & lockPath)
      quit(1)
    else:
      warn("Removing stale lockfile.")
      removeFile(lockPath)
  writeFile(lockPath, $getCurrentProcessId())

proc releaseLock() =
  if fileExists(lockPath):
    removeFile(lockPath)

proc install(name: string) =
    info(fmt"Downloading source for {Bold}{name}{Reset}")
    status(fmt"Connecting to {REPO}...")

    let workdir = TMP / name
    createDir(workdir)
    let pkgsrc = TMP / (name & ".tar.gz")
    let client = newHttpClient()
    client.downloadFile(fmt"{REPO}/{name}.tar.gz", pkgsrc)
    success(fmt"Downloaded {name} from {REPO}")

    dimLine(SEPARATOR)

    info("Extracting source.\n")
    
    if dirExists(workdir):
        removeDir(workdir)

    extractAll(pkgsrc, workdir)
    removeFile(pkgsrc)
    success("Source extracted.")

    if fileExists(fmt"{TMP}/{name}/depends"):
        for dep in lines(fmt"{TMP}/{name}/depends"):
            let i = dep.strip()

            if i.len == 0:
                continue

            if fileExists(fmt"/var/forge/world/{i}"):
                warn(fmt"Dependency {i} is already installed, skipping.")
                continue
            info(fmt"Installing dependency: {Bold}{i}{Reset}")
            sleep(1000)
            try:
              install(i)
            except Exception as e:
              error(fmt"Failed to install dependency {i}: {e.msg}")
              quit(1)
    else:
      status("No dependencies found.")

    dimLine(SEPARATOR)

    info("Building package.")
    dimLine(SEPARATOR)

    let timeMarker = TMP / (name & "_marker")
    sleep(1000)
    discard execCmd("touch " & timeMarker)
    sleep(1000)
    let buildsh = readFile(fmt"{TMP}/{name}/build.sh")
    echo buildsh

    dimLine(SEPARATOR)

    if execCmd(fmt"cd {TMP}/{name} && sh build.sh") != 0:
        error("Build failed.")
        quit(1)

    let dirs = "/bin /sbin /usr/bin /usr/sbin /usr/include /usr/share /usr/lib /usr/lib64 /usr/local/bin /usr/local/lib /etc /lib /lib64"
    let installLog = fmt"/var/forge/world/{name}_installed"
    status("Tracking installed files...")
    discard execCmd(fmt"find {dirs} -newer {timeMarker} ! -type d 2>/dev/null > {installLog}")
    writeFile(fmt"/var/forge/world/{name}", "")
    removeFile(timeMarker)
    success(fmt"{name} has been installed succesfully.")

proc remove(name: string) =
    let tbr = readFile(fmt"/var/forge/world/{name}_installed").splitLines()
    for item in tbr:
        let path = item.strip()
        if path.len == 0: continue
        if fileExists(path) or symlinkExists(path): # changed that cuz remove script literally removed my /usr/bin
          removeFile(path)
          echo "Removed: ", path
    info("Deregestering from world set.")
    removeFile(fmt"/var/forge/world/{name}_installed")
    removeFile(fmt"/var/forge/world/{name}")
    success(fmt"{name} has been removed.")

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
  error(fmt"Unknown operation '{OP}'")
  printUsage()
  quit(1)
