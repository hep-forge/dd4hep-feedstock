#! /usr/bin/bash
set -e

# GCC's constant-merging optimization corrupts embedded/inlined XML tag
# strings baked into DD4hep's compact-detector-description machinery.
# conda-forge only discovered this 2026-06-10 (see recipe/patches).
export CFLAGS="${CFLAGS} -fno-merge-constants"
export CXXFLAGS="${CXXFLAGS} -fno-merge-constants"

mkdir -p build
cd build

cmake .. \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON \
  -DBUILD_TESTING=OFF \
  -DDD4HEP_USE_GEANT4=ON \
  -DDD4HEP_USE_XERCESC=ON \
  -DDD4HEP_USE_EDM4HEP=ON \
  -DDD4HEP_USE_HEPMC3=ON \
  -DDD4HEP_USE_G4HEPEM=ON \
  -DDD4HEP_BUILD_EXAMPLES=OFF \
  -DDD4HEP_RELAX_PYVER=ON \
  -DPython_EXECUTABLE="${PREFIX}/bin/python" \
  -DPython_ROOT_DIR="${PREFIX}" \
  -DPython_FIND_STRATEGY=LOCATION

NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu)
make -j"$NPROC"
make install
