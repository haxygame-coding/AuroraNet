FROM gcr.io/distroless/base:debug
ENTRYPOINT [ "/go/bin/auroranet-signal","run" ]
CMD ["--log-file", "console"]
ARG TARGETPLATFORM
COPY ${TARGETPLATFORM}/auroranet-signal /go/bin/auroranet-signal
