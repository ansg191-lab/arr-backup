################################################################################
# Create a stage for building the application.

FROM --platform=$BUILDPLATFORM rust:1.85.0-alpine3.21@sha256:654d54214c3ebd48d3e981cc4ad4d4a73be3c9610675be04b979df89064295f7 AS build
WORKDIR /app

# renovate: datasource=repology depName=alpine_3_21/zig versioning=loose
ENV ZIG_VERSION="0.13.0-r1"
# renovate: datasource=repology depName=alpine_3_21/musl-dev versioning=loose
ENV MUSL_DEV_VERSION="1.2.5-r9"

# Install deps
RUN apk add --no-cache \
    	musl-dev=${MUSL_DEV_VERSION} \
    	zig=${ZIG_VERSION} \
    && \
    cargo install --locked cargo-zigbuild && \
    rustup target add x86_64-unknown-linux-musl aarch64-unknown-linux-musl

# Build the application.
# Leverage a cache mount to /usr/local/cargo/registry/
# for downloaded dependencies, a cache mount to /usr/local/cargo/git/db
# for git repository dependencies, and a cache mount to /app/target/ for
# compiled dependencies which will speed up subsequent builds.
# Leverage a bind mount to the src directory to avoid having to copy the
# source code into the container. Once built, copy the executable to an
# output directory before the cache mounted /app/target is unmounted.
RUN --mount=type=bind,source=src,target=src \
    --mount=type=bind,source=Cargo.toml,target=Cargo.toml \
    --mount=type=bind,source=Cargo.lock,target=Cargo.lock \
    --mount=type=cache,target=/app/target/ \
    --mount=type=cache,target=/usr/local/cargo/git/db \
    --mount=type=cache,target=/usr/local/cargo/registry/ \
    cargo zigbuild --release --target x86_64-unknown-linux-musl --target aarch64-unknown-linux-musl && \
    mkdir /app/linux && \
    cp target/aarch64-unknown-linux-musl/release/arr-backup /app/linux/arm64 && \
    cp target/x86_64-unknown-linux-musl/release/arr-backup /app/linux/amd64

################################################################################
FROM alpine:3.21@sha256:a8560b36e8b8210634f77d9f7f9efd7ffa463e380b75e2e74aff4511df3ef88c AS final
ARG TARGETPLATFORM

# Create a non-privileged user that the app will run under.
# See https://docs.docker.com/go/dockerfile-user-best-practices/
ARG UID=10001
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    appuser
USER appuser

# Copy the executable from the "build" stage.

COPY --from=build /app/${TARGETPLATFORM} /bin/arr-backup

CMD [ "/bin/arr-backup" ]
