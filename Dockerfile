# ---------- Stage 1: export the Godot project to HTML5 ----------
FROM debian:bookworm-slim AS builder

# Must match your editor version. Export templates MUST be the exact same version.
ARG GODOT_VERSION=4.6.2
ARG GODOT_RELEASE=stable

# fontconfig keeps Godot from spamming font errors during headless export
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates wget unzip libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*

# Install the headless Godot editor binary (clean up the zip in the same layer)
RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64.zip" -O /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /tmp \
    && mv "/tmp/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm -f /tmp/godot.zip

# Install ONLY the Web export templates (the full .tpz is ~1GB and OOMs the builder)
RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_export_templates.tpz" -O /tmp/templates.tpz \
    && unzip -q /tmp/templates.tpz -d /tmp \
    && TPL_DIR="/root/.local/share/godot/export_templates/${GODOT_VERSION}.${GODOT_RELEASE}" \
    && mkdir -p "$TPL_DIR" \
    && cp /tmp/templates/web*.zip "$TPL_DIR/" \
    && cp /tmp/templates/version.txt "$TPL_DIR/" \
    && rm -rf /tmp/templates /tmp/templates.tpz

WORKDIR /src
COPY . .

# Generate a Web export preset if the repo didn't ship one. This makes the build
# self-contained even when export_presets.cfg is gitignored or not committed.
RUN if [ ! -f export_presets.cfg ]; then \
      printf '%s\n' \
        '[preset.0]' \
        '' \
        'name="Web"' \
        'platform="Web"' \
        'runnable=true' \
        'advanced_options=false' \
        'dedicated_server=false' \
        'custom_features=""' \
        'export_filter="all_resources"' \
        'include_filter=""' \
        'exclude_filter=""' \
        'export_path="build/index.html"' \
        'patches=PackedStringArray()' \
        'encryption_include_filters=""' \
        'encryption_exclude_filters=""' \
        'seed=0' \
        'encrypt_pck=false' \
        'encrypt_directory=false' \
        'script_export_mode=2' \
        '' \
        '[preset.0.options]' \
        '' \
        'custom_template/debug=""' \
        'custom_template/release=""' \
        'variant/extensions_support=false' \
        'variant/thread_support=false' \
        'vram_texture_compression/for_desktop=true' \
        'vram_texture_compression/for_mobile=false' \
        'html/export_icon=true' \
        'html/custom_html_shell=""' \
        'html/head_include=""' \
        'html/canvas_resize_policy=2' \
        'html/focus_canvas_on_start=true' \
        'html/experimental_virtual_keyboard=false' \
        'progressive_web_app/enabled=false' \
      > export_presets.cfg; \
      echo "Generated export_presets.cfg"; \
    else \
      echo "Using committed export_presets.cfg"; \
    fi

# Import assets first (generates the .godot import cache), then export.
RUN mkdir -p build \
    && godot --headless --path . --import || true \
    && godot --headless --path . --export-release "Web" build/index.html \
    && test -f build/index.html

# ---------- Stage 2: serve the exported files ----------
FROM nginx:1.27-alpine

COPY --from=builder /src/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 8080
