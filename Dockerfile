# ---------- Stage 1: export the Godot project to HTML5 ----------
FROM debian:bookworm-slim AS builder

# Must match your editor version. Export templates MUST be the exact same version.
ARG GODOT_VERSION=4.6.2
ARG GODOT_RELEASE=stable

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates wget unzip \
    && rm -rf /var/lib/apt/lists/*

# Install the headless Godot editor binary
RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64.zip" -O /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /tmp \
    && mv "/tmp/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot

# Install matching export templates into the path Godot expects
RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_export_templates.tpz" -O /tmp/templates.tpz \
    && unzip -q /tmp/templates.tpz -d /tmp \
    && mkdir -p "/root/.local/share/godot/export_templates/${GODOT_VERSION}.${GODOT_RELEASE}" \
    && mv /tmp/templates/* "/root/.local/share/godot/export_templates/${GODOT_VERSION}.${GODOT_RELEASE}/"

WORKDIR /src
COPY . .

# Import assets first (generates the .godot import cache), then export.
# The import pass can print non-fatal errors on a fresh project, so we don't fail on it.
RUN mkdir -p build \
    && godot --headless --path . --import || true \
    && godot --headless --path . --export-release "Web" build/index.html

# Godot names the web entry file after the export_path. Make sure it's index.html.
RUN test -f build/index.html

# ---------- Stage 2: serve the exported files ----------
FROM nginx:1.27-alpine

COPY --from=builder /src/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 8080
