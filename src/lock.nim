# SPDX-License-Identifier: BSD-3-Clause
# Copyright (C) 2025-2026 Cobalt, Flummiy
import std/[os, times]
import "console", "handler"


when not defined(debug):
    {.push optimization:speed, checks:off, warnings:off.}


proc acquireLock(lockPath: string) =
  createDir(parentDir(lockPath))
  if fileExists(lockPath):
    let age = getTime() - getLastModificationTime(lockPath)
    if age.inHours < 1:
      consoleFail("Another forge process is running (lockfile exists).")
      consoleWarn("If this is stale, remove " & lockPath)
      programExit("Forge already running")
    else:
      consoleWarn("Removing stale lockfile.")
      removeFile(lockPath)
  writeFile(lockPath, $getCurrentProcessId())

proc releaseLock(lockPath: string) =
  if fileExists(lockPath):
    removeFile(lockPath)

template withLock*(lockPath: string; body: untyped) =
  acquireLock(lockPath)
  try:
    body
  finally:
    releaseLock(lockPath)
