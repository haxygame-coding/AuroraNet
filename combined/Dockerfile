FROM ubuntu:24.04
RUN apt update && apt install -y ca-certificates && rm -fr /var/cache/apt
ENTRYPOINT [ "/go/bin/auroranet-server" ]
CMD ["--config", "/etc/auroranet/config.yaml"]
ARG TARGETPLATFORM
COPY ${TARGETPLATFORM}/auroranet-server /go/bin/auroranet-server
