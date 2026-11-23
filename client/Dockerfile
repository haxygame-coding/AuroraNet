# build & run locally with:
#   cd "$(git rev-parse --show-toplevel)"
#   CGO_ENABLED=0 go build -o auroranet ./client
#   sudo podman build -t localhost/auroranet:latest -f client/Dockerfile --ignorefile .dockerignore-client .
#   sudo podman run --rm -it --cap-add={BPF,NET_ADMIN,NET_RAW} localhost/auroranet:latest

FROM alpine:3.24
# iproute2: busybox doesn't display ip rules properly
RUN apk add --no-cache \
    bash \
    ca-certificates \
    ip6tables \
    iproute2 \
    iptables

ENV \
    AURORANET_BIN="/usr/local/bin/auroranet" \
    NB_LOG_FILE="console,/var/log/auroranet/client.log" \
    NB_DAEMON_ADDR="unix:///var/run/auroranet.sock" \
    NB_ENABLE_CAPTURE="false" \
    NB_ENTRYPOINT_SERVICE_TIMEOUT="30"

ENTRYPOINT [ "/usr/local/bin/auroranet-entrypoint.sh" ]
ARG TARGETPLATFORM
ARG AURORANET_BINARY=$TARGETPLATFORM/auroranet
COPY client/auroranet-entrypoint.sh /usr/local/bin/auroranet-entrypoint.sh
COPY "${AURORANET_BINARY}"  /usr/local/bin/auroranet
