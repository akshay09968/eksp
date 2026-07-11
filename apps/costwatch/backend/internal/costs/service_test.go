package costs

import (
	"context"
	"errors"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/costexplorer"
	cetypes "github.com/aws/aws-sdk-go-v2/service/costexplorer/types"
)

type mockCE struct {
	mu        sync.Mutex
	calls     atomic.Int64
	pages     []*costexplorer.GetCostAndUsageOutput
	err       error
	forecast  *costexplorer.GetCostForecastOutput
	lastInput *costexplorer.GetCostAndUsageInput
}

func (m *mockCE) GetCostAndUsage(_ context.Context, in *costexplorer.GetCostAndUsageInput,
	_ ...func(*costexplorer.Options)) (*costexplorer.GetCostAndUsageOutput, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.calls.Add(1)
	m.lastInput = in
	if m.err != nil {
		return nil, m.err
	}
	// page through the configured outputs using NextPageToken
	idx := 0
	if in.NextPageToken != nil {
		idx = 1
	}
	return m.pages[idx], nil
}

func (m *mockCE) GetCostForecast(_ context.Context, _ *costexplorer.GetCostForecastInput,
	_ ...func(*costexplorer.Options)) (*costexplorer.GetCostForecastOutput, error) {
	if m.forecast == nil {
		return &costexplorer.GetCostForecastOutput{
			Total: &cetypes.MetricValue{Amount: aws.String("0"), Unit: aws.String("USD")},
		}, nil
	}
	return m.forecast, nil
}

func page(token *string, results ...cetypes.ResultByTime) *costexplorer.GetCostAndUsageOutput {
	return &costexplorer.GetCostAndUsageOutput{
		NextPageToken: token,
		ResultsByTime: results,
	}
}

func resultAt(start string, groups map[string]string) cetypes.ResultByTime {
	r := cetypes.ResultByTime{
		TimePeriod: &cetypes.DateInterval{Start: aws.String(start), End: aws.String(start)},
	}
	for key, amount := range groups {
		r.Groups = append(r.Groups, cetypes.Group{
			Keys: []string{key},
			Metrics: map[string]cetypes.MetricValue{
				"UnblendedCost": {Amount: aws.String(amount), Unit: aws.String("USD")},
			},
		})
	}
	return r
}

func TestCostsAggregatesAcrossPages(t *testing.T) {
	token := "next"
	m := &mockCE{pages: []*costexplorer.GetCostAndUsageOutput{
		page(&token, resultAt("2026-07-01", map[string]string{"Amazon EC2": "10.5", "Amazon S3": "2.0"})),
		page(nil, resultAt("2026-07-02", map[string]string{"Amazon EC2": "12.0"})),
	}}
	svc := NewService(m, WithTTL(time.Hour))

	series, err := svc.Costs(context.Background(), Query{Granularity: Daily, GroupBy: "SERVICE", Days: 2})
	if err != nil {
		t.Fatalf("Costs: %v", err)
	}

	if len(series.Times) != 2 {
		t.Fatalf("times = %v, want 2 periods", series.Times)
	}
	if len(series.Groups) != 2 {
		t.Fatalf("groups = %d, want 2", len(series.Groups))
	}
	// sorted by total desc: EC2 (22.5) first
	if series.Groups[0].Key != "Amazon EC2" || series.Groups[0].Total != 22.5 {
		t.Fatalf("top group = %+v, want EC2 total 22.5", series.Groups[0])
	}
	// S3 has no data for period 2 — zero-filled, aligned lengths
	if len(series.Groups[1].Values) != 2 || series.Groups[1].Values[1] != 0 {
		t.Fatalf("S3 values = %v, want zero-filled second period", series.Groups[1].Values)
	}
	if series.Total != 24.5 {
		t.Fatalf("total = %v, want 24.5", series.Total)
	}
}

func TestCostsCachesByQueryShape(t *testing.T) {
	m := &mockCE{pages: []*costexplorer.GetCostAndUsageOutput{
		page(nil, resultAt("2026-07-01", map[string]string{"Amazon EC2": "1"})),
	}}
	svc := NewService(m, WithTTL(time.Hour))
	q := Query{Granularity: Daily, GroupBy: "SERVICE", Days: 7}

	first, err := svc.Costs(context.Background(), q)
	if err != nil {
		t.Fatalf("first: %v", err)
	}
	second, err := svc.Costs(context.Background(), q)
	if err != nil {
		t.Fatalf("second: %v", err)
	}

	if got := m.calls.Load(); got != 1 {
		t.Fatalf("CE called %d times, want 1 (cache hit)", got)
	}
	if first.Cached || !second.Cached {
		t.Fatalf("cached flags = %v,%v — want false,true", first.Cached, second.Cached)
	}
}

func TestCostsCoalescesConcurrentCalls(t *testing.T) {
	m := &mockCE{pages: []*costexplorer.GetCostAndUsageOutput{
		page(nil, resultAt("2026-07-01", map[string]string{"Amazon EC2": "1"})),
	}}
	svc := NewService(m, WithTTL(time.Hour))
	q := Query{Granularity: Daily, GroupBy: "SERVICE", Days: 7}

	var wg sync.WaitGroup
	for range 8 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := svc.Costs(context.Background(), q); err != nil {
				t.Errorf("concurrent Costs: %v", err)
			}
		}()
	}
	wg.Wait()

	if got := m.calls.Load(); got != 1 {
		t.Fatalf("CE called %d times under concurrency, want 1 (singleflight)", got)
	}
}

