FROM alpine:3.21
ARG TARGETARCH=arm64
ARG XRAY_VERSION=v26.10.31
RUN apk add --no-cache curl ca-certificates unzip bash \
 && case "${TARGETARCH}" in \
      amd64) A="Xray-linux-64.zip" ;; \
      arm64) A="Xray-linux-arm64-v8a.zip" ;; \
      *) echo "unsupported arch ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && curl -fsSL -o /tmp/x.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/${A}" \
 && unzip -q /tmp/x.zip -d /usr/local/bin \
 && rm -f /tmp/x.zip \
 && chmod +x /usr/local/bin/xray
ENTRYPOINT ["/usr/local/bin/xray"]
