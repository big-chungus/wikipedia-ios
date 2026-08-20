#!/usr/bin/env bash
#
# Cloud Agent install script for wikipedia-ios.
#
# IMPORTANT: wikipedia-ios is a native iOS app. Building, running, and running
# its XCTest unit/UI tests all require Xcode + the iOS Simulator, which only
# exist on macOS (CI uses the `macos-26` runner with Xcode 26.5). Cloud Agent
# VMs run Linux, so the app itself cannot be built, run, or unit-tested here.
#
# This script provisions the subset of the project's tooling that genuinely
# runs on Linux, so an agent can lint and statically analyze changes before
# they reach macOS CI:
#   - SwiftLint     Swift lint (see .swiftlint.yml)
#   - clang-format  Objective-C lint (see .clang-format; used by scripts/* and
#                   the scripts/clang_format_git_diff pre-commit hook)
#   - Ruby          runtime for the repo's Ruby helper scripts, including the
#                   clang-format wrapper scripts and the pre-commit hook
#
# Not installed here: the fastlane bundle (Gemfile). fastlane's lanes drive
# Xcode builds/TestFlight uploads that only work on macOS, and its lockfile
# pins Ruby < 3.2 (CFPropertyList 3.0.9), which is not available on this Ubuntu
# image. Do fastlane work on macOS.
#
# The script is idempotent and non-interactive: re-running it is safe and each
# already-satisfied step is a fast no-op.

set -euo pipefail

SWIFTLINT_VERSION="0.65.0"
SWIFTLINT_SHA256="1407d5240eafceccc2003e46fb68bf786e60373687d379889360c1f3a8823f4a"

log() { printf '\n=== %s ===\n' "$1"; }

log "System packages (clang-format, ruby, build tools)"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
  clang-format ruby ruby-dev build-essential unzip ca-certificates curl

log "SwiftLint ${SWIFTLINT_VERSION} (self-contained static Linux binary)"
# SourceKit is unavailable on Linux, so SwiftLint runs its SwiftSyntax-based
# rules and skips SourceKit-only rules. That still covers most of .swiftlint.yml
# and is enough for a pre-CI lint pass.
if [ "$(swiftlint version 2>/dev/null || true)" != "${SWIFTLINT_VERSION}" ]; then
  tmp="$(mktemp -d)"
  curl -fsSL --retry 4 --retry-delay 4 -o "${tmp}/swiftlint.zip" \
    "https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/swiftlint_linux_amd64.zip"
  unzip -o "${tmp}/swiftlint.zip" -d "${tmp}" >/dev/null
  echo "${SWIFTLINT_SHA256}  ${tmp}/swiftlint-static" | sha256sum -c -
  sudo install -m 0755 "${tmp}/swiftlint-static" /usr/local/bin/swiftlint
  rm -rf "${tmp}"
fi

log "Tooling ready"
swiftlint version
clang-format --version
ruby --version
