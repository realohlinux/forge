import os, osproc, strformat, httpclient, strutils, posix

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

let REPO = readFile("/var/hypernova/repo").strip()
let TMP = "/tmp/hypernova"
let OP = paramStr(1)
let PKG = paramStr(2)
let URL = fmt"{REPO}/{PKG}.tar.gz"
let SEPARATOR= "----------------------------------------"

createDir("/var/forge/world")
discard execProcess(fmt"mkdir -p {TMP}/{PKG}")

proc install() =
    echo "Downloading source."
    echo fmt"Connecting to {REPO}..."

    let workdir = TMP / PKG
    createDir(workdir)
    let pkgsrc = workdir / (PKG & ".tar.gz")
    let client = newHttpClient()
    client.downloadFile(URL, pkgsrc)
    echo fmt"Successfully downloaded {PKG} from {REPO}"
    
    echo SEPARATOR

    echo "Extracting source.\n"
 
    discard execCmd(fmt"tar -xzvf {pkgsrc} -C {TMP}/{PKG}")
    echo "Source extracted."  

    if fileExists(fmt"{TMP}/{PKG}/depends"):
        for dep in readFile(fmt"{TMP}/{PKG}/depends").splitLines():
            let i = dep.strip()

            if i.len == 0:
                continue

            if fileExists(fmt"/var/forge/world/{i}"):
                echo fmt"Dependency {i} is already installed, skipping."
                continue
            echo fmt"Installing dependency: {i}"
            sleep(1000)
            if execCmd(fmt"forge install {i}") != 0:
                echo fmt"Error: Failed to install dependency {i}."
                quit(1)
    else:
        echo "No dependencies found."

    echo SEPARATOR

    echo "Building package."
    echo SEPARATOR

    let buildsh = readFile(fmt"{TMP}/{PKG}/build.sh")
    echo buildsh

    echo SEPARATOR

    if execCmd(fmt"cd {TMP}/{PKG} && sh build.sh") != 0:
        echo "Error: Build failed."
        quit(1)

    echo SEPARATOR
    echo "Done, registering into the world set."
    writeFile(fmt"/var/forge/world/{PKG}", "")
    echo fmt"{PKG} has been installed successfully."
    
proc remove() =
    let tbr = readFile(fmt"/var/forge/world/{PKG}_installed").splitLines()
    for item in tbr:
        discard execCmd(fmt"rm -rfv {item}")
    echo "Deregestering from world set."
    discard execCmd(fmt"rm -rfv /var/forge/world/{PKG}_installed")
    discard execCmd(fmt"rm -rfv /var/forge/world/{PKG}")


if OP == "install":
    install()
elif OP == "remove":
    remove()
else:
    echo fmt"Error: Unknown operation '{OP}'"

