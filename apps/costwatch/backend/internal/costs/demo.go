package costs

import (
	"context"
	"fmt"
	"hash/fnv"
	"math"
	"sort"
	"strconv"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/costexplorer"
	cetypes "github.com/aws/aws-sdk-go-v2/service/costexplorer/types"
)

// DemoClient implements CostExplorerAPI with deterministic synthetic data:
// run the full UI with zero AWS access (`make costwatch-demo`), screenshot it,
// test against it. Determinism is a feature — same inputs, same dashboard.
type DemoClient struct{}

func NewDemoClient() *DemoClient { return &DemoClient{} }

// base daily USD costs shaped like a real small EKS platform bill
var demoServices = map[string]float64{
	"Amazon Elastic Compute Cloud - Compute": 41.80,
	"Amazon Elastic Kubernetes Service":      7.20,
	"Amazon Relational Database Service":     17.50,
	"EC2 - Other":                            9.40, // NAT, EBS, data transfer
	"Amazon Simple Storage Service":          4.30,
	"AmazonCloudWatch":                       3.10,
	"Elastic Load Balancing":                 5.60,
	"Amazon EC2 Container Registry (ECR)":    1.20,
	"Amazon Route 53":                        0.50,
	"AWS Cost Explorer":                      0.30,
	"Amazon Virtual Private Cloud":           2.40,
	"AWS Key Management Service":             0.90,
	"Amazon DynamoDB":                        0.70,
	"AWS Lambda":                             0.40,
}

func demoKeys(groupBy string) map[string]float64 {
	switch groupBy {
	case "REGION":
		return map[string]float64{"ap-south-1": 78.0, "us-east-1": 12.0, "eu-west-1": 5.0}
	case "LINKED_ACCOUNT":
		return map[string]float64{"123456789012": 95.0}
	case "USAGE_TYPE":
		return map[string]float64{
			"APS3-BoxUsage:m7g.large": 22.0, "APS3-SpotUsage:c7g.xlarge": 14.0,
			"APS3-NatGateway-Hours": 3.2, "APS3-DataTransfer-Out-Bytes": 6.1,
			"APS3-TimedStorage-ByteHrs": 4.3, "APS3-LoadBalancerUsage": 5.6,
		}
	case "RESOURCE_ID":
		return map[string]float64{
			"i-0f3a1c9d2e8b47a01": 11.2, "i-0b7e4d1a9c3f52e88": 9.8,
			"nat-0a1b2c3d4e5f60718": 3.2, "vol-0c9d8e7f6a5b41230": 1.9,
			"arn:aws:elasticloadbalancing:ap-south-1:123456789012:loadbalancer/app/eksp/50dc6c495c0c9188": 5.6,
			"i-0e2d3c4b5a6978f10": 7.4,
		}
	default: // SERVICE and TAG:* use the service-shaped set
		return demoServices
	}
}

// wave produces a smooth deterministic multiplier: weekly seasonality plus a
// slow upward trend, phase-shifted per key so lines don't move in lockstep.
func wave(key string, t time.Time) float64 {
	h := fnv.New32a()
	h.Write([]byte(key))
	phase := float64(h.Sum32()%628) / 100 // 0..2π

	day := float64(t.Unix()) / 86400
	weekly := 0.15 * math.Sin(2*math.Pi*day/7+phase)
	daily := 0.05 * math.Sin(2*math.Pi*float64(t.Hour())/24+phase)
	trend := 0.003 * (day - 20600) // gentle growth around mid-2026

	return 1 + weekly + daily + trend
}

