version       = "1.0.1"
author        = "okthela"
description   = "the package manager for ohlinux (fr this time)"
license       = "BSD-3-Clause"
srcDir        = "src"
bin           = @["main"]
namedBin["main"] = "forge"

requires "nim >= 2.0.8"
requires "zippy >= 0.10.19"
requires "regex >= 0.26.3"
requires "parsetoml >= 0.7.0"
requires "nimcrypto >= 0.5.4"

import std/strformat

task release, "Build release binary":
    selfExec &"c -d:release -d:strip -d:ssl -o:forge {srcDir}/main.nim"
