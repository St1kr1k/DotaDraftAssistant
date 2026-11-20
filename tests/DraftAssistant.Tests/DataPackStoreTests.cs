using System.Text.Json;
using DraftAssistant.Application.Abstractions;
using DraftAssistant.Infrastructure.Storage;
using Xunit;

namespace DraftAssistant.Tests;

public sealed class DataPackStoreTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "dda_packs_" + Guid.NewGuid().ToString("N"));
    private string Bundled => Path.Combine(_root, "bundled");
    private string Downloads => Path.Combine(_root, "downloads");

    public void Dispose()
    {
        try { Directory.Delete(_root, true); } catch (IOException) { }
    }

    private static void WritePatch(string root, DateTimeOffset fetchedAt, bool packFile = true)
    {
        var dir = DataFiles.PatchDir(root);
        Directory.CreateDirectory(dir);
        File.WriteAllText(Path.Combine(dir, "meta.json"),
            JsonSerializer.Serialize(new PatchMetaDto { Patch = "7.40", FetchedAt = fetchedAt }, DataFiles.Json));
        if (packFile)
            File.WriteAllText(Path.Combine(dir, DataPackStore.PackFile),
                JsonSerializer.Serialize(new PackMetaDto { Patch = "7.40", FetchedAt = fetchedAt }, DataFiles.Json));
    }

    private static void WriteHeroes(string root, params int[] ids)
    {
        Directory.CreateDirectory(DataFiles.HeroesDir(root));
        File.WriteAllText(DataFiles.HeroesJson(root),
            JsonSerializer.Serialize(ids.Select(id => new HeroDto { Id = id, Name = $"h{id}" }).ToList(), DataFiles.Json));
    }

    private DataPackStore Store() => new(Bundled, Downloads, NullLog.Instance);

    [Fact]
    public void NoDownloads_UsesBundled()
    {
        WritePatch(Bundled, DateTimeOffset.UtcNow, packFile: false);
        WriteHeroes(Bundled, 1, 2);
        Assert.Equal(Bundled, Store().ResolvePatchRoot());
        Assert.Equal(Bundled, Store().ResolveHeroesRoot());
    }

    [Fact]
    public void NewerDownloadedStats_AreUsed_OlderAreNot()
    {
        var t = DateTimeOffset.UtcNow;
        WritePatch(Bundled, t, packFile: false);
        WriteHeroes(Bundled, 1, 2);
        var older = Path.Combine(Downloads, "20260101_000000");
        WritePatch(older, t.AddDays(-1));
        Assert.Equal(Bundled, Store().ResolvePatchRoot());

        var newer = Path.Combine(Downloads, "20260102_000000");
        WritePatch(newer, t.AddDays(1));
        Assert.Equal(newer, Store().ResolvePatchRoot());
        // Портретов в пакете нет — герои остаются встроенные.
        Assert.Equal(Bundled, Store().ResolveHeroesRoot());
    }

    [Fact]
    public void DownloadedHeroes_UsedOnlyWhenNewHeroesAppeared()
    {
        WritePatch(Bundled, DateTimeOffset.UtcNow);
        WriteHeroes(Bundled, 1, 2);
        var same = Path.Combine(Downloads, "20260101_000000");
        WriteHeroes(same, 1, 2);
        Assert.Equal(Bundled, Store().ResolveHeroesRoot());

        var withNew = Path.Combine(Downloads, "20260102_000000");
        WriteHeroes(withNew, 1, 2, 3);
        Assert.Equal(withNew, Store().ResolveHeroesRoot());
    }

    [Fact]
    public void Cleanup_KeepsUsedAndTwoNewest_RemovesUnfinished()
    {
        WritePatch(Bundled, DateTimeOffset.UtcNow);
        var dirs = new[] { "20260101_000000", "20260102_000000", "20260103_000000", "20260104_000000" }
            .Select(n => Path.Combine(Downloads, n)).ToList();
        foreach (var d in dirs) WritePatch(d, DateTimeOffset.UtcNow);
        Directory.CreateDirectory(Path.Combine(Downloads, "20260105_000000.tmp"));

        Store().Cleanup(dirs[0]);

        Assert.True(Directory.Exists(dirs[0]));
        Assert.False(Directory.Exists(dirs[1]));
        Assert.True(Directory.Exists(dirs[2]));
        Assert.True(Directory.Exists(dirs[3]));
        Assert.False(Directory.Exists(Path.Combine(Downloads, "20260105_000000.tmp")));
    }
}
