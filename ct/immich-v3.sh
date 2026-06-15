#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Gabriel Baker (gbaker403)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://immich.app

APP="Immich-v3"
var_tags="${var_tags:-photos;immich;rc}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

# Pinned Immich release tag. Immich v3 is currently pre-release; bump this
# (and re-run the update) once a newer rc or the final v3.0.0 is out.
IMMICH_TAG="v3.0.0-rc.0"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/immich-v3 ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  INSTALL_DIR="/opt/immich-v3"
  SRC_DIR="${INSTALL_DIR}/source"
  APP_DIR="${INSTALL_DIR}/app"
  ML_DIR="${APP_DIR}/machine-learning"
  GEO_DIR="${INSTALL_DIR}/geodata"
  UPLOAD_DIR="${INSTALL_DIR}/upload"
  STAGING_DIR=/opt/staging
  BASE_DIR="${STAGING_DIR}/base-images"
  SOURCE_DIR="${STAGING_DIR}/image-source"

  if [[ -f ~/.immich-v3_library_revisions ]]; then
    cd "$BASE_DIR"
    $STD git pull
    cd "$STAGING_DIR"
    rm -rf "$SOURCE_DIR"
    mkdir -p "$SOURCE_DIR"

    for library in libjxl libheif libraw imagemagick libvips; do
      new_rev=$(jq -cr '.revision' "$BASE_DIR"/server/sources/"$library".json)
      old_rev=$(awk -F': ' -v l="$library" '$1==l {print $2}' ~/.immich-v3_library_revisions)
      [[ "$new_rev" == "$old_rev" ]] && continue

      msg_info "Recompiling $library"
      SOURCE="${SOURCE_DIR}/${library}"
      case "$library" in
      libjxl)
        JPEGLI_LIBJPEG_LIBRARY_SOVERSION="62"
        JPEGLI_LIBJPEG_LIBRARY_VERSION="62.3.0"
        $STD git clone https://github.com/libjxl/libjxl.git "$SOURCE"
        cd "$SOURCE"
        $STD git reset --hard "$new_rev"
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
        ;;
      libheif)
        $STD git clone https://github.com/strukturag/libheif.git "$SOURCE"
        cd "$SOURCE"
        $STD git reset --hard "$new_rev"
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
        ;;
      libraw)
        $STD git clone https://github.com/libraw/libraw.git "$SOURCE"
        cd "$SOURCE"
        $STD git reset --hard "$new_rev"
        $STD autoreconf --install
        $STD ./configure
        $STD make -j"$(nproc)"
        $STD make install
        ldconfig /usr/local/lib
        $STD make clean
        cd "$STAGING_DIR"
        ;;
      imagemagick)
        $STD git clone https://github.com/ImageMagick/ImageMagick.git "$SOURCE"
        cd "$SOURCE"
        $STD git reset --hard "$new_rev"
        $STD ./configure --with-modules
        $STD make -j"$(nproc)"
        $STD make install
        ldconfig /usr/local/lib
        $STD make clean
        cd "$STAGING_DIR"
        ;;
      libvips)
        $STD git clone https://github.com/libvips/libvips.git "$SOURCE"
        cd "$SOURCE"
        $STD git reset --hard "$new_rev"
        $STD meson setup build --buildtype=release --libdir=lib -Dintrospection=disabled -Dtiff=disabled
        cd build
        $STD ninja install
        ldconfig /usr/local/lib
        cd "$STAGING_DIR"
        rm -rf "$SOURCE"/build
        ;;
      esac
      msg_ok "Recompiled $library"
    done

    {
      for library in libjxl libheif libraw imagemagick libvips; do
        echo "$library: $(jq -cr '.revision' "$BASE_DIR"/server/sources/"$library".json)"
      done
    } >~/.immich-v3_library_revisions
  fi

  if check_for_gh_release "immich-v3" "immich-app/immich" "$IMMICH_TAG"; then
    msg_info "Stopping Services"
    systemctl stop immich-v3 immich-v3-ml
    msg_ok "Stopped Services"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "immich-v3" "immich-app/immich" "tarball" "$IMMICH_TAG" "$SRC_DIR"
    mkdir -p "${INSTALL_DIR}/www"

    msg_info "Rebuilding Immich Server"
    cd "$SRC_DIR"
    export CI=1 COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    rm -rf "$APP_DIR"/{bin,dist,helmet.json,node_modules,LICENSE}
    SHARP_IGNORE_GLOBAL_LIBVIPS=true $STD pnpm --filter @immich/sdk --filter @immich/plugin-sdk --filter immich build
    SHARP_FORCE_GLOBAL_LIBVIPS=true $STD pnpm --filter immich --prod --no-optional deploy "$APP_DIR"
    chmod +x "$APP_DIR"/bin/*.sh
    cp LICENSE "$APP_DIR"
    msg_ok "Rebuilt Immich Server"

    msg_info "Rebuilding Immich Web"
    cd "$SRC_DIR"
    SHARP_IGNORE_GLOBAL_LIBVIPS=true $STD pnpm --filter @immich/sdk --filter immich-web install --frozen-lockfile --force
    $STD pnpm --filter @immich/sdk --filter immich-web build
    rm -rf "${INSTALL_DIR}/www"
    cp -r "$SRC_DIR"/web/build "${INSTALL_DIR}/www"
    msg_ok "Rebuilt Immich Web"

    msg_info "Rebuilding Machine Learning"
    rm -rf "$ML_DIR"/ml-venv
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
    rm -rf "$ML_DIR"/{ann,immich_ml}
    cp -a machine-learning/{ann,immich_ml} "$ML_DIR"
    if [[ -f ~/.openvino ]]; then
      sed -i "/intra_op/s/int = 0/int = os.cpu_count() or 0/" "$ML_DIR"/immich_ml/config.py
      for so in "$ML_DIR"/ml-venv/lib/python3.*/site-packages/onnxruntime/capi/onnxruntime_pybind11_state*.so; do
        [[ -f "$so" ]] && patchelf --clear-execstack "$so"
      done

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
    fi
    msg_ok "Rebuilt Machine Learning"

    sed -i "s@\"/cache\"@\"$INSTALL_DIR/cache\"@g" "$ML_DIR"/immich_ml/config.py
    ln -sf "$UPLOAD_DIR" "$APP_DIR"/upload
    ln -sf "$UPLOAD_DIR" "$ML_DIR"/upload

    msg_info "Rebuilding Immich CLI"
    cd "$SRC_DIR"
    $STD pnpm --filter @immich/sdk --filter @immich/cli install --frozen-lockfile
    $STD pnpm --filter @immich/sdk --filter @immich/cli build
    rm -rf "${INSTALL_DIR}/cli"
    $STD pnpm --filter @immich/cli --prod --no-optional deploy "${INSTALL_DIR}/cli"
    ln -sf "${INSTALL_DIR}/cli/bin/immich" "$APP_DIR/bin/immich"
    msg_ok "Rebuilt Immich CLI"

    msg_info "Starting Services"
    systemctl start immich-v3-ml immich-v3
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} This is Immich v3.0.0-rc.0, a pre-release. Run it alongside, not instead of, your v2 instance.${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:2283${CL}"
