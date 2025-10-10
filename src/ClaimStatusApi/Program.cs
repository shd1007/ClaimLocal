using System.Reflection;
using Azure.Identity;
using ClaimStatusApi.Models;
using ClaimStatusApi.Services;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

// Serilog
builder.Host.UseSerilog((ctx, lc) => lc
    .ReadFrom.Configuration(ctx.Configuration)
    .WriteTo.Console());

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddHttpClient();

builder.Services.AddSingleton<IClaimRepository, ClaimRepository>();

// Summarization service wiring - uses managed identity / default credential
builder.Services.AddSingleton<ISummarizationService>(sp =>
{
    var cfg = sp.GetRequiredService<IConfiguration>();
    var cred = new DefaultAzureCredential();
    return new OpenAiSummarizationService(sp.GetRequiredService<ILogger<OpenAiSummarizationService>>(), cfg, cred, sp.GetRequiredService<IHttpClientFactory>());
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.MapGet("/healthz", () => Results.Ok(new { status = "ok", assembly = Assembly.GetExecutingAssembly().GetName().Version?.ToString() }))
    .WithName("Health")
    .WithOpenApi();

app.MapGet("/claims/{id:int}", async (int id, IClaimRepository repo, CancellationToken ct) =>
{
    var claim = await repo.GetClaimAsync(id, ct);
    return claim is null ? Results.NotFound() : Results.Ok(claim);
})
.WithName("GetClaimById")
.WithOpenApi(op => { op.Summary = "Get claim by id"; return op; });

app.MapPost("/claims/{id:int}/summarize", async (int id, IClaimRepository repo, ISummarizationService summarizer, CancellationToken ct) =>
{
    var claim = await repo.GetClaimAsync(id, ct);
    if (claim is null) return Results.NotFound();
    var notes = await repo.GetNotesAsync(id, ct) ?? new ClaimNoteSet { Id = id };
    var summary = await summarizer.SummarizeAsync(claim, notes, ct);
    return Results.Ok(summary);
})
.WithName("SummarizeClaim")
.WithOpenApi(op => { op.Summary = "Summarize claim notes via Azure OpenAI"; return op; });

app.Run();
