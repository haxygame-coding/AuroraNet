FROM golang:1.26.10-alpine AS builder
WORKDIR /app

RUN echo "auroranet:x:1000:1000:auroranet:/var/lib/auroranet:/sbin/nologin" > /tmp/passwd && \
    echo "auroranet:x:1000:auroranet" > /tmp/group && \
    mkdir -p /tmp/var/lib/auroranet && \
    mkdir -p /tmp/certs

FROM gcr.io/distroless/base:debug
ARG TARGETPLATFORM
COPY ${TARGETPLATFORM}/auroranet-proxy /go/bin/auroranet-proxy
COPY --from=builder /tmp/passwd /etc/passwd
COPY --from=builder /tmp/group /etc/group
COPY --from=builder --chown=1000:1000 /tmp/var/lib/auroranet /var/lib/auroranet
COPY --from=builder --chown=1000:1000 --chmod=755 /tmp/certs /certs
USER auroranet:auroranet
ENV HOME=/var/lib/auroranet
ENV NB_PROXY_ADDRESS=":8443"
EXPOSE 8443
ENTRYPOINT ["/go/bin/auroranet-proxy"]
