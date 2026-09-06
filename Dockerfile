# syntax=docker/dockerfile:1
# Blessing Skin Server - LinuxServer.io (LSIO) style image
# Modeled after SnowMoonSS/MCSManager-lsio

ARG BUILDPLATFORM=linux/amd64
# Optional: pin a specific PHP version (e.g. 8.1) pulled from packages.sury.org.
# Leave empty to use the distro's default PHP (Debian trixie -> 8.4).
ARG PHP_VERSION=

###############################################################################
# Stage: source — fetch the Blessing Skin source (git or release zip)
###############################################################################
FROM --platform=${BUILDPLATFORM} alpine:3.20 AS source
WORKDIR /src

ARG BLESSING_REPO=https://github.com/bs-community/blessing-skin-server.git
ARG BLESSING_VERSION=dev
ARG BLESSING_SOURCE=git

RUN apk add --no-cache git curl unzip ca-certificates bash && \
    if [ "${BLESSING_SOURCE}" = "release" ]; then \
      echo "Fetching release: ${BLESSING_VERSION}" && \
      curl -fsSL -o /tmp/release.zip "https://github.com/bs-community/blessing-skin-server/releases/download/${BLESSING_VERSION}/blessing-skin-server-${BLESSING_VERSION}.zip" && \
      unzip -q /tmp/release.zip -d /tmp/extracted && \
      if [ -d /tmp/extracted/public ]; then \
        cp -a /tmp/extracted/. /src/; \
      else \
        d=$(find /tmp/extracted -mindepth 1 -maxdepth 1 -type d | head -n 1); \
        cp -a "${d}/." /src/; \
      fi; \
    else \
      echo "Cloning ${BLESSING_REPO} @ ${BLESSING_VERSION}" && \
      git clone --depth 1 --branch "${BLESSING_VERSION}" "${BLESSING_REPO}" . && \
      rm -rf .git; \
    fi && \
    # sanity check: artisan + public/index.php exist in both git and release payloads
    test -f /src/artisan && test -f /src/public/index.php && \
    echo "Source ready"

###############################################################################
# Stage: vendor — install PHP dependencies
###############################################################################
FROM --platform=${BUILDPLATFORM} composer:latest AS vendor
WORKDIR /src

ARG BLESSING_SOURCE=git
COPY --from=source /src ./

RUN if [ "${BLESSING_SOURCE}" = "git" ]; then \
      echo "Installing PHP dependencies via composer" && \
      composer install \
        --prefer-dist \
        --no-dev \
        --no-suggest \
        --no-progress \
        --no-autoloader \
        --no-scripts \
        --no-interaction \
        --ignore-platform-reqs; \
    else \
      echo "Release mode: vendor already bundled in the archive"; \
    fi

###############################################################################
# Stage: frontend — build webpack assets (only for git/source builds)
###############################################################################
FROM --platform=${BUILDPLATFORM} node:lts-alpine AS frontend
WORKDIR /app

ARG BLESSING_SOURCE=git
COPY --from=source /src ./

RUN mkdir -p resources/views/assets public && \
    if [ "${BLESSING_SOURCE}" = "git" ]; then \
      echo "Cleaning prior webpack output" && \
      rm -rf public/app && \
      yarn install --frozen-lockfile && \
      yarn build && \
      cp resources/assets/src/images/bg.webp public/app/ 2>/dev/null || true && \
      cp resources/assets/src/images/favicon.ico public/app/ 2>/dev/null || true && \
      echo "Frontend built"; \
    else \
      echo "Release mode: using prebuilt public assets"; \
    fi

###############################################################################
# Stage: builder — assemble the final application image payload
###############################################################################
FROM --platform=${BUILDPLATFORM} composer:latest AS builder
WORKDIR /app

ARG BLESSING_SOURCE=git
COPY --from=source /src ./
COPY --from=vendor /src/vendor ./vendor
COPY --from=frontend /app/public ./public
COPY --from=frontend /app/resources/views/assets ./resources/views/assets

RUN if [ "${BLESSING_SOURCE}" = "git" ]; then \
      echo "Optimizing autoloader and cleaning dev files" && \
      composer dump-autoload --no-dev -o && \
      rm -rf *.config.js *.config.ts tsconfig.* package.json yarn.lock node_modules/ \
        resources/assets/ resources/misc resources/misc/backgrounds/ tools/; \
    else \
      echo "Release mode: using prebuilt application payload"; \
    fi && \
    # Ship the base storage structure (static, build-time).
    # .env and APP_KEY are generated at runtime by init-bs-config/run.
    touch storage/database.db && \
    mkdir -p storage/plugins && \
    echo "Builder finished"

###############################################################################
# Stage: runtime — LinuxServer.io base + Apache + PHP + s6-overlay
###############################################################################
FROM ghcr.io/linuxserver/baseimage-debian:trixie

ARG PHP_VERSION=

ENV S6_VERBOSITY=1 \
    APACHE_DOCUMENT_ROOT=/app/public

# If PHP_VERSION is provided (e.g. 8.1/8.2/8.4), install that version's
# packages from packages.sury.org (which also ships older PHP versions for
# trixie). When PHP_VERSION is empty, use trixie's default PHP (8.4) from the
# standard Debian archive.
RUN set -eux; \
    if [ -n "${PHP_VERSION}" ]; then \
      MOD="libapache2-mod-php${PHP_VERSION}"; \
      P="php${PHP_VERSION}-"; \
      CLI="php${PHP_VERSION}-cli"; \
    else \
      MOD="libapache2-mod-php"; \
      P="php-"; \
      CLI="php-cli"; \
    fi; \
    apt-get update; \
    if [ -n "${PHP_VERSION}" ]; then \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends curl ca-certificates; \
      curl -fsSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg; \
      echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(. /etc/os-release && echo "${VERSION_CODENAME}") main" > /etc/apt/sources.list.d/php.list; \
      apt-get update; \
    fi; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      apache2 \
      ${MOD} \
      ${CLI} \
      ${P}mbstring \
      ${P}xml \
      ${P}curl \
      ${P}zip \
      ${P}gd \
      ${P}imagick \
      ${P}sqlite3 \
      ${P}mysql \
      ${P}redis \
      ${P}opcache \
      curl \
      ca-certificates \
      sqlite3 \
      netcat-openbsd; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Copy the built application
COPY --from=builder /app /app

# Apache configuration: document root, rewrite + headers.
RUN a2enmod rewrite headers && \
    sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf && \
    sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf && \
    echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf && \
    a2enconf servername

# Bring in s6-overlay services + apache blessing config
COPY root/ /

RUN chmod +x /etc/s6-overlay/s6-rc.d/svc-bs/run && \
    chmod +x /etc/s6-overlay/s6-rc.d/init-bs-config/run && \
    chmod +x /etc/s6-overlay/s6-rc.d/svc-bs-queue-worker/run && \
    a2enconf blessing

EXPOSE 80
VOLUME ["/config", "/data"]
