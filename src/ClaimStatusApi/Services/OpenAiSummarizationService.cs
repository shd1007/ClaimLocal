using Azure;
using Azure.AI.OpenAI;
using ClaimStatusApi.Models;
using OpenAI.Chat;
using System.ClientModel;
using System.Text.Json;

namespace ClaimStatusApi.Services;

// REST implementation using Azure OpenAI Chat Completions endpoint
public class OpenAiSummarizationService : ISummarizationService
{
    private readonly ILogger<OpenAiSummarizationService> _logger;
    private readonly AzureOpenAIClient _client;
    private readonly string _deployment;

    public OpenAiSummarizationService(ILogger<OpenAiSummarizationService> logger, IConfiguration config)
    {
        _logger = logger;
        var endpoint = config["OpenAI:Endpoint"] ?? throw new InvalidOperationException("OpenAI:Endpoint not configured");
        var apiKey = config["OpenAI:ApiKey"];
        _deployment = config["OpenAI:Deployment"] ?? throw new InvalidOperationException("OpenAI:Deployment not configured");
        AzureKeyCredential azureKeyCredential = new AzureKeyCredential(apiKey);
        var apiKeyCredential = new ApiKeyCredential(apiKey);
        _client = new AzureOpenAIClient(new Uri(endpoint), apiKeyCredential);
    }

    public async Task<ClaimSummaryResponse> SummarizeAsync(Claim claim, ClaimNoteSet noteSet, CancellationToken ct = default)
    {
        var notesPlain = string.Join("\n", noteSet.Notes.Select(n => $"- {n.Author}: {n.Text}"));
        var systemPrompt = "You are an insurance claims assistant. Create: (1) a concise general summary (2) a simple customer-facing summary (3) a more detailed adjuster summary with any missing info callouts (4) a single recommended next step phrase. Return JSON with keys summary, customerSummary, adjusterSummary, nextStep.";
        var userPrompt = $"Claim: {claim.Id} Type: {claim.Type} Status: {claim.Status} LossDate: {claim.LossDate} Notes:\n{notesPlain}";

        var requestOptions = new ChatCompletionOptions()
        {
            Temperature = 0.4f,
            MaxOutputTokenCount = 400,
            TopP = 1.0f,
            FrequencyPenalty = 0.0f,
            PresencePenalty = 0.0f
        };
        List<ChatMessage> messages = new List<ChatMessage>()
        {
            new SystemChatMessage(systemPrompt),
            new UserChatMessage(userPrompt),
        };
        try
        {
            var chatClient = _client.GetChatClient(_deployment);
            var response = chatClient.CompleteChat(messages, requestOptions);
            var content = response.Value.Content[0].Text ?? string.Empty;
            ClaimSummaryResponse? model = null;
            try
            {
               var rawModel = JsonSerializer.Deserialize<ClaimSummaryRaw>(content, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
               model = rawModel?.ToResponse(claim.Id);
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, "Parsing model JSON failed; returning raw content");
            }
            return model ?? new ClaimSummaryResponse(claim.Id, content, content, content, "Review details");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "AzureOpenAI summarization failed");
            return new ClaimSummaryResponse(claim.Id, "Summarization unavailable", "Summarization unavailable", "Summarization unavailable", "Retry later");
        }
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
