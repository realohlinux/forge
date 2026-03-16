# SPDX-License-Identifier: BSD-3-Clause
# Copyright (C) 2025-2026 Taylor (Wakana Kisarazu)
import std/[posix, os, strformat]
import "console"


when not defined(debug):
    {.push optimization:speed, checks:off, warnings:off.}


proc programExit*[T](msg: T = "", code: int = QuitFailure) = 
    var m = msg

    when T is string:
        m = msg
    else:
        m = $msg
    
    consoleDebug(fmt("Calling: programExit({m}, {code})"))

    stdout.flushFile()
    stderr.flushFile()

    quit(m, code)


proc checkCanExecute*(): bool =
     if getuid() != 0: return false
     if paramCount() == 0: return false    

     return true         


template printUsage*() =
    echo """Usage: forge <operation> <package>

    Operations:
        install - Install a package
        remove - Remove a package

    Package: *path/to/file*"""
    stdout.flushFile()
    stderr.flushFile()
