import os, osproc, strformat, httpclient, strutils, posix

const
  TMP = "/tmp/hypernova"
  SEPARATOR = "----------------------------------------"

if paramCount() == 0:
    echo """Usage: forge <operation> <package>
    Operations:
        install - Install a package
    """
    quit(1)

elif paramCount() == 1:
    echo "Error: Missing package name"
    quit(1)

elif paramCount() > 2:
    echo "Error: Too many arguments"
    quit(1)

let PARAMS = commandLineParams()
let REPO = readFile("/var/hypernova/repo").strip()
let OP = PARAMS[1]
let PKGS = PARAMS[2..^1]

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
