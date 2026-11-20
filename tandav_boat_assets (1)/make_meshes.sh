#!/bin/bash
# Re-export the two meshes with the balsam of YOUR Qt version (use this if Qt says "mesh version mismatch"):
#   ./make_meshes.sh /path/to/Qt/6.x/gcc_arm64/bin/balsam
BALSAM=${1:-balsam}
cd "$(dirname "$0")/assets/meshes/src"
$BALSAM -o ../_out tandavStealth.obj
$BALSAM -o ../_out contactYacht.obj
mv ../_out/meshes/*.mesh .. && rm -rf ../_out
echo "done: assets/meshes/tandavStealth_mesh.mesh  assets/meshes/contactYacht_mesh.mesh"
