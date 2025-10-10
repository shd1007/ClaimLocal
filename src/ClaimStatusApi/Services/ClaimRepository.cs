using System.Text.Json;
using ClaimStatusApi.Models;

namespace ClaimStatusApi.Services;

public interface IClaimRepository
{
    Task<Claim?> GetClaimAsync(int id, CancellationToken ct = default);
    Task<IReadOnlyList<Claim>> GetAllClaimsAsync(CancellationToken ct = default);
    Task<ClaimNoteSet?> GetNotesAsync(int id, CancellationToken ct = default);
}

public class ClaimRepository : IClaimRepository
{
    private readonly ILogger<ClaimRepository> _logger;
    private readonly string _claimsPath;
    private readonly string _notesPath;
    private readonly JsonSerializerOptions _jsonOptions = new(JsonSerializerDefaults.Web);

    private IReadOnlyList<Claim>? _claimsCache;
    private IReadOnlyDictionary<int, ClaimNoteSet>? _notesCache;
    private readonly SemaphoreSlim _loadLock = new(1,1);

    public ClaimRepository(ILogger<ClaimRepository> logger, IWebHostEnvironment env)
    {
        _logger = logger;
        _claimsPath = Path.Combine(env.ContentRootPath, "claims.json");
        _notesPath = Path.Combine(env.ContentRootPath, "notes.json");
    }

    public async Task<Claim?> GetClaimAsync(int id, CancellationToken ct = default)
    {
        await EnsureLoadedAsync(ct);
        return _claimsCache!.FirstOrDefault(c => c.Id == id);
    }

    public async Task<IReadOnlyList<Claim>> GetAllClaimsAsync(CancellationToken ct = default)
    {
        await EnsureLoadedAsync(ct);
        return _claimsCache!;
    }

    public async Task<ClaimNoteSet?> GetNotesAsync(int id, CancellationToken ct = default)
    {
        await EnsureLoadedAsync(ct);
        return _notesCache!.TryGetValue(id, out var set) ? set : null;
    }

    private async Task EnsureLoadedAsync(CancellationToken ct)
    {
        if (_claimsCache != null && _notesCache != null) return;
        await _loadLock.WaitAsync(ct);
        try
        {
            if (_claimsCache == null)
            {
                using var s = File.OpenRead(_claimsPath);
                var claims = await JsonSerializer.DeserializeAsync<List<ClaimDto>>(s, _jsonOptions, ct) ?? new();
                _claimsCache = claims.Select(dto => dto.ToModel()).ToList();
            }
            if (_notesCache == null)
            {
                using var s = File.OpenRead(_notesPath);
                var notes = await JsonSerializer.DeserializeAsync<List<ClaimNoteSetDto>>(s, _jsonOptions, ct) ?? new();
                _notesCache = notes.Select(n => n.ToModel()).ToDictionary(n => n.Id);
            }
        }
        finally
        {
            _loadLock.Release();
        }
    }

    private record ClaimDto(
        int Id,
        string PolicyNumber,
        string Type,
        string Status,
        string LossDate,
        string InsuredName,
        decimal AmountClaimed,
        decimal AmountReserved,
        DateTime LastUpdated
    )
    {
        public Claim ToModel() => new(
            Id,
            PolicyNumber,
            Type,
            Status,
            DateOnly.Parse(LossDate),
            InsuredName,
            AmountClaimed,
            AmountReserved,
            DateTime.SpecifyKind(LastUpdated, DateTimeKind.Utc));
    }

    private record ClaimNoteSetDto(int Id, List<ClaimNote> Notes)
    {
        public ClaimNoteSet ToModel() => new ClaimNoteSet { Id = Id, Notes = Notes };
    }
}
