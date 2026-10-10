#!/usr/bin/env bash

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/abbrex"
mkdir -p "$cache_dir"
if [[ $? -ne 0 ]]; then
    printf '%s\n' "Error: Failed to create cache directory ${cache_dir}" >&2
    exit 1
fi

if [[ ! -d "Sources/AbbreviationExpander" || ! -d "Tests/AbbreviationExpanderTests" ]]; then
    printf '%s\n' "Error: Source or test directory not found" >&2
    exit 1
fi

sdk_file="${cache_dir}/sdk_path.tmp"
xcrun --show-sdk-path >"$sdk_file" 2>/dev/null
if [[ $? -ne 0 || ! -s "$sdk_file" ]]; then
    rm -f "$sdk_file"
    printf '%s\n' "Error: Failed to locate macOS SDK via xcrun" >&2
    exit 1
fi

IFS= read -r sdk_path <"$sdk_file"
rm -f "$sdk_file"

test_dir="${XDG_RUNTIME_DIR:-/tmp}"
test_bin="${test_dir}/RunSwiftTests"

printf '%s\n' "Executing Swift unit tests..."

swiftc -sdk "$sdk_path" \
    Sources/AbbreviationExpander/Core/*.swift \
    Sources/AbbreviationExpander/Services/*.swift \
    Sources/AbbreviationExpander/UI/*.swift \
    Sources/AbbreviationExpander/AppDelegate.swift \
    Tests/AbbreviationExpanderTests/*.swift \
    -o "$test_bin"
if [[ $? -ne 0 ]]; then
    printf '%s\n' "Error: Swift test compilation failed" >&2
    exit 1
fi

"$test_bin"
test_status=$?
rm -f "$test_bin"

if [[ "$test_status" -ne 0 ]]; then
    printf '%s\n' "Error: Swift unit tests failed" >&2
    exit "$test_status"
fi
