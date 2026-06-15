#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Gabriel Baker (gbaker403)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://immich.app

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

IMMICH_TAG="v3.0.0-rc.0"
INSTALL_DIR="/opt/immich-v3"
SRC_DIR="${INSTALL_DIR}/source"
APP_DIR="${INSTALL_DIR}/app"
ML_DIR="${APP_DIR}/machine-learning"
GEO_DIR="${INSTALL_DIR}/geodata"
UPLOAD_DIR="${INSTALL_DIR}/upload"

msg_info "Installing Dependencies"
$STD apt install -y \
  autoconf \
  build-essential \
  cmake \
  cpanminus \
  ffmpeg \
  git \
  libbrotli-dev \
  libdav1d-dev \
  libde265-0 \
  libde265-dev \
  libexif-dev \
  libexif12 \
  libexpat1-dev \
  libgdk-pixbuf-2.0-dev \
  libgif-dev \
  libglib2.0-0 \
  libglib2.0-dev \
  libgomp1 \
  libgsf-1-114 \
  libgsf-1-dev \
  libhwy-dev \
  libhwy1 \
  libio-compress-brotli-perl \
  libjpeg62-turbo-dev \
  liblcms2-dev \
  liblqr-1-0 \
  libltdl7 \
  libmimalloc3 \
  libopenexr-dev \
  libopenjp2-7 \
  librsvg2-2 \
  librsvg2-dev \
  libspng-dev \
  libspng0 \
  libtool \
  libwebp-dev \
  libwebp7 \
  libwebpdemux2 \
  libwebpmux3 \
  mesa-utils \
  mesa-va-drivers \
  mesa-vulkan-drivers \
  meson \
  ninja-build \
  ocl-icd-libopencl1 \
  pkg-config \
  python3-dev \
  redis-server \
  tini \
  unzip \
  zlib1g
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs
PG_VERSION="16" PG_MODULES="pgvector,contrib" setup_postgresql
setup_uv

if [[ -d /dev/dri ]]; then
  read -r -t 60 -p "${TAB3}Enable Intel OpenVINO acceleration for machine learning? [y/N] (auto-no in 60s): " prompt || prompt=""
  [[ "${prompt,,}" =~ ^(y|yes)$ ]] && touch ~/.openvino
fi

if [[ -f ~/.openvino ]]; then
  msg_info "Installing Intel Level Zero GPU drivers"
  $STD apt install -y level-zero patchelf

  # intel-opencl-icd is intentionally NOT installed: its OpenCL ICD breaks
  # onnxruntime's OpenVINO device enumeration (immich-app/immich#23450, #25830).
  # intel-level-zero-gpu isn't packaged for Trixie, so fetch it (and its
  # gmmlib dependency) from compute-runtime GitHub releases, same as
  # setup_hwaccel's Intel Arc/Gen9+ paths do.
  fetch_and_deploy_gh_release "libigdgmm12" "intel/compute-runtime" "binary" "latest" "" "libigdgmm12_*_amd64.deb" || true
  fetch_and_deploy_gh_release "intel-level-zero-gpu" "intel/compute-runtime" "binary" "latest" "" "libze-intel-gpu1_*_amd64.deb" || true
  msg_ok "Installed Intel Level Zero GPU drivers"
fi

PG_DB_NAME="immich" PG_DB_USER="immich" PG_DB_EXTENSIONS="pgvector,cube,earthdistance" PG_DB_GRANT_SUPERUSER="true" setup_postgresql_db

msg_info "Compiling image-processing libraries (this takes a while)"
STAGING_DIR=/opt/staging
BASE_REPO="https://github.com/immich-app/base-images"
BASE_DIR="${STAGING_DIR}/base-images"
SOURCE_DIR="${STAGING_DIR}/image-source"
$STD git clone -b main "$BASE_REPO" "$BASE_DIR"
mkdir -p "$SOURCE_DIR"
cd "$STAGING_DIR"

