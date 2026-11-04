#! /usr/bin/bash
set -e

# GCC's constant-merging optimization corrupts embedded/inlined XML tag
# strings baked into DD4hep's compact-detector-description machinery.
# conda-forge only discovered this 2026-06-10 (see recipe/patches).
# GCC only (as conda-forge does): clang warns it is unsupported, and CMake's
# flag probes then fail on that warning.
if [[ "$(uname)" != "Darwin" ]]; then
  export CFLAGS="${CFLAGS} -fno-merge-constants"
  export CXXFLAGS="${CXXFLAGS} -fno-merge-constants"
fi

mkdir -p build
cd build

# macOS: look in the conda prefix before the SDK, or Geant4Config's
# find_dependency(EXPAT) reads the SDK's expat.h (2.2.5 < 2.9.0).
EXTRA_ARGS=()
if [[ "$(uname)" == "Darwin" ]]; then
  EXTRA_ARGS+=(-DCMAKE_PREFIX_PATH="${PREFIX}" -DCMAKE_FIND_FRAMEWORK=LAST)
  # conda's CMAKE_ARGS carry the macOS SDK and toolchain settings; without
  # them CMake's flag probes fail ("does not support -ftls-model=global-dynamic").
  # conda-forge's dd4hep on osx-arm64 builds with them, and with the define
  # below (libc++ otherwise rejects std::from_chars for older deployment targets).
  read -r -a CONDA_CMAKE_ARGS <<< "${CMAKE_ARGS}"
  EXTRA_ARGS+=("${CONDA_CMAKE_ARGS[@]}")
  export CXXFLAGS="${CXXFLAGS} -D_LIBCPP_DISABLE_AVAILABILITY"
  # ROOT's interpreter (rootcling, and ROOT inside listcomponents) asks a C++
  # compiler for the system include paths. Without CLING_CXX_PATH it found
  # Xcode's c++ and the SDK's older libc++ ("__configuration/abi.h not
  # found" against ROOT's std_darwin.modulemap): use conda's, which matches
  # the libc++ ROOT was built with.
  export CLING_CXX_PATH="${CXX}"
  # DDPython's plugins take Python's symbols from the loading process, and
  # listcomponents (which writes each plugin's .components file) is not
  # Python: preload libpython there, as conda-forge does through DD4hep
  # v01-38's DD4HEP_GENERATE_ROOTMAP_EXTRA_ENV. Backported to 1.37's
  # dd4hep_generate_rootmap; the installed DD4hep.cmake carries it to
  # dd4hep's consumers.
  sed -i.bak "s|^\( *\)\"ROOT_LIBRARY_PATH=\${DD4HEP_ROOT_LIBRARY_PATH}\"\$|&\n\1\"DYLD_INSERT_LIBRARIES=${PREFIX}/lib/libpython${PY_VER}.dylib\"|" ../cmake/DD4hep.cmake
  grep -q "DYLD_INSERT_LIBRARIES=${PREFIX}/lib/libpython${PY_VER}.dylib" ../cmake/DD4hep.cmake
  # DD4hep's build passes conda's LDFLAGS twice, so every link has the
  # $PREFIX/lib rpath twice. Apple's ld then warns "duplicate -rpath", and
  # CMake's check_cxx_compiler_flag counts any such warning as a failed
  # probe: every flag "unsupported", -ftls-model=global-dynamic fatally.
  # Give the rpath to CMake instead, once: for the installed files and for
  # the build-tree tools the build runs (listcomponents needs libc++ there).
  export LDFLAGS="${LDFLAGS//-Wl,-rpath,${PREFIX}\/lib/}"
  EXTRA_ARGS+=(-DCMAKE_INSTALL_RPATH="${PREFIX}/lib" -DCMAKE_BUILD_RPATH="${PREFIX}/lib")
fi

cmake .. "${EXTRA_ARGS[@]}" \
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
  -DPython_FIND_STRATEGY=LOCATION || {
  # every CMake probe failed on macOS without saying why: show the reason
  if [[ "$(uname)" == "Darwin" ]]; then
    grep -B2 -A40 -m3 'CXX_FLAG_WORKS__Wshadow' CMakeFiles/CMakeConfigureLog.yaml | tail -120 || true
  fi
  exit 1
}

NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu)
make -j"$NPROC"
make install
