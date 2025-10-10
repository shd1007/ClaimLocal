namespace ClaimStatusApi.Models;

public record Claim(
    int Id,
    string PolicyNumber,
    string Type,
    string Status,
    DateOnly LossDate,
    string InsuredName,
    decimal AmountClaimed,
    decimal AmountReserved,
    DateTime LastUpdated
);
