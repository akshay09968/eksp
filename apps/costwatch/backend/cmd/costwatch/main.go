// costwatch: FinOps visibility for this AWS account — hourly/daily/monthly
// spend, per service down to per resource, served as an embedded React app.
// Read-only against Cost Explorer via EKS Pod Identity; `-demo` runs the whole
// thing on synthetic data with zero AWS access.
package main

import (
	"context"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/costexplorer"

	"github.com/akshaydeshpande/eksp/apps/costwatch/internal/api"
	"github.com/akshaydeshpande/eksp/apps/costwatch/internal/costs"
	"github.com/akshaydeshpande/eksp/apps/costwatch/web"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	demoFlag := flag.Bool("demo", false, "serve deterministic synthetic data (no AWS access)")
	flag.Parse()
	demo := *demoFlag || os.Getenv("DEMO") == "true"

	ttl := 6 * time.Hour
	if v := os.Getenv("CACHE_TTL"); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			ttl = d
		}
	}

	var client costs.CostExplorerAPI
	if demo {
		log.Info("demo mode: synthetic data, no AWS calls")
		client = costs.NewDemoClient()
	} else {
		// Cost Explorer only exists in us-east-1 — pin it regardless of where
		// the pod runs. Credentials come from the Pod Identity chain.
		cfg, err := config.LoadDefaultConfig(context.Background(), config.WithRegion("us-east-1"))
		if err != nil {
			log.Error("aws config", "err", err)
			os.Exit(1)
		}
		client = costexplorer.NewFromConfig(cfg)
	}

	svc := costs.NewService(client, costs.WithTTL(ttl))
	server := api.New(svc, demo, web.FS())

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           server.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()

	go func() {
		log.Info("costwatch listening", "port", port, "demo", demo, "cacheTTL", ttl.String())
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Error("server failed", "err", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(shutdownCtx)
	log.Info("stopped")
}
