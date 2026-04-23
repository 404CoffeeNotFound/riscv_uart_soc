#!/bin/bash
# Clone PicoRV32 into rtl/core/picorv32/
# Only the single file rtl/core/picorv32/picorv32.v is actually used by our SoC.

set -e

HERE="$(cd "$(dirname "$0")/.." && pwd)"
DST="$HERE/rtl/core/picorv32"

if [ -d "$DST/.git" ]; then
  echo "Already cloned at $DST — pulling latest"
  git -C "$DST" pull --ff-only
else
  echo "Cloning PicoRV32 into $DST"
  git clone --depth 1 https://github.com/YosysHQ/picorv32.git "$DST"
fi

echo ""
echo "Verifying picorv32.v exists:"
ls -la "$DST/picorv32.v"
echo ""
echo "Done. Add \$HERE/rtl/core/picorv32/picorv32.v to your Vivado / Verilator sources."
