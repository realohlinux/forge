import os, osproc, strformat, httpclient, strutils, posix
stdout.flushFile()

if getuid() != 0:
  stderr.writeLine("You need to be a superuser to run the forge package manager.")
  quit(1)
const
  TMP = "/tmp/hypernova"
  SEPARATOR = "----------------------------------------"

if paramCount() == 0:
    echo """Usage: forge <operation> <package>
    Operations:
        install - Install a package
        remove - Remove a package
    """
    quit(1)

elif paramCount() == 1:
    echo "Error: Missing package name"
    quit(1)

let PARAMS = commandLineParams()
let REPO = readFile("/var/hypernova/repo").strip()
let OP = PARAMS[0]
let PKGS = PARAMS[1..^1]

createDir("/var/forge/world")

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


if OP == "install":
  for pkg in PKGS:
    install(pkg)
elif OP == "remove":
  for pkg in PKGS:
    remove(pkg)
else:
    echo fmt"Error: Unknown operation '{OP}'"
