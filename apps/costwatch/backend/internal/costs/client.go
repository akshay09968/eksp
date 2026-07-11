package costs

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/service/costexplorer"
)

// CostExplorerAPI is the consumer-side slice of the CE client: exactly the two
// calls the service makes, nothing more. Satisfied by *costexplorer.Client,
// the tests' mock, and demo mode.
type CostExplorerAPI interface {
	GetCostAndUsage(ctx context.Context, in *costexplorer.GetCostAndUsageInput,
		opts ...func(*costexplorer.Options)) (*costexplorer.GetCostAndUsageOutput, error)
	GetCostForecast(ctx context.Context, in *costexplorer.GetCostForecastInput,
		opts ...func(*costexplorer.Options)) (*costexplorer.GetCostForecastOutput, error)
}
