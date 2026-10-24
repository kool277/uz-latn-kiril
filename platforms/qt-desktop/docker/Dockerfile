# Build and test environment for platforms/qt-desktop: Debian trixie ships Qt 6.8 LTS.
#   docker build -t uztranslit-qt platforms/qt-desktop/docker
#   docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/repo -w /repo/platforms/qt-desktop uztranslit-qt \
#     sh -c 'cmake -S . -B build -G Ninja && cmake --build build -j4 && ctest --test-dir build --output-on-failure'
FROM debian:trixie
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates cmake ninja-build g++ make file \
      qt6-base-dev qt6-base-dev-tools qt6-tools-dev qt6-tools-dev-tools qt6-l10n-tools qt6-qpa-plugins \
      qt6-translations-l10n libgl-dev fontconfig fonts-dejavu-core xauth xvfb \
    && rm -rf /var/lib/apt/lists/*
ENV QT_QPA_PLATFORM=offscreen LANG=C.UTF-8
