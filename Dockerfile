# Stage 1: Cortex Agent artifacts source
FROM distributions.traps.paloaltonetworks.com/agent-docker-pull/fb3a9c3931e64c6d9cca8bda5a021a22/method:9.3.0.220 AS cortex_agent

# Stage 2: Build & Installer environment (Debian-based, contains /bin/sh)
FROM node:24-slim AS installer

COPY . /juice-shop
WORKDIR /juice-shop

# Install dependencies and build Juice Shop
RUN npm install -g typescript@^6.0.3
RUN npm install --omit=dev
RUN npm dedupe --omit=dev
RUN rm -rf frontend/node_modules
RUN rm -rf frontend/.angular
RUN rm -rf frontend/src/assets
RUN mkdir logs
RUN chown -R 65532 logs
RUN chgrp -R 0 ftp/ frontend/dist/ logs/ data/ i18n/
RUN chmod -R g=u ftp/ frontend/dist/ logs/ data/ i18n/
RUN rm ftp/legal.md || true
RUN rm i18n/*.json || true

# keep version in sync with package.json
ARG CYCLONEDX_NPM_VERSION='^2.0.0||^3.0.0||^4.0.0'
RUN npm install -g @cyclonedx/cyclonedx-npm@$CYCLONEDX_NPM_VERSION
RUN npm run sbom

# --- Cortex Agent Setup ---
COPY --from=cortex_agent /opt/traps /opt/traps
COPY --from=cortex_agent /etc/panw-init /etc/panw-init
COPY --from=cortex_agent /var/log/traps-install.log /var/log/traps-install.log
COPY --from=cortex_agent /etc/ssl/certs/ /etc/ssl/certs/
COPY --from=cortex_agent /usr/share/ca-certificates/ /usr/share/ca-certificates/

# Prepare SSL links and entrypoints directly in standard system paths
RUN mkdir -p /usr/lib/ssl \
 && rm -rf /usr/lib/ssl/certs \
 && ln -sfn /etc/ssl/certs /usr/lib/ssl/certs \
 && ln -sf /etc/ssl/certs/ca-certificates.crt /usr/lib/ssl/cert.pem \
 && ln -sf /opt/traps/bin/initd /initd \
 && mkdir -p /etc/panw \
 && echo '["/juice-shop/build/app.js"]' > /etc/panw/dypd_entry \
 && chmod 666 /etc/panw/dypd_entry

# Stage 3: Final Distroless Production Image
FROM gcr.io/distroless/nodejs24-debian13

ARG BUILD_DATE
ARG VCS_REF
LABEL maintainer="Bjoern Kimminich <bjoern.kimminich@owasp.org>" \
    org.opencontainers.image.title="OWASP Juice Shop" \
    org.opencontainers.image.description="Probably the most modern and sophisticated insecure web application" \
    org.opencontainers.image.authors="Bjoern Kimminich <bjoern.kimminich@owasp.org>" \
    org.opencontainers.image.vendor="Open Worldwide Application Security Project" \
    org.opencontainers.image.documentation="https://help.owasp-juice.shop" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.version="20.2.0" \
    org.opencontainers.image.url="https://owasp-juice.shop" \
    org.opencontainers.image.source="https://github.com/juice-shop/juice-shop" \
    org.opencontainers.image.revision=$VCS_REF \
    org.opencontainers.image.created=$BUILD_DATE

WORKDIR /juice-shop
COPY --from=installer --chown=65532:0 /juice-shop .

# Copy prepared Cortex paths directly into distroless image
COPY --from=installer /opt/traps /opt/traps
COPY --from=installer /etc/panw-init /etc/panw-init
COPY --from=installer /etc/panw /etc/panw
COPY --from=installer /var/log/traps-install.log /var/log/traps-install.log
COPY --from=installer /etc/ssl/certs /etc/ssl/certs
COPY --from=installer /usr/share/ca-certificates /usr/share/ca-certificates
COPY --from=installer /usr/lib/ssl /usr/lib/ssl
COPY --from=installer /initd /initd

ENV XDR_CA_CERTS_LOCATION="/etc/ssl/certs/ca-certificates.crt" \
    XDR_INIT_ROOT_DIR="/etc/panw-init" \
    XDR_DISTRIBUTION_ID="fb3a9c3931e64c6d9cca8bda5a021a22" \
    XDR_CONTAINER_MODE="embeddedcontainer" \
    XDR_DISTRIBUTION_SERVER="https://distributions.traps.paloaltonetworks.com"

USER 65532
EXPOSE 3000

ENTRYPOINT ["/initd"]
