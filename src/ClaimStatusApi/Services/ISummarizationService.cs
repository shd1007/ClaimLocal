using ClaimStatusApi.Models;

namespace ClaimStatusApi.Services;

public interface ISummarizationService
{
    Task<ClaimSummaryResponse> SummarizeAsync(Claim claim, ClaimNoteSet noteSet, CancellationToken ct = default);
}
