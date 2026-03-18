# SPDX-License-Identifier: BSD-3-Clause
# Copyright (C) 2025-2026 Taylor (Wakana Kisarazu), Kaden (flummiy)
import std/[os, strutils]
import parsetoml
import nimcrypto/sha2
import nimcrypto/hash


when not defined(debug):
    {.push optimization:speed, checks:off, warnings:off.}


## Follows structure given by the markdown file
type
  Manifest* = object
    name*:        string
    version*:     string
    description*: string
    homepage*:    string
    source*:      string
    sha256*:      string
    buildDeps*:   seq[string]
    runtimeDeps*: seq[string]


proc parseManifest*(path: string): Manifest =
    let t = parsetoml.parseFile(path)
    let pkg = t["package"]
    result.name        = pkg["name"].getStr()
    result.version     = pkg["version"].getStr()
    result.description = pkg["description"].getStr()
    result.homepage    = pkg["homepage"].getStr()
    result.source      = pkg["source"].getStr()
    result.sha256      = pkg["sha256"].getStr()
    if t.hasKey("dependencies"):
        let deps = t["dependencies"]
        if deps.hasKey("build"):
            for item in deps["build"].getElems():
                result.buildDeps.add(item.getStr())
        if deps.hasKey("runtime"):
            for item in deps["runtime"].getElems():
                result.runtimeDeps.add(item.getStr())


proc verifySha256*(filePath: string, expected: string): bool =
    var ctx: sha256
    ctx.init()
    let f = open(filePath, fmRead)
    defer: f.close()
    var buf: array[65536, byte]
    while true:
        let n = f.readBytes(buf, 0, buf.len)
        if n == 0: break
        ctx.update(buf.toOpenArray(0, n - 1))
    let actual = ($ctx.finish()).toLowerAscii()
    result = actual == expected.toLowerAscii()