SOURCE="${SOURCE_DIR}/libjxl"
JPEGLI_LIBJPEG_LIBRARY_SOVERSION="62"
JPEGLI_LIBJPEG_LIBRARY_VERSION="62.3.0"
LIBJXL_REVISION=$(jq -cr '.revision' "$BASE_DIR"/server/sources/libjxl.json)
$STD git clone https://github.com/libjxl/libjxl.git "$SOURCE"
cd "$SOURCE"
$STD git reset --hard "$LIBJXL_REVISION"
$STD git submodule update --init --recursive --depth 1 --recommend-shallow
$STD git apply "$BASE_DIR"/server/sources/libjxl-patches/jpegli-empty-dht-marker.patch
$STD git apply "$BASE_DIR"/server/sources/libjxl-patches/jpegli-icc-warning.patch
mkdir build
cd build
$STD cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTING=OFF \
  -DJPEGXL_ENABLE_DOXYGEN=OFF \
  -DJPEGXL_ENABLE_MANPAGES=OFF \
  -DJPEGXL_ENABLE_PLUGIN_GIMP210=OFF \
  -DJPEGXL_ENABLE_BENCHMARK=OFF \
  -DJPEGXL_ENABLE_EXAMPLES=OFF \
  -DJPEGXL_FORCE_SYSTEM_BROTLI=ON \
  -DJPEGXL_FORCE_SYSTEM_HWY=ON \
  -DJPEGXL_ENABLE_JPEGLI=ON \
  -DJPEGXL_ENABLE_JPEGLI_LIBJPEG=ON \
  -DJPEGXL_INSTALL_JPEGLI_LIBJPEG=ON \
  -DJPEGXL_ENABLE_PLUGINS=ON \
  -DJPEGLI_LIBJPEG_LIBRARY_SOVERSION="$JPEGLI_LIBJPEG_LIBRARY_SOVERSION" \
  -DJPEGLI_LIBJPEG_LIBRARY_VERSION="$JPEGLI_LIBJPEG_LIBRARY_VERSION" \
  -DLIBJPEG_TURBO_VERSION_NUMBER=2001005 \
  ..
$STD cmake --build . -- -j"$(nproc)"
$STD cmake --install .
ldconfig /usr/local/lib
$STD make clean
cd "$STAGING_DIR"
rm -rf "$SOURCE"/{build,third_party}

SOURCE="${SOURCE_DIR}/libheif"
LIBHEIF_REVISION=$(jq -cr '.revision' "$BASE_DIR"/server/sources/libheif.json)
$STD git clone https://github.com/strukturag/libheif.git "$SOURCE"
cd "$SOURCE"
$STD git reset --hard "$LIBHEIF_REVISION"
mkdir build
cd build
$STD cmake --preset=release-noplugins \
  -DWITH_DAV1D=ON \
  -DENABLE_PARALLEL_TILE_DECODING=ON \
  -DWITH_LIBSHARPYUV=ON \
  -DWITH_LIBDE265=ON \
  -DWITH_AOM_DECODER=OFF \
  -DWITH_AOM_ENCODER=OFF \
  -DWITH_X265=OFF \
  -DWITH_EXAMPLES=OFF \
  ..
$STD make install -j"$(nproc)"
ldconfig /usr/local/lib
$STD make clean
cd "$STAGING_DIR"
rm -rf "$SOURCE"/build

SOURCE="${SOURCE_DIR}/libraw"
LIBRAW_REVISION=$(jq -cr '.revision' "$BASE_DIR"/server/sources/libraw.json)
$STD git clone https://github.com/libraw/libraw.git "$SOURCE"
cd "$SOURCE"
$STD git reset --hard "$LIBRAW_REVISION"
$STD autoreconf --install
$STD ./configure
$STD make -j"$(nproc)"
$STD make install
ldconfig /usr/local/lib
$STD make clean
cd "$STAGING_DIR"

SOURCE="${SOURCE_DIR}/imagemagick"
IMAGEMAGICK_REVISION=$(jq -cr '.revision' "$BASE_DIR"/server/sources/imagemagick.json)
$STD git clone https://github.com/ImageMagick/ImageMagick.git "$SOURCE"
cd "$SOURCE"
$STD git reset --hard "$IMAGEMAGICK_REVISION"
$STD ./configure --with-modules
$STD make -j"$(nproc)"
$STD make install
ldconfig /usr/local/lib
$STD make clean
cd "$STAGING_DIR"

