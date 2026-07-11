# Three stages: build the SPA, embed it into the Go binary, ship distroless.
# Context: apps/costwatch (both frontend/ and backend/ visible).

FROM node:22-alpine AS ui
WORKDIR /ui
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ .
# vite.config outDir points at ../backend/web/dist — recreate that shape here
COPY backend/web/dist/.gitkeep /backend/web/dist/.gitkeep
RUN npm run build -- --outDir /backend/web/dist --emptyOutDir

FROM --platform=$BUILDPLATFORM golang:1.26 AS build
ARG TARGETOS TARGETARCH
WORKDIR /src
COPY backend/go.mod backend/go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY backend/ .
COPY --from=ui /backend/web/dist ./web/dist
ARG VERSION=dev
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath \
    -ldflags="-s -w -X github.com/akshaydeshpande/eksp/apps/costwatch/internal/api.Version=$VERSION" \
    -o /out/costwatch ./cmd/costwatch

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/costwatch /costwatch
ENV PORT=8080
EXPOSE 8080
USER nonroot
ENTRYPOINT ["/costwatch"]
