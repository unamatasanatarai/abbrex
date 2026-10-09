#!/bin/bash
set -e

echo "==> Executing Swift unit tests..."
SDK_PATH=$(xcrun --show-sdk-path)

swiftc -sdk "$SDK_PATH" \
    Sources/AbbreviationExpander/Core/*.swift \
    Tests/AbbreviationExpanderTests/TestMain.swift \
    -o /tmp/RunSwiftTests

/tmp/RunSwiftTests
rm -f /tmp/RunSwiftTests
