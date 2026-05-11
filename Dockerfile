# ================================
# Build image
# ================================
FROM swift:6.1-noble AS build

ARG TARGETPLATFORM

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get install -y libjemalloc-dev \
    && rm -r /var/lib/apt/lists/*

WORKDIR /build

# Resolve dependencies (cached layer)
COPY ./Package.* ./
RUN swift package resolve \
        $([ -f ./Package.resolved ] && echo "--force-resolved-versions" || true)

COPY . .

RUN mkdir /staging

# Build server
RUN --mount=type=cache,id=pingd-swift-build-${TARGETPLATFORM},target=/build/.build \
    swift build -c release \
        --product pingd \
        --static-swift-stdlib \
        -Xlinker -ljemalloc && \
    cp "$(swift build -c release --show-bin-path)/pingd" /staging && \
    find -L "$(swift build -c release --show-bin-path)" -regex '.*\.resources$' -exec cp -Ra {} /staging \;

# Build CLI
RUN --mount=type=cache,id=pingd-swift-build-${TARGETPLATFORM},target=/build/.build \
    swift build -c release \
        --product pingd-cli \
        --static-swift-stdlib \
        -Xlinker -ljemalloc && \
    cp "$(swift build -c release --show-bin-path)/pingd-cli" /staging

# Build VAPID keygen
RUN --mount=type=cache,id=pingd-swift-build-${TARGETPLATFORM},target=/build/.build \
    swift build -c release \
        --product pingd-webpush-keygen \
        --static-swift-stdlib \
        -Xlinker -ljemalloc && \
    cp "$(swift build -c release --show-bin-path)/pingd-webpush-keygen" /staging

WORKDIR /staging

RUN cp "/usr/libexec/swift/linux/swift-backtrace-static" ./

# Copy Public directory for web UI
RUN [ -d /build/Public ] && { mv /build/Public ./Public && chmod -R a-w ./Public; } || true
RUN [ -d /build/Resources ] && { mv /build/Resources ./Resources && chmod -R a-w ./Resources; } || true

# ================================
# Run image
# ================================
FROM ubuntu:noble

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q install -y \
      libjemalloc2 \
      ca-certificates \
      curl \
      tzdata \
    && rm -r /var/lib/apt/lists/*

RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor

RUN mkdir -p /data && chown vapor:vapor /data

WORKDIR /app

COPY --from=build --chown=vapor:vapor /staging /app

ENV SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no,swift-backtrace=./swift-backtrace-static

USER vapor:vapor

EXPOSE 7685

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:7685/health || exit 1

ENTRYPOINT ["./pingd"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0"]
