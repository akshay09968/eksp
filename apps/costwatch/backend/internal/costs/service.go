package costs

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/costexplorer"
	cetypes "github.com/aws/aws-sdk-go-v2/service/costexplorer/types"
)

// maxGroups caps distinct series returned to the UI; everything past it folds
// into "Other" (a categorical palette stops being readable past ~a dozen hues).
const maxGroups = 12

type Service struct {
	api         CostExplorerAPI
	cache       *cache
	now         func() time.Time
	allowedTags map[string]bool
}

type Option func(*Service)

// WithTTL sets the cache TTL; 0 disables caching (used by tests/demo checks).
func WithTTL(d time.Duration) Option {
	return func(s *Service) { s.cache = newCache(d) }
}

// WithAllowedTagKeys permits specific cost-allocation tag keys for
// groupBy=TAG:<key>. Default is none: every distinct tag key is a *billed* CE
// query and a long-lived cache entry, so the surface is closed until opened
// deliberately (AUDIT P0-1).
func WithAllowedTagKeys(keys []string) Option {
	return func(s *Service) {
		s.allowedTags = make(map[string]bool, len(keys))
		for _, k := range keys {
			if k = strings.TrimSpace(k); k != "" {
				s.allowedTags[k] = true
			}
		}
	}
}

// WithNow pins the clock — Summary math is date-window arithmetic and must be
// testable on a fixed day.
func WithNow(fn func() time.Time) Option {
	return func(s *Service) { s.now = fn }
}

func NewService(api CostExplorerAPI, opts ...Option) *Service {
	s := &Service{
		api:   api,
		cache: newCache(6 * time.Hour),
		now:   time.Now,
	}
	for _, opt := range opts {
		opt(s)
	}
	return s
}

func (s *Service) CacheStats() CacheStats { return s.cache.stats() }

// ---------------------------------------------------------------------------
// Costs
// ---------------------------------------------------------------------------

func (s *Service) Costs(ctx context.Context, q Query) (Series, error) {
	if err := q.normalize(s.allowedTags); err != nil {
		return Series{}, err
	}

	key := fmt.Sprintf("costs|%s|%s|%d", q.Granularity, q.GroupBy, q.Days)
	val, cached, err := s.cache.do(key, func() (any, error) {
		return s.fetchCosts(ctx, q)
	})
	if err != nil {
		return Series{}, err
	}
	series := val.(Series)
	series.Cached = cached
	return series, nil
}

func (q *Query) normalize(allowedTags map[string]bool) error {
	switch q.Granularity {
	case Hourly, Daily, Monthly:
	default:
		return fmt.Errorf("unsupported granularity %q (HOURLY|DAILY|MONTHLY)", q.Granularity)
	}

	if tag, ok := strings.CutPrefix(q.GroupBy, "TAG:"); ok {
		if !allowedTags[tag] {
			return fmt.Errorf("unsupported groupBy tag key %q — set ALLOWED_TAG_KEYS to permit specific cost-allocation tags", tag)
		}
	} else if !ValidGroupBys[q.GroupBy] {
		return fmt.Errorf("unsupported groupBy %q", q.GroupBy)
	}

	switch q.Granularity {
	case Hourly:
		q.Days = clamp(q.Days, 1, 14) // CE hard limit for hourly data
	case Daily:
		q.Days = clamp(q.Days, 1, 365)
		if q.Days == 1 {
			q.Days = 30
		}
	case Monthly:
		q.Days = clamp(q.Days, 30, 390)
	}
	return nil
}

func clamp(v, min, max int) int {
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}

func (s *Service) fetchCosts(ctx context.Context, q Query) (Series, error) {
	now := s.now().UTC()
	var start, end string
	switch q.Granularity {
	case Hourly:
		e := now.Truncate(time.Hour)
		st := e.Add(-time.Duration(q.Days) * 24 * time.Hour)
		start, end = st.Format(time.RFC3339), e.Format(time.RFC3339)
	case Daily:
		start = now.AddDate(0, 0, -q.Days).Format("2006-01-02")
		end = now.Format("2006-01-02")
	case Monthly:
		months := q.Days / 30
		first := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
		start = first.AddDate(0, -(months - 1), 0).Format("2006-01-02")
		end = now.Format("2006-01-02")
	}

	groupDef := cetypes.GroupDefinition{
		Type: cetypes.GroupDefinitionTypeDimension,
		Key:  aws.String(q.GroupBy),
	}
	if tag, ok := strings.CutPrefix(q.GroupBy, "TAG:"); ok {
		groupDef = cetypes.GroupDefinition{
			Type: cetypes.GroupDefinitionTypeTag,
			Key:  aws.String(tag),
		}
	}

	input := &costexplorer.GetCostAndUsageInput{
		TimePeriod:  &cetypes.DateInterval{Start: aws.String(start), End: aws.String(end)},
		Granularity: cetypes.Granularity(q.Granularity),
		Metrics:     []string{"UnblendedCost"},
		GroupBy:     []cetypes.GroupDefinition{groupDef},
	}

	var results []cetypes.ResultByTime
	for {
		out, err := s.api.GetCostAndUsage(ctx, input)
		if err != nil {
			return Series{}, mapCEError(err)
		}
		results = append(results, out.ResultsByTime...)
		if out.NextPageToken == nil || *out.NextPageToken == "" {
			break
		}
		input.NextPageToken = out.NextPageToken
	}

	return s.aggregate(results), nil
}

func mapCEError(err error) error {
	msg := err.Error()
	if strings.Contains(strings.ToLower(msg), "hourly") {
		return fmt.Errorf("%w: %v", ErrHourlyNotEnabled, err)
	}
	return err
}
