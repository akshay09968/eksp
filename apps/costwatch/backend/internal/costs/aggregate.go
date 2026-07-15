package costs

import (
	"sort"
	"strconv"

	cetypes "github.com/aws/aws-sdk-go-v2/service/costexplorer/types"
)

func (s *Service) aggregate(results []cetypes.ResultByTime) Series {
	series := Series{Currency: "USD", FetchedAt: s.now().UTC()}
	groupIdx := map[string]int{}

	for _, r := range results {
		if r.TimePeriod == nil || r.TimePeriod.Start == nil {
			continue
		}
		series.Times = append(series.Times, *r.TimePeriod.Start)
		t := len(series.Times) - 1

		for _, g := range r.Groups {
			if len(g.Keys) == 0 {
				continue
			}
			key := g.Keys[0]
			metric, ok := g.Metrics["UnblendedCost"]
			if !ok || metric.Amount == nil {
				continue
			}
			amount, err := strconv.ParseFloat(*metric.Amount, 64)
			if err != nil {
				continue
			}
			if metric.Unit != nil && *metric.Unit != "" {
				series.Currency = *metric.Unit
			}

			idx, ok := groupIdx[key]
			if !ok {
				idx = len(series.Groups)
				groupIdx[key] = idx
				series.Groups = append(series.Groups, GroupSeries{Key: key})
			}
			for len(series.Groups[idx].Values) < t {
				series.Groups[idx].Values = append(series.Groups[idx].Values, 0)
			}
			series.Groups[idx].Values = append(series.Groups[idx].Values, amount)
			series.Groups[idx].Total += amount
		}
	}

	// zero-fill trailing periods so every series aligns with Times
	for i := range series.Groups {
		for len(series.Groups[i].Values) < len(series.Times) {
			series.Groups[i].Values = append(series.Groups[i].Values, 0)
		}
		series.Total += series.Groups[i].Total
	}

	sort.SliceStable(series.Groups, func(i, j int) bool {
		return series.Groups[i].Total > series.Groups[j].Total
	})

	if len(series.Groups) > maxGroups {
		other := GroupSeries{Key: "Other", Values: make([]float64, len(series.Times))}
		for _, g := range series.Groups[maxGroups:] {
			for t, v := range g.Values {
				other.Values[t] += v
			}
			other.Total += g.Total
		}
		series.Groups = append(series.Groups[:maxGroups:maxGroups], other)
	}

	return series
}
