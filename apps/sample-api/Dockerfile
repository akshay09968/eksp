# Multi-stage, multi-arch (amd64+arm64 — Graviton spot is the cost story).
# Final image is distroless static: ~2MB of attack surface, no shell — which is
# why the app implements its own drain instead of a preStop sleep.

FROM --platform=$BUILDPLATFORM golang:1.26 AS build
ARG TARGETOS TARGETARCH
WORKDIR /src

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY . .
ARG VERSION=dev
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags="-s -w" -o /out/sample-api .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/sample-api /sample-api
ENV PORT=8080
EXPOSE 8080
USER nonroot
ENTRYPOINT ["/sample-api"]
