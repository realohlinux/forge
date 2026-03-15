import os, osproc, strformat, httpclient, strutils, posix, re
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

    let timeMarker = fmt"{TMP}/{name}_marker"
    writeFile(timeMarker, "")

    let buildsh = readFile(fmt"{TMP}/{name}/build.sh")
    echo buildsh

    echo SEPARATOR

    if execCmd(fmt"cd {TMP}/{name} && sh build.sh") != 0:
        echo "Error: Build failed."
        quit(1)

    echo SEPARATOR
    echo "Done, registering into the world set."
    writeFile(fmt"/var/forge/world/{name}", "")
    echo fmt"{name} has been installed successfully."

proc remove(name: string) =
    let tbr = readFile(fmt"/var/forge/world/{name}_installed").splitLines()
    for item in tbr:
        if dirExists(item):
          removeDir(item)
        elif fileExists(item):
          removeFile(item)
    echo "Deregestering from world set."
    removeFile(fmt"/var/forge/world/{name}_installed")
    removeFile(fmt"/var/forge/world/{name}")


if OP == "install":
  for pkg in PKGS:
    install(pkg)
elif OP == "remove":
  for pkg in PKGS:
    remove(pkg)
else:
    echo fmt"Error: Unknown operation '{OP}'"
