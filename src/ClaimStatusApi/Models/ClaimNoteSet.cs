namespace ClaimStatusApi.Models;

public class ClaimNoteSet
{
    public int Id { get; set; }
    public List<ClaimNote> Notes { get; set; } = new();
}

public class ClaimNote
{
    public string Author { get; set; } = string.Empty;
    public string Text { get; set; } = string.Empty;
}