func TestHourlyOptInErrorIsMapped(t *testing.T) {
	m := &mockCE{err: errors.New("ValidationException: Hourly granularity is not enabled for this account")}
	svc := NewService(m, WithTTL(time.Hour))

	_, err := svc.Costs(context.Background(), Query{Granularity: Hourly, GroupBy: "SERVICE", Days: 1})
	if !errors.Is(err, ErrHourlyNotEnabled) {
		t.Fatalf("err = %v, want ErrHourlyNotEnabled", err)
	}
}

func TestInvalidGroupByRejected(t *testing.T) {
	m := &mockCE{}
	svc := NewService(m, WithTTL(time.Hour))

	_, err := svc.Costs(context.Background(), Query{Granularity: Daily, GroupBy: "DROP TABLE", Days: 7})
	if err == nil || !strings.Contains(err.Error(), "groupBy") {
		t.Fatalf("err = %v, want groupBy validation error", err)
	}
	if m.calls.Load() != 0 {
		t.Fatal("CE must not be called for invalid input")
	}
}

func TestGroupCapFoldsIntoOther(t *testing.T) {
	groups := map[string]string{}
	for i := range 20 {
		groups["svc-"+string(rune('a'+i))] = "1.0"
	}
	groups["big"] = "100"
	m := &mockCE{pages: []*costexplorer.GetCostAndUsageOutput{
		page(nil, resultAt("2026-07-01", groups)),
	}}
	svc := NewService(m, WithTTL(time.Hour))

	series, err := svc.Costs(context.Background(), Query{Granularity: Daily, GroupBy: "SERVICE", Days: 1})
	if err != nil {
		t.Fatalf("Costs: %v", err)
	}
	if len(series.Groups) > maxGroups+1 {
		t.Fatalf("groups = %d, want ≤ %d incl. Other", len(series.Groups), maxGroups+1)
	}
	if series.Groups[0].Key != "big" {
		t.Fatalf("top group = %s, want 'big'", series.Groups[0].Key)
	}
	last := series.Groups[len(series.Groups)-1]
	if last.Key != "Other" {
		t.Fatalf("last group = %s, want fold into 'Other'", last.Key)
	}
}

func TestSummaryComputesDeltaAndMovers(t *testing.T) {
	// Summary calls GetCostAndUsage twice (MTD, prev-MTD) — distinguish by
	// TimePeriod since pagination isn't involved here.
	m := &summaryMock{}
	svc := NewService(m, WithTTL(time.Hour), WithNow(func() time.Time {
		return time.Date(2026, 7, 10, 12, 0, 0, 0, time.UTC)
	}))

	s, err := svc.Summary(context.Background())
	if err != nil {
		t.Fatalf("Summary: %v", err)
	}
	if s.MonthToDate != 300 {
		t.Fatalf("MTD = %v, want 300", s.MonthToDate)
	}
	if s.PrevMonthToDate != 200 {
		t.Fatalf("prev MTD = %v, want 200", s.PrevMonthToDate)
	}
	if s.DeltaPct != 50 {
		t.Fatalf("delta = %v%%, want 50%%", s.DeltaPct)
	}
	if s.ForecastMonthEnd != 900 {
		t.Fatalf("forecast = %v, want 900", s.ForecastMonthEnd)
	}
	if len(s.TopMovers) == 0 || s.TopMovers[0].Service != "Amazon EC2" {
		t.Fatalf("movers = %+v, want EC2 first", s.TopMovers)
	}
}

type summaryMock struct{ calls atomic.Int64 }

func (m *summaryMock) GetCostAndUsage(_ context.Context, in *costexplorer.GetCostAndUsageInput,
	_ ...func(*costexplorer.Options)) (*costexplorer.GetCostAndUsageOutput, error) {
	m.calls.Add(1)
	if *in.TimePeriod.Start >= "2026-07-01" { // current month window
		return page(nil, resultAt("2026-07-01", map[string]string{
			"Amazon EC2": "250", "Amazon S3": "50",
		})), nil
	}
	return page(nil, resultAt("2026-06-01", map[string]string{
		"Amazon EC2": "150", "Amazon S3": "50",
	})), nil
}

func (m *summaryMock) GetCostForecast(_ context.Context, _ *costexplorer.GetCostForecastInput,
	_ ...func(*costexplorer.Options)) (*costexplorer.GetCostForecastOutput, error) {
	return &costexplorer.GetCostForecastOutput{
		Total: &cetypes.MetricValue{Amount: aws.String("900"), Unit: aws.String("USD")},
	}, nil
}

func TestDemoModeIsDeterministic(t *testing.T) {
	d := NewDemoClient()
	svc := NewService(d, WithTTL(0)) // no cache — determinism must come from demo itself

	q := Query{Granularity: Daily, GroupBy: "SERVICE", Days: 30}
	a, err := svc.Costs(context.Background(), q)
	if err != nil {
		t.Fatalf("demo Costs: %v", err)
	}
	b, err := svc.Costs(context.Background(), q)
	if err != nil {
		t.Fatalf("demo Costs: %v", err)
	}
	if len(a.Groups) == 0 || len(a.Times) != 30 {
		t.Fatalf("demo series empty or wrong length: %d times", len(a.Times))
	}
	if a.Total != b.Total {
		t.Fatalf("demo not deterministic: %v vs %v", a.Total, b.Total)
	}

	// hourly must work in demo without any opt-in
	if _, err := svc.Costs(context.Background(), Query{Granularity: Hourly, GroupBy: "SERVICE", Days: 1}); err != nil {
		t.Fatalf("demo hourly: %v", err)
	}
}
