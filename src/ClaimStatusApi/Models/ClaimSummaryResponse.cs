namespace ClaimStatusApi.Models;

public record ClaimSummaryResponse(
    int ClaimId,
    string Summary,
    string CustomerSummary,
    string AdjusterSummary,
    string NextStep
);
