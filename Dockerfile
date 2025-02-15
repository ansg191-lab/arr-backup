################################################################################
# Create a stage for building the application.

FROM --platform=$BUILDPLATFORM rust:1.84.1-alpine@sha256:12360d0b997278c4bc8ccde026dba3260ccc8320352f71392680a4c5dd1fc824 AS build
WORKDIR /app

# Install deps
RUN apk add --no-cache clang lld musl-dev git zig && \
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
