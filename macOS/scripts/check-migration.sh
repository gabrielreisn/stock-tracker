#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
swiftc Sources/StockBar/LegacyMigration.swift Tests/LegacyMigrationTests.swift -o "$test_dir/check-migration"
"$test_dir/check-migration"
