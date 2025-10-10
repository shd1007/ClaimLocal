using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Azure.Core;
using ClaimStatusApi.Models;

namespace ClaimStatusApi.Services;

// REST implementation using Azure OpenAI Chat Completions endpoint
public class OpenAiSummarizationService : ISummarizationService
{
    private static readonly JsonSerializerOptions JsonOpts = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        PropertyNameCaseInsensitive = true
    };

    private readonly ILogger<OpenAiSummarizationService> _logger;
    private readonly HttpClient _http;
    private readonly string _endpoint;
    private readonly string _deployment;
    private readonly TokenCredential _credential;

    public OpenAiSummarizationService(ILogger<OpenAiSummarizationService> logger, IConfiguration config, TokenCredential credential, IHttpClientFactory httpFactory)
    {
        _logger = logger;
        _credential = credential;
        _endpoint = config["OpenAI:Endpoint"]?.TrimEnd('/') ?? throw new InvalidOperationException("OpenAI:Endpoint not configured");
        _deployment = config["OpenAI:Deployment"] ?? throw new InvalidOperationException("OpenAI:Deployment not configured");
        _http = httpFactory.CreateClient("openai");
    }

    public async Task<ClaimSummaryResponse> SummarizeAsync(Claim claim, ClaimNoteSet noteSet, CancellationToken ct = default)
    {
        var notesPlain = string.Join("\n", noteSet.Notes.Select(n => $"- {n.Author}: {n.Text}"));
        var systemPrompt = "You are an insurance claims assistant. Create: (1) a concise general summary (2) a simple customer-facing summary (3) a more detailed adjuster summary with any missing info callouts (4) a single recommended next step phrase. Return JSON with keys summary, customerSummary, adjusterSummary, nextStep.";
        var userPrompt = $"Claim: {claim.Id} Type: {claim.Type} Status: {claim.Status} LossDate: {claim.LossDate} Notes:\n{notesPlain}";

        var url = $"{_endpoint}/openai/deployments/{_deployment}/chat/completions?api-version=2024-02-15-preview";

        var request = new
        {
            messages = new object[]
            {
                new { role = "system", content = systemPrompt },
                new { role = "user", content = userPrompt }
            },
            temperature = 0.4,
            max_tokens = 400
        };

        try
        {
            using var httpReq = new HttpRequestMessage(HttpMethod.Post, url)
            {
                Content = JsonContent.Create(request, options: JsonOpts)
            };

            // Acquire token via managed identity (default credential)
            var token = await _credential.GetTokenAsync(new TokenRequestContext(new[] { "https://cognitiveservices.azure.com/.default" }), ct);
            httpReq.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token.Token);

            var resp = await _http.SendAsync(httpReq, ct);
            var raw = await resp.Content.ReadAsStringAsync(ct);
            if (!resp.IsSuccessStatusCode)
            {
                _logger.LogWarning("OpenAI call failed: {Status} {Body}", resp.StatusCode, raw);
                return new ClaimSummaryResponse(claim.Id, "Summarization unavailable", "Summarization unavailable", "Summarization unavailable", "Retry later");
            }

            var parsed = JsonSerializer.Deserialize<ChatResponse>(raw, JsonOpts);
            var firstChoice = parsed?.Choices?.FirstOrDefault();
            var content = firstChoice?.Message?.Content ?? string.Empty;

            ClaimSummaryResponse? model = null;
            try
            {
                model = JsonSerializer.Deserialize<ClaimSummaryRaw>(content, JsonOpts)?.ToResponse(claim.Id);
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, "Parsing model JSON failed; returning raw content");
            }
            return model ?? new ClaimSummaryResponse(claim.Id, content, content, content, "Review details");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "OpenAI summarization failed");
            return new ClaimSummaryResponse(claim.Id, "Summarization unavailable", "Summarization unavailable", "Summarization unavailable", "Retry later");
        }
    }

    private sealed class ChatResponse
    {
        public List<ChatChoice>? Choices { get; set; }
    }
    private sealed class ChatChoice
    {
        public ChatMessage? Message { get; set; }
    }
    private sealed class ChatMessage
    {
        public string? Role { get; set; }
        public string? Content { get; set; }
    }

    private record ClaimSummaryRaw(string? Summary, string? CustomerSummary, string? AdjusterSummary, string? NextStep)
    {
        public ClaimSummaryResponse ToResponse(int claimId) => new(
            claimId,
            Summary ?? string.Empty,
            CustomerSummary ?? Summary ?? string.Empty,
            AdjusterSummary ?? Summary ?? string.Empty,
            NextStep ?? string.Empty);
    }
}