SOURCE="${SOURCE_DIR}/libvips"
LIBVIPS_REVISION=$(jq -cr '.revision' "$BASE_DIR"/server/sources/libvips.json)
$STD git clone https://github.com/libvips/libvips.git "$SOURCE"
cd "$SOURCE"
$STD git reset --hard "$LIBVIPS_REVISION"
$STD meson setup build --buildtype=release --libdir=lib -Dintrospection=disabled -Dtiff=disabled
cd build
$STD ninja install
ldconfig /usr/local/lib
cd "$STAGING_DIR"
rm -rf "$SOURCE"/build

{
  echo "imagemagick: $IMAGEMAGICK_REVISION"
  echo "libheif: $LIBHEIF_REVISION"
  echo "libjxl: $LIBJXL_REVISION"
  echo "libraw: $LIBRAW_REVISION"
  echo "libvips: $LIBVIPS_REVISION"
} >~/.immich-v3_library_revisions
msg_ok "Compiled image-processing libraries"

fetch_and_deploy_gh_release "immich-v3" "immich-app/immich" "tarball" "$IMMICH_TAG" "$SRC_DIR"
mkdir -p "$APP_DIR" "$UPLOAD_DIR" "$GEO_DIR" "$ML_DIR" "${INSTALL_DIR}/cache"

msg_info "Building Immich Server and Web"
cd "$SRC_DIR"/server
$STD npm install -g node-gyp node-pre-gyp
$STD npm ci
$STD npm run build
$STD npm prune --omit=dev --omit=optional
cd "$SRC_DIR"/open-api/typescript-sdk
$STD npm ci
$STD npm run build
cd "$SRC_DIR"/web
$STD npm ci
$STD npm run build
cd "$SRC_DIR"
cp -a server/{node_modules,dist,bin,resources,package.json,package-lock.json,start*.sh} "$APP_DIR"/
cp -a web/build "$APP_DIR"/www
cp LICENSE "$APP_DIR"
msg_ok "Built Immich Server and Web"

msg_info "Setting up Machine Learning"
$STD uv venv --python 3.12 "$ML_DIR"/ml-venv
cd "$SRC_DIR"/machine-learning
(
  source "$ML_DIR"/ml-venv/bin/activate
  if [[ -f ~/.openvino ]]; then
    $STD uv sync --extra openvino --no-cache --active
  else
    $STD uv sync --extra cpu --no-cache --active
  fi
)
cd "$SRC_DIR"
cp -a machine-learning/{ann,immich_ml} "$ML_DIR"
if [[ -f ~/.openvino ]]; then
  sed -i "/intra_op/s/int = 0/int = os.cpu_count() or 0/" "$ML_DIR"/immich_ml/config.py
  for so in "$ML_DIR"/ml-venv/lib/python3.*/site-packages/onnxruntime/capi/onnxruntime_pybind11_state*.so; do
    [[ -f "$so" ]] && patchelf --clear-execstack "$so"
  done
fi
ln -sf "$APP_DIR"/resources "$INSTALL_DIR"
msg_ok "Set up Machine Learning"

if [[ -f ~/.openvino ]]; then
  msg_info "Patching OpenVINO execution provider"
  python3 - "$ML_DIR/immich_ml/sessions/ort.py" <<'PYEOF'
import sys

OLD_MARKER = "ort.capi._pybind_state.get_available_openvino_device_ids()"
NEW_MARKER = "enumeration bypassed"
END_MARKER = 'log.debug("OpenVINO: No GPU found, using CPU")'

NEW_BLOCK = [
    "# Patched: skip get_available_openvino_device_ids() which segfaults\n",
    "# on onnxruntime 1.24.1 + OpenVINO inside containers.\n",
    "# GPU verified working via Level Zero, so target it directly.\n",
    'device_type = f"GPU.{settings.device_id}"\n',
    'log.debug(f"OpenVINO: Using GPU device {device_type} (enumeration bypassed)")\n',
]

path = sys.argv[1]
with open(path) as f:
    content = f.read()

if NEW_MARKER in content:
    print("unchanged: already patched")
    sys.exit(0)

if OLD_MARKER not in content:
    sys.exit(
        "FAIL: expected OpenVINOExecutionProvider device enumeration "
        f"({OLD_MARKER}) not found, and patch is not already applied. "
        "Upstream ort.py has likely changed - review install/immich-v3-install.sh"
    )

