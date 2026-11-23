FROM gcr.io/distroless/base:debug
ENTRYPOINT [ "/go/bin/auroranet-relay" ]
ENV NB_LOG_FILE=console
ARG TARGETPLATFORM
COPY ${TARGETPLATFORM}/auroranet-relay /go/bin/auroranet-relay
