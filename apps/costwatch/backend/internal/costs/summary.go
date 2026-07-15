package costs

import (
	"context"
	"sort"
	"strconv"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/costexplorer"
	cetypes "github.com/aws/aws-sdk-go-v2/service/costexplorer/types"
)

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

func (s *Service) Summary(ctx context.Context) (Summary, error) {
	val, cached, err := s.cache.do("summary", func() (any, error) {
		return s.fetchSummary(ctx)
	})
	if err != nil {
		return Summary{}, err
	}
	sum := val.(Summary)
	sum.Cached = cached
	return sum, nil
}

func (s *Service) fetchSummary(ctx context.Context) (Summary, error) {
	now := s.now().UTC()
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	prevStart := monthStart.AddDate(0, -1, 0)
	dayOffset := int(now.Sub(monthStart).Hours() / 24)
	prevEnd := prevStart.AddDate(0, 0, dayOffset)
	nextMonth := monthStart.AddDate(0, 1, 0)

	current, err := s.byService(ctx, monthStart, now)
	if err != nil {
		return Summary{}, err
	}
	previous, err := s.byService(ctx, prevStart, prevEnd)
	if err != nil {
		return Summary{}, err
	}

	sum := Summary{Currency: "USD", FetchedAt: now}
	for _, v := range current {
		sum.MonthToDate += v
	}
	for _, v := range previous {
		sum.PrevMonthToDate += v
	}
	if sum.PrevMonthToDate > 0 {
		sum.DeltaPct = (sum.MonthToDate - sum.PrevMonthToDate) / sum.PrevMonthToDate * 100
	}

	// Forecast to month end (skip when the API has nothing to extrapolate —
	// e.g. brand-new accounts).
	fc, err := s.api.GetCostForecast(ctx, &costexplorer.GetCostForecastInput{
		TimePeriod: &cetypes.DateInterval{
			Start: aws.String(now.Format("2006-01-02")),
			End:   aws.String(nextMonth.Format("2006-01-02")),
		},
		Metric:      cetypes.MetricUnblendedCost,
		Granularity: cetypes.GranularityMonthly,
	})
	if err == nil && fc.Total != nil && fc.Total.Amount != nil {
		if v, perr := strconv.ParseFloat(*fc.Total.Amount, 64); perr == nil {
			sum.ForecastMonthEnd = v
		}
	}

	// Top movers by absolute delta vs the same window last month.
	seen := map[string]bool{}
	for k := range current {
		seen[k] = true
	}
	for k := range previous {
		seen[k] = true
	}
	for svc := range seen {
		sum.TopMovers = append(sum.TopMovers, Mover{
			Service:  svc,
			Current:  current[svc],
			Previous: previous[svc],
			Delta:    current[svc] - previous[svc],
		})
	}
	sort.Slice(sum.TopMovers, func(i, j int) bool {
		return abs(sum.TopMovers[i].Delta) > abs(sum.TopMovers[j].Delta)
	})
	if len(sum.TopMovers) > 5 {
		sum.TopMovers = sum.TopMovers[:5]
	}

	return sum, nil
}

func (s *Service) byService(ctx context.Context, start, end time.Time) (map[string]float64, error) {
	input := &costexplorer.GetCostAndUsageInput{
		TimePeriod: &cetypes.DateInterval{
			Start: aws.String(start.Format("2006-01-02")),
			End:   aws.String(end.Format("2006-01-02")),
		},
		Granularity: cetypes.GranularityMonthly,
		Metrics:     []string{"UnblendedCost"},
		GroupBy: []cetypes.GroupDefinition{{
			Type: cetypes.GroupDefinitionTypeDimension,
			Key:  aws.String("SERVICE"),
		}},
	}

	totals := map[string]float64{}
	for {
		out, err := s.api.GetCostAndUsage(ctx, input)
		if err != nil {
			return nil, mapCEError(err)
		}
		for _, r := range out.ResultsByTime {
			for _, g := range r.Groups {
				if len(g.Keys) == 0 {
					continue
				}
				if m, ok := g.Metrics["UnblendedCost"]; ok && m.Amount != nil {
					if v, err := strconv.ParseFloat(*m.Amount, 64); err == nil {
						totals[g.Keys[0]] += v
					}
				}
			}
		}
		if out.NextPageToken == nil || *out.NextPageToken == "" {
			break
		}
		input.NextPageToken = out.NextPageToken
	}
	return totals, nil
}

func abs(v float64) float64 {
	if v < 0 {
		return -v
	}
	return v
}
