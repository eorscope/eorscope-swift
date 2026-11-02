#!/bin/sh
# Copies the CC BY 4.0 dataset export (https://eorscope.com/data/) into the
# package resources, byte for byte. Then: swift test
set -eu
here=$(cd "$(dirname "$0")" && pwd)
src=${1:?usage: sync.sh <dataset export dir>}
for f in country_summary.csv country_contributions.csv country_assumptions.csv LICENSE; do
	cp "$src/$f" "$here/Sources/EORScopeEmployerCosts/data/$f"
done
echo "synced from $src"
