version       = "1.0.0"
author        = "okthela"
description   = "the package manager for ohlinux (fr this time)"
license       = "BSD-3-Clause"
srcDir        = "src"
bin           = @["forge"]

requires "nim >= 2.0.8"
requires "zippy >= 0.10.19"

import std/strformat

task release, "Build release binary":
    for b in bin:
        selfExec &"c -d:release -d:strip -o:{b} {srcDir}/{b}.nim"