lines = content.splitlines(keepends=True)
start_idx = next(i for i, line in enumerate(lines) if OLD_MARKER in line)
indent = lines[start_idx][: len(lines[start_idx]) - len(lines[start_idx].lstrip())]

try:
    end_idx = next(i for i in range(start_idx, len(lines)) if END_MARKER in lines[i])
except StopIteration:
    sys.exit(f"FAIL: found start of OpenVINO block but not end marker ({END_MARKER!r})")

new_lines = lines[:start_idx] + [indent + line for line in NEW_BLOCK] + lines[end_idx + 1:]

with open(path, "w") as f:
    f.writelines(new_lines)

print("changed: patched OpenVINOExecutionProvider block")
PYEOF
  msg_ok "Patched OpenVINO execution provider"
fi

cd "$APP_DIR"
grep -RlZ /usr/src . | xargs -0 -r sed -i "s|/usr/src|$INSTALL_DIR|g"
grep -RlZE "'/build'" . | xargs -0 -r sed -i "s|'/build'|'$APP_DIR'|g"
sed -i "s@\"/cache\"@\"$INSTALL_DIR/cache\"@g" "$ML_DIR"/immich_ml/config.py
ln -s "$UPLOAD_DIR" "$APP_DIR"/upload
ln -s "$UPLOAD_DIR" "$ML_DIR"/upload
ln -s "$GEO_DIR" "$APP_DIR"

msg_info "Installing Immich CLI"
$STD npm install --build-from-source sharp
rm -rf "$APP_DIR"/node_modules/@img/sharp-{libvips*,linuxmusl-x64}
$STD npm install -g @immich/cli
msg_ok "Installed Immich CLI"

msg_info "Downloading GeoNames data"
cd "$GEO_DIR"
URL_LIST=(
  https://download.geonames.org/export/dump/admin1CodesASCII.txt
  https://download.geonames.org/export/dump/admin2Codes.txt
  https://download.geonames.org/export/dump/cities500.zip
  https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_0_countries.geojson
)
echo "${URL_LIST[@]}" | xargs -n1 -P4 wget -q
unzip -q cities500.zip
date --iso-8601=seconds | tr -d "\n" >geodata-date.txt
rm cities500.zip
msg_ok "Downloaded GeoNames data"

msg_info "Creating environment file and services"
cat <<EOF >"${INSTALL_DIR}"/.env
TZ=$(cat /etc/timezone)
NODE_ENV=production

DB_HOSTNAME=127.0.0.1
DB_USERNAME=${PG_DB_USER}
DB_PASSWORD=${PG_DB_PASS}
DB_DATABASE_NAME=${PG_DB_NAME}
DB_VECTOR_EXTENSION=pgvector

REDIS_HOSTNAME=127.0.0.1
IMMICH_MACHINE_LEARNING_URL=http://127.0.0.1:3003
MACHINE_LEARNING_CACHE_FOLDER=${INSTALL_DIR}/cache

IMMICH_MEDIA_LOCATION=${UPLOAD_DIR}
IMMICH_PORT=2283
EOF
if [[ -f ~/.openvino ]]; then
  echo "MACHINE_LEARNING_DEVICE_ID=0" >>"${INSTALL_DIR}"/.env
fi

cat <<EOF >"${ML_DIR}"/ml_start.sh
#!/usr/bin/env bash

cd ${ML_DIR}
. ml-venv/bin/activate

set -a
. ${INSTALL_DIR}/.env
set +a

python -m immich_ml
EOF
chmod +x "$ML_DIR"/ml_start.sh

cat <<EOF >/etc/systemd/system/immich-v3-ml.service
[Unit]
Description=Immich v3 Machine Learning
After=network.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
EnvironmentFile=${INSTALL_DIR}/.env
ExecStart=${ML_DIR}/ml_start.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/immich-v3.service
[Unit]
Description=Immich v3 Server
After=network.target
Requires=redis-server.service postgresql.service immich-v3-ml.service

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
EnvironmentFile=${INSTALL_DIR}/.env
ExecStart=/usr/bin/node ${APP_DIR}/dist/main
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now immich-v3-ml.service immich-v3.service
msg_ok "Created environment file and services"

motd_ssh
customize
cleanup_lxc
