// Package web embeds the built frontend. dist/ holds a committed placeholder
// so `go build` always works; `npm run build` (vite outDir) overwrites it with
// the real SPA before the container image is assembled (ADR-0015).
package web

import (
	"embed"
	"io/fs"
)

//go:embed all:dist
var dist embed.FS

func FS() fs.FS {
	sub, err := fs.Sub(dist, "dist")
	if err != nil {
		panic(err) // unreachable: dist is embedded at compile time
	}
	return sub
}
