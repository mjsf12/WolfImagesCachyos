#!/usr/bin/env bash
set -e

source /opt/gow/bash-lib/utils.sh

# Executa os passos de inicialização somente se rodando como root
if [ "$(id -u)" = "0" ]; then

    # ---- Configura usuário ----
    gow_log "**** Configure default user ****"
    PUID="${PUID:-1000}"
    PGID="${PGID:-1000}"
    UMASK="${UMASK:-000}"

    if [[ "${UNAME}" != "root" ]]; then
        gow_log "Setting default user uid=${PUID}(${UNAME}) gid=${PGID}(${UNAME})"

        # Remove usuário existente com mesmo UID se for diferente do UNAME
        if id -u "${PUID}" &>/dev/null; then
            oldname=$(id -nu "${PUID}")
            if [ "$oldname" != "$UNAME" ]; then
                userdel -r "${oldname}" 2>/dev/null || true
            fi
        fi

        groupadd -f -g "${PGID}" "${UNAME}" 2>/dev/null || true
        if ! id "${UNAME}" &>/dev/null; then
            useradd -m -d "${HOME}" -u "${PUID}" -g "${PGID}" -s /bin/bash "${UNAME}"
        else
            usermod -u "${PUID}" -g "${PGID}" "${UNAME}" 2>/dev/null || true
        fi

        umask "${UMASK}"

        mkdir -p "${HOME}"
        chown "${PUID}:${PGID}" "${HOME}"

        # Corrige permissões de diretórios criados como root pelo Docker
        # quando bind mounts criam os parent dirs antes do entrypoint rodar
        # (ex: montar /host/.config/heroic cria /home/gow/.config/ como root)
        for d in "${HOME}/.config" "${HOME}/.local" "${HOME}/.local/share"; do
            if [ -d "$d" ] && [ "$(stat -c '%u' "$d")" != "${PUID}" ]; then
                chown "${PUID}:${PGID}" "$d"
            fi
        done

        # Garante que XDG_RUNTIME_DIR existe e pertence ao usuário
        mkdir -p "${XDG_RUNTIME_DIR}"
        chown -R "${PUID}:${PGID}" "${XDG_RUNTIME_DIR}"
        chmod 700 "${XDG_RUNTIME_DIR}"

        gow_log "DONE"
    fi

    # ---- Configura grupos dos dispositivos ----
    gow_log "**** Configure devices ****"
    /opt/gow/ensure-groups ${GOW_REQUIRED_DEVICES:-/dev/uinput /dev/input/event*}
    gow_log "DONE"

    # ---- Configura Nvidia ----
    # Caso o volume do driver nvidia esteja montado em /usr/nvidia
    if [ -d /usr/nvidia ]; then
        gow_log "Nvidia driver volume detected"
        ldconfig

        [ -d /usr/nvidia/share/vulkan/icd.d ] && {
            mkdir -p /usr/share/vulkan/icd.d/
            cp /usr/nvidia/share/vulkan/icd.d/* /usr/share/vulkan/icd.d/
        }
        [ -d /usr/nvidia/share/egl/egl_external_platform.d ] && {
            mkdir -p /usr/share/egl/egl_external_platform.d/
            cp /usr/nvidia/share/egl/egl_external_platform.d/* /usr/share/egl/egl_external_platform.d/
        }
        [ -d /usr/nvidia/share/glvnd/egl_vendor.d ] && {
            mkdir -p /usr/share/glvnd/egl_vendor.d/
            cp /usr/nvidia/share/glvnd/egl_vendor.d/* /usr/share/glvnd/egl_vendor.d/
        }
        [ -d /usr/nvidia/lib/gbm ] && {
            mkdir -p /usr/lib/gbm/
            cp /usr/nvidia/lib/gbm/* /usr/lib/gbm/
        }

    # Caso nvidia-utils já esteja instalado na imagem (Arch: /usr/lib/)
    elif [ -e /usr/lib/libnvidia-allocator.so.1 ]; then
        gow_log "Nvidia driver detected (nvidia-utils instalado)"
        ldconfig

        if [ ! -e /usr/lib/gbm/nvidia-drm_gbm.so ]; then
            gow_log "Creating symlink nvidia-drm_gbm.so"
            mkdir -p /usr/lib/gbm
            ln -sv ../libnvidia-allocator.so.1 /usr/lib/gbm/nvidia-drm_gbm.so
        fi

        if [ ! -f /usr/share/glvnd/egl_vendor.d/10_nvidia.json ]; then
            mkdir -p /usr/share/glvnd/egl_vendor.d/
            echo '{"file_format_version":"1.0.0","ICD":{"library_path":"libEGL_nvidia.so.0"}}' \
                > /usr/share/glvnd/egl_vendor.d/10_nvidia.json
        fi

        if [ ! -f /usr/share/vulkan/icd.d/nvidia_icd.json ]; then
            mkdir -p /usr/share/vulkan/icd.d/
            echo '{"file_format_version":"1.0.0","ICD":{"library_path":"libGLX_nvidia.so.0","api_version":"1.3.242"}}' \
                > /usr/share/vulkan/icd.d/nvidia_icd.json
        fi

        if [ ! -f /usr/share/egl/egl_external_platform.d/15_nvidia_gbm.json ]; then
            mkdir -p /usr/share/egl/egl_external_platform.d/
            echo '{"file_format_version":"1.0.0","ICD":{"library_path":"libnvidia-egl-gbm.so.1"}}' \
                > /usr/share/egl/egl_external_platform.d/15_nvidia_gbm.json
        fi

        if [ ! -f /usr/share/egl/egl_external_platform.d/10_nvidia_wayland.json ]; then
            mkdir -p /usr/share/egl/egl_external_platform.d/
            echo '{"file_format_version":"1.0.0","ICD":{"library_path":"libnvidia-egl-wayland.so.1"}}' \
                > /usr/share/egl/egl_external_platform.d/10_nvidia_wayland.json
        fi
    fi

fi

# Se um comando foi passado como argumento (ex: CMD ["/bin/bash"]), executa como UNAME
# usando setpriv como alternativa ao gosu
if [ -n "${*:-}" ]; then
    exec setpriv \
        --reuid="${PUID:-1000}" \
        --regid="${PGID:-1000}" \
        --init-groups \
        -- /bin/bash -c "$*"
fi

# Caso contrário, lança o script de startup como usuário UNAME
gow_log "Launching the container's startup script as user '${UNAME}'"
chmod +x /opt/gow/startup.sh
exec setpriv \
    --reuid="${PUID:-1000}" \
    --regid="${PGID:-1000}" \
    --init-groups \
    -- /opt/gow/startup.sh
