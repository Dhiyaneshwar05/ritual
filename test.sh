#!/bin/zsh
set -e; cd "${0:A:h}"
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
mkdir -p build
swiftc -sdk $SDK -target arm64-apple-macos15.0 -swift-version 5 Shared/Model.swift Shared/Tasks.swift Tests/main.swift -o build/tests
build/tests
