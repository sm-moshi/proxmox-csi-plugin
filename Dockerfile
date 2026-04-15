# syntax = docker/dockerfile:1.23@sha256:2780b5c3bab67f1f76c781860de469442999ed1a0d7992a5efdf2cffc0e3d769
########################################

FROM golang:1.26.2-trixie@sha256:c0074c718b473f3827043f86532c4c0ff537e3fe7a81b8219b0d1ccfcc2c9a09 AS develop

WORKDIR /src
COPY ["go.mod", "go.sum", "/src/"]
RUN go mod download

########################################

FROM --platform=${BUILDPLATFORM} golang:1.26.2-alpine3.23@sha256:c2a1f7b2095d046ae14b286b18413a05bb82c9bca9b25fe7ff5efef0f0826166 AS builder
RUN apk update && apk add --no-cache make git
ENV GO111MODULE=on
WORKDIR /src

COPY ["go.mod", "go.sum", "/src/"]
RUN go mod download && go mod verify

COPY . .
ARG TAG
ARG SHA
ENV TAG=${TAG} SHA=${SHA}
RUN make build-all-archs

########################################

FROM --platform=${TARGETARCH} scratch AS proxmox-csi-controller
LABEL org.opencontainers.image.source="https://github.com/sergelogvinov/proxmox-csi-plugin" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.description="Proxmox VE CSI plugin"

COPY --from=gcr.io/distroless/static-debian13:nonroot@sha256:e3f945647ffb95b5839c07038d64f9811adf17308b9121d8a2b87b6a22a80a39 . .
ARG TARGETARCH
COPY --from=builder /src/bin/proxmox-csi-controller-${TARGETARCH} /bin/proxmox-csi-controller

ENTRYPOINT ["/bin/proxmox-csi-controller"]

########################################

FROM --platform=${TARGETARCH} debian:13.4@sha256:3352c2e13876c8a5c5873ef20870e1939e73cb9a3c1aeba5e3e72172a85ce9ed AS tools

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    mount \
    udev \
    e2fsprogs \
    xfsprogs \
    util-linux \
    cryptsetup \
    rsync

COPY tools/ /tools/
RUN /tools/deps.sh

########################################

FROM --platform=${TARGETARCH} gcr.io/distroless/base-debian13@sha256:c83f022002fc917a92501a8c30c605efdad3010157ba2c8998a2cbf213299201 AS tools-check

COPY --from=tools /bin/sh /bin/sh
COPY --from=tools /tools/ /tools/
COPY --from=tools /dest/ /

SHELL ["/bin/sh"]
RUN /tools/deps-check.sh

########################################

FROM --platform=${TARGETARCH} scratch AS proxmox-csi-node
LABEL org.opencontainers.image.source="https://github.com/sergelogvinov/proxmox-csi-plugin" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.description="Proxmox VE CSI plugin"

COPY --from=gcr.io/distroless/base-debian13@sha256:c83f022002fc917a92501a8c30c605efdad3010157ba2c8998a2cbf213299201 . .
COPY --from=tools /dest/ /

ARG TARGETARCH
COPY --from=builder /src/bin/proxmox-csi-node-${TARGETARCH} /bin/proxmox-csi-node

ENTRYPOINT ["/bin/proxmox-csi-node"]

########################################

FROM alpine:3.23@sha256:c69a6ff7c24d1ffa913798501d0e7104e0e9764e28eb44a930939f91ef829e64 AS pvecsictl
LABEL org.opencontainers.image.source="https://github.com/sergelogvinov/proxmox-csi-plugin" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.description="Proxmox VE CSI tools"

ARG TARGETARCH
COPY --from=builder /src/bin/pvecsictl-${TARGETARCH} /bin/pvecsictl

ENTRYPOINT ["/bin/pvecsictl"]

########################################

FROM alpine:3.23@sha256:c69a6ff7c24d1ffa913798501d0e7104e0e9764e28eb44a930939f91ef829e64 AS pvecsictl-goreleaser
LABEL org.opencontainers.image.source="https://github.com/sergelogvinov/proxmox-csi-plugin" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.description="Proxmox VE CSI tools"

ARG TARGETARCH
COPY pvecsictl-linux-${TARGETARCH} /bin/pvecsictl

ENTRYPOINT ["/bin/pvecsictl"]