func (d *DemoClient) GetCostAndUsage(_ context.Context, in *costexplorer.GetCostAndUsageInput,
	_ ...func(*costexplorer.Options)) (*costexplorer.GetCostAndUsageOutput, error) {

	layout := "2006-01-02"
	step := 24 * time.Hour
	if in.Granularity == cetypes.GranularityHourly {
		layout = time.RFC3339
		step = time.Hour
	}
	if in.Granularity == cetypes.GranularityMonthly {
		step = 0 // handled below
	}

	start, err := parseDemoTime(*in.TimePeriod.Start)
	if err != nil {
		return nil, fmt.Errorf("demo: bad start: %w", err)
	}
	end, err := parseDemoTime(*in.TimePeriod.End)
	if err != nil {
		return nil, fmt.Errorf("demo: bad end: %w", err)
	}

	groupBy := "SERVICE"
	if len(in.GroupBy) > 0 && in.GroupBy[0].Key != nil {
		groupBy = *in.GroupBy[0].Key
	}
	keys := demoKeys(groupBy)

	// Emit groups in sorted-key order: map iteration is randomized per process,
	// and float summation is non-associative — unordered emission made totals
	// differ in the last ULP between runs, breaking the determinism promise
	// (caught by TestDemoModeIsDeterministic under repeated runs).
	names := make([]string, 0, len(keys))
	for k := range keys {
		names = append(names, k)
	}
	sort.Strings(names)

	var results []cetypes.ResultByTime
	emit := func(pStart, pEnd time.Time, scale float64) {
		r := cetypes.ResultByTime{
			TimePeriod: &cetypes.DateInterval{
				Start: aws.String(pStart.Format(layout)),
				End:   aws.String(pEnd.Format(layout)),
			},
		}
		for _, key := range names {
			base := keys[key]
			amount := base * scale * wave(key, pStart)
			if in.Granularity == cetypes.GranularityHourly {
				amount /= 24
			}
			r.Groups = append(r.Groups, cetypes.Group{
				Keys: []string{key},
				Metrics: map[string]cetypes.MetricValue{
					"UnblendedCost": {
						Amount: aws.String(strconv.FormatFloat(amount, 'f', 6, 64)),
						Unit:   aws.String("USD"),
					},
				},
			})
		}
		results = append(results, r)
	}

	if in.Granularity == cetypes.GranularityMonthly {
		for cur := time.Date(start.Year(), start.Month(), 1, 0, 0, 0, 0, time.UTC); cur.Before(end); cur = cur.AddDate(0, 1, 0) {
			pEnd := cur.AddDate(0, 1, 0)
			if pEnd.After(end) {
				pEnd = end
			}
			days := pEnd.Sub(maxTime(cur, start)).Hours() / 24
			emit(maxTime(cur, start), pEnd, days)
		}
	} else {
		for cur := start; cur.Before(end); cur = cur.Add(step) {
			emit(cur, cur.Add(step), 1)
		}
	}

	return &costexplorer.GetCostAndUsageOutput{ResultsByTime: results}, nil
}

func (d *DemoClient) GetCostForecast(_ context.Context, in *costexplorer.GetCostForecastInput,
	_ ...func(*costexplorer.Options)) (*costexplorer.GetCostForecastOutput, error) {

	start, _ := parseDemoTime(*in.TimePeriod.Start)
	end, _ := parseDemoTime(*in.TimePeriod.End)
	days := end.Sub(start).Hours() / 24

	// Sorted iteration for the same ULP-determinism reason as GetCostAndUsage.
	names := make([]string, 0, len(demoServices))
	for k := range demoServices {
		names = append(names, k)
	}
	sort.Strings(names)

	var daily float64
	for _, key := range names {
		daily += demoServices[key] * wave(key, start)
	}

	return &costexplorer.GetCostForecastOutput{
		Total: &cetypes.MetricValue{
			Amount: aws.String(strconv.FormatFloat(daily*days, 'f', 2, 64)),
			Unit:   aws.String("USD"),
		},
	}, nil
}

func parseDemoTime(s string) (time.Time, error) {
	if t, err := time.Parse("2006-01-02", s); err == nil {
		return t, nil
	}
	return time.Parse(time.RFC3339, s)
}

func maxTime(a, b time.Time) time.Time {
	if a.After(b) {
		return a
	}
	return b
}
