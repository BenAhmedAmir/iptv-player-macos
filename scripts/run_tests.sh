#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Compiling and running IPTV Player test suite..."

swiftc -o /tmp/iptv_test_suite \
  -framework Foundation \
  -framework Security \
  "$DIR"/IPTVPlayer/Models/*.swift \
  "$DIR"/IPTVPlayer/Services/M3UParserService.swift \
  "$DIR"/IPTVPlayer/Services/XtreamAPIService.swift \
  "$DIR"/IPTVPlayer/Services/KeychainService.swift \
  "$DIR"/IPTVPlayer/Services/PersistenceController.swift \
  "$DIR"/Tests/TestRunner.swift

/tmp/iptv_test_suite
